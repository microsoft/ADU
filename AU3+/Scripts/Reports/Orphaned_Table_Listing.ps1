#* FileName: Orphaned_Table_Listing.ps1
#*=====================================================================
#* Script Name: OrphanedTableListing.ps1
#* Created: [04/04/2017]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=====================================================================
#* Purpose: List orphaned tables in a database
#*          Table on CMPxx nodes have no matching table on CTL01
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
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged


#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
	{
		# Domain name and CTL host name
		$PDWHOST = GetNodeList -ctl	
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFileTXT = "D:\PDWDiagnostics\TableHealth\OrphanedTableListing_$CurrTime.txt"
		$OutputFileCSV = "D:\PDWDiagnostics\TableHealth\OrphanedTableListing_$CurrTime.csv"
		$OutputFileHTML = "D:\PDWDiagnostics\TableHealth\OrphanedTableListing_$CurrTime.html"
		if (!(test-path "D:\PDWDiagnostics\TableHealth"))
			{
				New-item "D:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
			}
		if (!(test-path $OutputFileTXT))
			{
				New-Item $OutputFileTXT -ItemType File|out-null
			}
		if (!(test-path $OutputFileCSv))
			{
				New-Item $OutputFileCSV -ItemType File|out-null
			}
		if (!(test-path $OutputFileHTML))
			{
				New-Item $OutputFileHTML -ItemType File|out-null
			}

		# Get username and credentials
		
		if(!$username)
			{   $PDWUID = GetPdwUsername; $PDWPWD = GetPdwPassword }
		else
			{   $PDWUID = $username; $PDWPWD = $password }	
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}	
if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD))
{

    write-error "failed to validate credentials"
}


function Get-CTL01MappedDatabaseName ($dbname)
	{	
		$SQLQuery = "SELECT d.name as DBName, dm.physical_name as Mapped_DB
                     FROM sys.databases d INNER JOIN sys.pdw_database_mappings dm ON d.database_id = dm.database_id
                     WHERE d.name = '" + $dbname + "';"

		$rset_MappedDBName = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD 
		$MappedDBName=$rset_MappedDBName.Mapped_DB
        
        return $MappedDBName
	}

function Get-CTL01MappedTableList($dbname)
	{	
	  
      $rset_MappedTableNames = @{}
      $SQLQuery = "SELECT DISTINCT tm.physical_name AS Mapped_Table
		             FROM [" + $dbname + "].[sys].[objects] o INNER JOIN [" + $dbname + "].[sys].[pdw_table_mappings] tm ON o.object_id = tm.object_id
				     ORDER BY 1;"

		$rset_MappedTableNames = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD 

        return $rset_MappedTableNames
	}

function Get-CMPxxTableNames($CMPNode, $dbname)
	{

		$SQLQuery = "SELECT '$CMPNode' AS CMPNode, '$dbname' AS DBName, o.name AS TableName FROM [$dbname].[sys].[objects] o WHERE type = 'U' ORDER BY 3;"
		$rset_CMPTableNames = $NULL
        $rset_CMPTableNames = Invoke-Sqlcmd -Query "$SQLQuery" -ServerInstance "$CMPNode" -Database $dbname

        Return $rset_CMPTableNames

	}



## ===================================================================================================================================================================
Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
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
$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb') order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD


$tblDBSummary = $NULL
$tblDBSummary = New-Object system.Data.DataTable "DatabaseSummary"
$colDatabaseName = New-Object system.Data.DataColumn DatabaseName,([string])
$colTableCount = New-Object system.Data.DataColumn TableCount,([int])
$tblDBSummary.columns.add($colDatabaseName)
$tblDBSummary.columns.add($colTableCount)

$tblOrphanedTables = $NULL
$tblOrphanedTables = New-Object system.Data.DataTable "CmpNodeTableList"
$colUserDatabaseName = New-Object system.Data.DataColumn DatabaseName,([string])
$colMappedDatabaseName = New-Object system.Data.DataColumn MappedDatabaseName,([string])
$colCmpNode = New-Object system.Data.DataColumn NodeName,([string])
$colMappedTableName = New-Object system.Data.DataColumn MappedTableName,([string])
$tblOrphanedTables.columns.add($colUserDatabaseName)
$tblOrphanedTables.columns.add($colMappedDatabaseName)
$tblOrphanedTables.columns.add($colCmpNode)
$tblOrphanedTables.columns.add($colMappedTableName)


#Empty body to hold the html fragments
$HTMLSummary=@()
$HTMLSummary += "<h2>______________________________________________________</h2>"
$HTMLSummary += "<h2>Summary</h2>"
$HTMLbody=@()
$HTMLbody += "<h2>______________________________________________________</h2>"

## For each db, 
##   Get the mapped DB name
##   Get the list of mapped tables
##   On each CMP node SQL Instance, get the list of tables
##   Match the CMP node table list with the list if mapped tables from CTL01,
##      Report tables on the CMP node that arent in the mapped table list
do
{
	#create the initial menu array
	$TableMenuOptions=@()
	$TableMenuOptions = (
		#@{"header"="Select a database or all"},
		@{"header"="Run for All Databases"},
		"All DBs",
		@{"header"="Select a single database"}
	)

    # Add the DB names to the array
	for ($i=1;$i -le @($dbs).count; $i++) {$TableMenuOptions+=($($dbs[$i-1].name))}

	[string]$ans = OutputMenu -header "Orphaned Table Listing" -options $TableMenuOptions
	if($ans -eq "q"){break}
		
	if ($ans -eq "All DBs")
	{
		$db=@()
		$db = $dbs.name
	}
	else{$db=$ans}
	
   
	foreach ($database in $db)
		{
          $UserDBName = $database  
          $MappedDBName = Get-CTL01MappedDatabaseName $database
          Write-Host "Processing: [$UserDBName] (mapped to [$MappedDBName])"  -ForegroundColor Green

	      $MappedTableList = @{}
	      $MappedTableList = Get-CTL01MappedTableList $database 
          $MappedTableHash=@{}
          foreach ($MappedTable in $MappedTableList)
            {
              $MappedTableHash.Add($MappedTable.Mapped_Table, $MappedTable.Mapped_Table)
            }


          foreach ($node in $CMPList)
	        {
              Write-Host "  Processing: $Node"  -ForegroundColor DarkGreen
              $CmpNodeTables = @{}
	          $CmpNodeTables = Get-CMPxxTableNames $node $MappedDBName 
              
              foreach ($CMPTable in $CmpNodeTables)
                {
                  $CMPNodeTableName = $CMPTable.TableName
   
                  if ($MappedTableHash.ContainsKey($CMPNodeTableName) -eq $false)
                    {
                      $NewOrphanedTablesRow = $tblOrphanedTables.NewRow()
                      $NewOrphanedTablesRow.NodeName = $CmpTable.CMPNode
                      $NewOrphanedTablesRow.DatabaseName = $UserDBName
                      $NewOrphanedTablesRow.MappedDatabaseName = $CmpTable.DBName
                      $NewOrphanedTablesRow.MappedTableName = $CmpTable.TableName
                      $tblOrphanedTables.Rows.Add($NewOrphanedTablesRow)
                    }
                }

            }

          $TableCount = $tblOrphanedTables.items.count
          Write-Host " $TableCount Orphaned Tables Identified" -ForegroundColor Cyan              
          

          $NewDBSummaryRow = $tblDBSummary.NewRow()
          $NewDBSummaryRow.DatabaseName = $UserDBName
          $NewDBSummaryRow.TableCount = $TableCount
          $tblDBSummary.Rows.Add($NewDBSummaryRow)  


          $tblOrphanedTables | SELECT DatabaseName, MappedDatabaseName, NodeName, MappedTableName | ft -autosize  | out-file -append $OutputFileTXT


	      #build the body of the HTML
	      if ($tblOrphanedTables.items.count -gt 0)
	        {
	          $HTMLbody += "<h2>Database: [$UserDBName], mapped to [$MappedDBName]</h2><br>"
              $HTMLbody += $tblOrphanedTables | select @{label = "Compute Node" ; Expression = {$_.NodeName}}, @{label = "Orphaned Table Name" ; Expression = {$_.MappedTableName}} | ConvertTo-Html -Fragment 
	          $HTMLbody += "<h2>______________________________________________________</h2>"
	          $HTMLbody += "<br>"
	        }

	      $tblOrphanedTables | Export-Csv $OutputFileCSV -NoTypeInformation -Append
  
          $tblOrphanedTables.Clear()

        }


}while($ans -ne "q")

$Rptdate=Get-Date
$Appliance = (Get-Cluster).name.split("-")[0]

$HTMLSummary += $tblDBSummary | Sort-Object DatabaseName | select @{label = "Database" ; Expression = {$_.DatabaseName}}, @{label = "Orphaned Table Count" ; Expression = {$_.TableCount}} | ConvertTo-Html -Fragment

$HTMLOutput=@()
$HTMLOutput += $HTMLSummary
$HTMLOutput += $HTMLbody


#Defining the style
$HTMLhead = @"
	<style>
	BODY{background-color:AliceBlue;}
	TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
	TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:DarkCyan}
	TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:Lavender}
	</style>
"@
ConvertTo-Html -head $HTMLhead -PostContent $HTMLOutput -body "<H1>Orphaned Table Report</H1><H2>Appliance: $Appliance<br>Date: $Rptdate</H2>" | out-file $OutputFileHTML

$tblDBSummary | Sort-Object DatabaseName | select @{label = "Database" ; Expression = {$_.DatabaseName}}, @{label = "Orphaned Table Count" ; Expression = {$_.TableCount}}  | ft -AutoSize

Write-Host -ForegroundColor Cyan "`nOutput also located at: $OutputFileTXT (also .csv and .html)"



