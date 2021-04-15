#* FileName: RowStore_Table_Fragmentation.ps1
#*=====================================================================
#* Script Name: RowStore_Table_Fragmentation.ps1
#* Created: [02/02/2018]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqiremnts:
#*	
#* 
#* Keywords:
#*=====================================================================
#* Purpose: Scan CMP node database(s) for RowStore table fragmentation
#*=====================================================================

#*=====================================================================
#* REVISION HISTORY
#*=====================================================================
#* Modified: 
#* Changes:
#*=====================================================================

param([string]$username,[string]$password,[string]$database)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9920 -EntryType Information -message "Starting $source" #first event logged

Write-Host -ForegroundColor Red    "======================================================================================================="
Write-Host -ForegroundColor Red    "===                                             CAUTION                                             ==="
Write-Host -ForegroundColor Red    "======================================================================================================="
Write-Host -ForegroundColor Yellow "=== This function queries sys.dm_db_index_physical_stats on the SQL Instances on the Compute Nodes. ==="
Write-Host -ForegroundColor Yellow "=== The DMV is expensive to run in a large-scale SQL environment.                                   ==="
Write-Host -ForegroundColor Yellow "=== This function may cause performance issues and should not be run during busy periods.           ==="
Write-Host -ForegroundColor Yellow "=== Due to the cost and extended runtime for this process, the scope of the execution is limited.   ==="
Write-Host -ForegroundColor Yellow "=== You can only select a single database, and will then be required to enter a table name.         ==="
Write-Host -ForegroundColor Yellow "======================================================================================================="

$Continue = Read-Host "`nPlease type 'y' and [Enter] to proceed with this data collection"
If ( $Continue -ne "y") {
    Write-Host  "Response was not 'y', script is exiting" -ForegroundColor DarkYellow
    pause
    return
  }

#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
	{
		# Domain name and CTL host name
		$PDWHOST = GetNodeList -ctl	
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFileCSV = "D:\PDWDiagnostics\TableHealth\RowStoreTableFragmentation_$CurrTime.csv"
		if (!(test-path "D:\PDWDiagnostics\TableHealth"))
			{
				New-item "D:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
			}
		if (!(test-path $OutputFileCSv))
			{
				New-Item $OutputFileCSV -ItemType File|out-null
			}

		# Get username and credentials		
		if(!$username)
			{   $PDWUID = GetPdwUsername; $PDWPWD = GetPdwPassword }
		else
			{   $PDWUID = $username; $PDWPWD = $password }	
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9921	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}	
if ($PDWUID -eq $null -or $PDWUID -eq "")
  {

    write-error "UserName not entered - script is exiting" -ErrorAction SilentlyContinue
    Write-Host  "UserName not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }
	
if ($PDWPWD -eq $null -or $PDWPWD -eq "")
  {
    write-error "Password not entered - script is exiting" -ErrorAction SilentlyContinue
    Write-Host  "Password not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }

if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD))
  {

    write-error "UserName / Password authentication failed - script is exiting" -ErrorAction SilentlyContinue
    Write-Host  "UserName / Password authentication failed - script is exiting" -ForegroundColor Red
    pause
    return
  }


function Get-FragmentedTables ($dbname, $CMPNode, $TargetTableList)
  {
    $sum_rset_FragTables=@()
    
    foreach ($TargetTable in $TargetTableList) {
    
        $MappedTableName = $TargetTable.MappedTableName
        $SQLQuery = "
DECLARE @ObjId    INT

SELECT @ObjID = o.object_id
    FROM sys.objects o
    WHERE o.name = '$MappedTableName'

SELECT CMPNode,
		TableName, 
		Index_Type_Desc, 
		Table_Geometry, 
		MIN(avg_fragmentation_in_percent) AS MinFrag,
		MAX(avg_fragmentation_in_percent) AS MaxFrag,
		AVG(avg_fragmentation_in_percent) AS AvgFrag, 
		index_id
    FROM (
		SELECT	SUBSTRING(@@SERVERNAME, (CHARINDEX ('-', @@SERVERNAME) + 1), 99) AS CMPNode,
				o.[name] AS TableName,
				CASE 
					WHEN (SUBSTRING(o.[name], (LEN(o.[name]) - 1), 1) = '_') THEN 'Distributed'
					ELSE 'Replicated'
				END AS Table_Geometry,
				ips.index_type_desc,
				ips.avg_fragmentation_in_percent,
				ips.index_id
			from sys.dm_db_index_physical_stats(DB_ID(),@ObjID,NULL,NULL,'LIMITED') ips 
				INNER JOIN sys.objects o
					ON ips.[object_id] = o.[object_id]
			WHERE ips.index_id < 2
				) AS x
	GROUP BY CMPNode, TableName, Index_Type_Desc, Table_Geometry, index_id"
 
        $rset_FragTables = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance $CMPNode -Database $dbname -QueryTimeout 7200 -ErrorAction Stop
        $sum_rset_FragTables += $rset_FragTables
    
      } 

    return $sum_rset_FragTables
  }

function Get-CTL01MappedDatabaseName ($dbname)
	{	
		$SQLQuery = "
SELECT d.name as DBName, dm.physical_name as Mapped_DB
FROM sys.databases d INNER JOIN sys.pdw_database_mappings dm ON d.database_id = dm.database_id
WHERE d.name = '" + $dbname + "';"

		$rset_MappedDBName = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD 
		$MappedDBName=$rset_MappedDBName.Mapped_DB
        
        return $MappedDBName
	}

function Get-CTL01MappedTableList($dbname)
	{	
	  
      $rset_MappedTableNames = @{}
      $SQLQuery = "
SELECT DISTINCT s.[name] as Schema_Name, o.[name] As User_Table, tm.physical_name AS Mapped_Table
FROM [$dbname].[sys].[objects] o INNER JOIN [$dbname].[sys].[pdw_table_mappings] tm ON o.object_id = tm.object_id INNER JOIN [$dbname].[sys].[schemas] s ON o.schema_id = s.schema_id"

		$rset_MappedTableNames = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD 

        return $rset_MappedTableNames
	}

function Get-TableName ()
    {
        Write-Host "Enter the table name, as [schema].[tablename] or [tablename], " -ForegroundColor Cyan
        write-host "   Do not include the '[' and ']' delimiters" -ForegroundColor Cyan
        Write-host "   If [schema] isn't entered, it will be assumed to be [dbo] if multiple tables are found for different schema's." -ForegroundColor Cyan
        Write-host "   If [tablename] includes a period ('.'), you " -ForegroundColor Cyan -NoNewline
        Write-host "MUST" -ForegroundColor Yellow -NoNewline
        Write-host " include the schema." -ForegroundColor Cyan 

        $TableName = Read-Host "TableName"

        $Schema= ""
        if ($TableName  -like "*.*") 
          {
            $Schema = ($TableName.Split("."))[0]
            $TableName =  $TableName.Substring($Schema.Length + 1)
          }

        If ($Schema -eq "")
          {
            $SchemaList = $Schemas = ($tblUserMappedTableList | ?{$_.UserTableName -eq $TableName} | select UserSchemaName -Unique)
            If ($SchemaList.UserSchemaName.count -gt 1)
              {
                $Schema ="dbo"
              }
            else
              {
                $Schema = $SchemaList.UserSchemaName
              }
          }

        $TargetTableList = @() 
        $TargetTableList = $tblUserMappedTableList | ?{$_.UserSchemaName -eq $Schema -and $_.UserTableName -eq $TableName} | SELECT MappedTableName

        return $TargetTableList
    }



function Main {
    ## ===================================================================================================================================================================

    Write-Host -ForegroundColor Cyan "`n`nLoading SQL PowerShell Module..."
    LoadSqlPowerShell


    ## Get the CMPxx node list
    Try
    {
	    $CMPList=@()
	    $CMPList = GetNodeList -cmp
    }
    catch
    {
	    Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
    }


    ## Get list of database names
    $dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb', 'mavtdb') order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD


    $Rptdate = Get-Date
    $Appliance = (Get-Cluster).name.split("-")[0]
 
    do
    {
	    #create the initial menu array
	    $TableMenuOptions=@()
	    $TableMenuOptions = (
		    @{"header"="** This script can only be run for individual databases **"},
		    @{"header"="Select a database"}
	    )

        # Add the DB names to the array
	    for ($i=1;$i -le @($dbs).count; $i++) {$TableMenuOptions+=($($dbs[$i-1].name))}

        Clear-Host

	    [string]$ans = OutputMenu -header "Fragmented Table Listing" -options $TableMenuOptions
	    if($ans -eq "q"){break}
		
        $UserDBName=$ans
   
	    # create the DataTables
        # (a) table for the User / Mapped Table list
        $tblUserMappedTableList = $NULL
        $tblUserMappedTableList = New-Object system.Data.DataTable "MappedTableList"
        $colUUserSchemaName = New-Object system.Data.DataColumn UserSchemaName,([string])
        $colUUserTableName = New-Object system.Data.DataColumn UserTableName,([string])
        $colUMappedTableName = New-Object system.Data.DataColumn MappedTableName,([string])
        $tblUserMappedTableList.columns.add($colUUserSchemaName)
        $tblUserMappedTableList.columns.add($colUUserTableName)
        $tblUserMappedTableList.columns.add($colUMappedTableName)

        # (b) table for the data at the CMP node level - the Mapped tables
        $tblFrag = $NULL
        $tblFrag = New-Object system.Data.DataTable "TableFragmentationData"
        $colDatabaseName = New-Object system.Data.DataColumn DatabaseName,([string])
        $colCmpNode = New-Object system.Data.DataColumn NodeName,([string])
        $colUserTableName = New-Object system.Data.DataColumn UserTableName,([string])
        $colMappedTableName = New-Object system.Data.DataColumn MappedTableName,([string])
        $colIndexType = New-Object system.Data.DataColumn IndexType,([string])
        $colMinFrag_Pct = New-Object system.Data.DataColumn MinFrag_Pct,([decimal])
        $colMaxFrag_Pct = New-Object system.Data.DataColumn MaxFrag_Pct,([decimal])
        $colAvgFrag_Pct = New-Object system.Data.DataColumn AvgFrag_Pct,([decimal])
        $colFrag_Geometry = New-Object system.Data.DataColumn Geometry,([string])
        $tblFrag.columns.add($colDatabaseName)
        $tblFrag.columns.add($colCmpNode)
        $tblFrag.columns.add($colUserTableName)
        $tblFrag.columns.add($colMappedTableName)
        $tblFrag.columns.add($colIndexType)
        $tblFrag.columns.add($colMinFrag_Pct)
        $tblFrag.columns.add($colMaxFrag_Pct)
        $tblFrag.columns.add($colAvgFrag_Pct)
        $tblFrag.columns.add($colFrag_Geometry)


        $MappedDBName = Get-CTL01MappedDatabaseName $UserDBName

        $MappedTableList = @{}
        $MappedTableList = Get-CTL01MappedTableList $UserDBName
        ForEach ($MappedTable in $MappedTableList)
          {
            $NewTblRow = $tblUserMappedTableList.NewRow()
            $NewTblRow.UserSchemaName = $MappedTable.Schema_Name
            $NewTblRow.UserTableName = $MappedTable.User_Table
            $NewTblRow.MappedTableName = $MappedTable.Mapped_Table
            $tblUserMappedTableList.Rows.Add($NewTblRow)
          }

        $TargetTableList = @{}
        $TargetTableList = Get-TableName 

        if ($TargetTableList.count -gt 0 -or ( $TargetTableList.MappedTableName -ne "" -and $TargetTableList.MappedTableName -ne $null)) 
          {
            #Write-Host "Processing: [$UserDBName] "  -ForegroundColor Green

            foreach ($CMPNode in $CMPList)
              {
                Write-Host "  Capturing fragmentation data on $CMPNode "  -ForegroundColor Cyan
                $CmpNodeFragTables = @{}
	            $CmpNodeFragTables = Get-FragmentedTables $MappedDBName $CMPNode $TargetTableList

                foreach ($CmpNodeFragTable in $CmpNodeFragTables)
                    {
                    $CMPNodeTableName = $CmpNodeFragTable.TableName
 
                    $New_tblFrag_Row = $tblFrag.NewRow()
                    $New_tblFrag_Row.DatabaseName = $UserDBName
                    $New_tblFrag_Row.NodeName = $CmpNodeFragTable.CMPNode
                    $MappedTable = $CmpNodeFragTable.TableName
                    $UserTable = $MappedTableList | ?{$_.Mapped_Table -eq $MappedTable} | Select User_Table
                    $New_tblFrag_Row.UserTableName = $UserTable.User_Table
                    $New_tblFrag_Row.MappedTableName = $CmpNodeFragTable.TableName
                    $New_tblFrag_Row.IndexType = $CmpNodeFragTable.Index_Type_Desc
                    $New_tblFrag_Row.MinFrag_Pct = $CmpNodeFragTable.MinFrag
                    $New_tblFrag_Row.MaxFrag_Pct = $CmpNodeFragTable.MaxFrag
                    $New_tblFrag_Row.AvgFrag_Pct = $CmpNodeFragTable.AvgFrag
                    $New_tblFrag_Row.Geometry = $CmpNodeFragTable.Table_Geometry

                    $tblFrag.Rows.Add($New_tblFrag_Row)
                    } 

                }                

            #Write the data to a CSV
	        $tblFrag | Export-Csv $OutputFileCSV -NoTypeInformation -Append

        }
        else
          {
            Write-Host -ForegroundColor Red "`nTable was not found"
            pause
          }


    }while($ans -ne "q")

    $Rptdate=Get-Date
    $Appliance = (Get-Cluster).name.split("-")[0]

    Write-Host -ForegroundColor Cyan "`nOutput located at: $OutputFileCSV"

    Pause

  }


Main