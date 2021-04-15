#* FileName: AllTableSizes.ps1
#*=============================================
#* Script Name: AllTableSizes.ps1
#* Created: [1/31/2014]
#* Author: Vic Hermosillo
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	Cluster must be up
#* 
#* Keywords:
#*=============================================
#* Purpose: Collect table size details
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 3/5/2014
#* Changes:
#* 1. Event logging
#* 2. Error handling
#* 3. Column data table format for output
#* Modified: 3/6/2014
#* Changes:
#* 1. Improved error handling
#* Modified: 7/31/2015 timsalch
#* Changes
#* 1. Added schema name to tables
#* Modified: 04/12/2017 sfacer
#* Changes
#* 1. Removed DESC from order by on SELECT db names
#+ 2. Added '[]' around schema and table names
#* Modified: 10/04/2018 sfacer
#* Changes
#* 1. Changed login failure error handling
#* Modified: 08/06/2020 sfacer
#* Changes
#* 1. Fixed summarization of rows for # Distr & RR tables
#* 2. Added Data space data to the output
#*=============================================

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
		$PDWHOST = GetNodeList -ctl
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "D:\PDWDiagnostics\TableHealth\TableSizes_$CurrTime.txt"
		$OutputFileCSV = "D:\PDWDiagnostics\TableHealth\TableSizes_$CurrTime.csv"
		$OutputFileHTML = "D:\PDWDiagnostics\TableHealth\TableSizes_$CurrTime.html"

		if (!(test-path "D:\PDWDiagnostics\TableHealth"))
			{
				New-item "D:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
			}
		if (!(test-path $OutputFile))
			{
				New-Item $OutputFile -ItemType File|out-null
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
if ($PDWUID -eq $null -or $PDWUID -eq "")
  {
    Write-Host  "UserName not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }
	
if ($PDWPWD -eq $null -or $PDWPWD -eq "")
  {
    Write-Host  "Password not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }

if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD))
  {
    Write-Host  "UserName / Password authentication failed - script is exiting" -ForegroundColor Red
    pause
    return
  }


Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

# Functions
#* Start function
function ReplicatedTableSize()
{
    	try
		{
            $outerLCV = 0       
			$replicatedtables = @()
			foreach ($db in $databases) 
			{
                ##########################
                #outer progress bar code
                #must set $outerLCV to 0 outside outer loop
                $innerLCV = 0
                [int64]$percentComplete = ($outerLCV/$($databases.count))*100
                Write-Progress -Activity "Looping through databases" -Status "$percentComplete Percent Complete" -PercentComplete $percentComplete
                $outerLCV++
                ##########################
                Write-Host -ForegroundColor Cyan "Gathering data for DB: $db"
                # Create a RepSizeTable
                $tableRepSize = New-Object system.Data.DataTable "RepSizeTable"
                $colDatabaseName = New-Object system.Data.DataColumn databaseName,([string])
                $colTableName = New-Object system.Data.DataColumn tableName,([string])
                $coltotalSpace = New-Object system.Data.DataColumn totalSpace,([decimal])
                $coldataSpace = New-Object system.Data.DataColumn dataSpace,([decimal])
                $coltotalRows = New-Object system.Data.DataColumn totalRows,([int64])
                $colTableType = New-Object system.Data.DataColumn tableType,([string])
                $tableRepSize.columns.add($colDatabaseName)
                $tableRepSize.columns.add($colTableName)
                $tableRepSize.columns.add($colTableType)
                $tableRepSize.columns.add($coltotalSpace)
                $tableRepSize.columns.add($coldataSpace)
                $tableRepSize.columns.add($coltotalRows)	
		
                try
                {
                    $RepQry = "use $db; SELECT '[' + sc.name + '].[' + ta.name + ']' as TableName FROM sys.tables ta INNER JOIN sys.partitions pa ON pa.OBJECT_ID = ta.OBJECT_ID INNER JOIN sys.schemas sc ON ta.schema_id = sc.schema_id, sys.pdw_table_mappings b, sys.pdw_table_distribution_properties c WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1,0) and ta.object_id = b.object_id AND b.object_id = c.object_id AND c.distribution_policy = '3' GROUP BY sc.name,ta.name ORDER BY SUM(pa.rows) DESC;"
                    $DistQry = "use $db; SELECT '[' + sc.name + '].[' + ta.name + ']' TableName FROM sys.tables ta INNER JOIN sys.partitions pa ON pa.OBJECT_ID = ta.OBJECT_ID INNER JOIN sys.schemas sc ON ta.schema_id = sc.schema_id, sys.pdw_table_mappings b, sys.pdw_table_distribution_properties c WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1,0) and ta.object_id = b.object_id AND b.object_id = c.object_id AND c.distribution_policy = '2' GROUP BY sc.name,ta.name ORDER BY SUM(pa.rows) DESC;"
                    $RRQry = "use $db; SELECT '[' + sc.name + '].[' + ta.name + ']' TableName FROM sys.tables ta INNER JOIN sys.partitions pa ON pa.OBJECT_ID = ta.OBJECT_ID INNER JOIN sys.schemas sc ON ta.schema_id = sc.schema_id, sys.pdw_table_mappings b, sys.pdw_table_distribution_properties c WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1,0) and ta.object_id = b.object_id AND b.object_id = c.object_id AND c.distribution_policy = '4' GROUP BY sc.name,ta.name ORDER BY SUM(pa.rows) DESC;"
                    $RepTbls = Invoke-Sqlcmd -querytimeout 0 -Query $RepQry -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
                    $distTbls = Invoke-Sqlcmd -querytimeout 0 -Query $DistQry -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
                    $RRTbls = Invoke-Sqlcmd -querytimeout 0 -Query $RRQry -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
				}
                catch	
                {
                    write-eventlog -entrytype Error -Message "Failed gathering table list with Invoke-SQLCMD $db`n`n $_" -Source $source -LogName ADU -EventId 9999	
                    Write-Error "Failed gathering table list with Invoke-SQLCMD $db`n`n $_" -ErrorAction Stop
                }
                
                $RepTableCount = $RepTbls.tablename.count
                $DistTableCount = $distTbls.tablename.count
                $RRTableCount = $RRTbls.tablename.count

                $totalTableCount = $RepTableCount + $DistTableCount + $RRTableCount

                #$innerLCV = 0
                #go through the replicated tables
				foreach($tbl in $RepTbls.tablename) 
					{
                        
                        ########################
                        #Inner progress bar code
                        #must set $innerLCV to 0 outside inner loop, but inside outer loop.
                        if ($($RepTableCount) -eq 0)
                        {
                            "No Replicated Tables Found"
							#[int64]$innerPercentComplete=100
                        }
                        else
                        {
					        [int64]$innerPercentComplete = ($innerLCV/$($totalTableCount))*100
                        }

                         Write-Progress -id 1 -Activity "Looping through tables in $db" -Status "$innerPercentComplete Percent Complete" -PercentComplete $innerPercentComplete
                         $innerLCV++
                        ########################

					

						# Varaibles
						$totalSpace=0
						$dataSpace=0
						[int64]$totalRows=0
						$row = $tableRepSize.NewRow()
						$row.databaseName = $db
						$row.tableName = $tbl

						# Capture DBCC PDW_SHOWSPACED output
						try
							{
								$results = Invoke-Sqlcmd -querytimeout 0 -Query "use $db; DBCC PDW_SHOWSPACEUSED ('$tbl');" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
							}
						catch
							{
								#Write-Host $Error
							}
			
						# Sum totalSpace
						$results.reserved_space |foreach { $totalSpace = $_ }
						$totalSpace = ([System.Math]::Round($totalSpace / 1024,1))
						
						# Sum dataSpace
						$results.data_space |foreach { $dataSpace = $_ }
						$dataSpace = ([System.Math]::Round($dataSpace / 1024,1))
										
						#sum totalRows
						$results.Rows |foreach { $totalRows = $_ }
						$row.TableType = "Replicated"
						$row.totalSpace = $totalSpace	
						$row.dataSpace = $dataSpace	 
						$row.totalRows = $totalRows
                        
						$tableRepSize.Rows.Add($row)
					}
                
                #$innerLCV = 0
                #go through the distributed tables
				foreach($tbl in $distTbls.tablename) 
					{
                        
                        ########################
                        #Inner progress bar code
                        #must set $innerLCV to 0 outside inner loop, but inside outer loop.
                        if ($($DistTableCount) -eq 0)
                        {
                            "No Distributed Tables Found"
							#[int64]$innerPercentComplete=100
                        }
                        else
                        {
					        [int64]$innerPercentComplete = ($innerLCV/$($totalTableCount))*100
                        }

                         Write-Progress -id 1 -Activity "Looping through tables in $db" -Status "$innerPercentComplete Percent Complete" -PercentComplete $innerPercentComplete
                         $innerLCV++
                        ########################

					

						# Varaibles
						$totalSpace=0
                        $dataSpace=0
						[int64]$totalRows=0
						$row = $tableRepSize.NewRow()
						$row.databaseName = $db
						$row.tableName = $tbl

						# Capture DBCC PDW_SHOWSPACED output
						try
							{
								$results = Invoke-Sqlcmd -querytimeout 0 -Query "use $db; DBCC PDW_SHOWSPACEUSED ('$tbl');" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
							}
						catch
							{
								#Write-Host $Error
							}
			
						# Sum totalSpace
						$results.reserved_space |foreach { $totalSpace += $_ }
						$totalSpace = ([System.Math]::Round($totalSpace / 1024,1))
						
						# Sum dataSpace
						$results.data_space |foreach { $dataSpace += $_ }
						$dataSpace = ([System.Math]::Round($dataSpace / 1024,1))
										
						#sum totalRows
						$results.Rows |foreach { $totalRows += $_ }
						$row.TableType = "Distributed"
						$row.totalSpace = $totalSpace	
						$row.dataSpace = $dataSpace	 
						$row.totalRows = $totalRows
                        
						$tableRepSize.Rows.Add($row)
					}
                
                #$innerLCV = 0
                #go through the Round Robin tables
				foreach($tbl in $RRTbls.tablename) 
					{
                        
                        ########################
                        #Inner progress bar code
                        #must set $innerLCV to 0 outside inner loop, but inside outer loop.
                        if ($($RRTableCount) -eq 0)
                        {
                            "No Round Robin tables found"
							[int64]$innerPercentComplete=100
                        }
                        else
                        {
					        [int64]$innerPercentComplete = ($innerLCV/$($totalTableCount))*100
                        }

                         Write-Progress -id 1 -Activity "Looping through tables in $db" -Status "$innerPercentComplete Percent Complete" -PercentComplete $innerPercentComplete
                         $innerLCV++
                        ########################

					

						# Varaibles
						$totalSpace=0
                        $dataSpace=0
						[int64]$totalRows=0
						$row = $tableRepSize.NewRow()
						$row.databaseName = $db
						$row.tableName = $tbl

						# Capture DBCC PDW_SHOWSPACED output
						try
							{
								$results = Invoke-Sqlcmd -querytimeout 0 -Query "use $db; DBCC PDW_SHOWSPACEUSED ('$tbl');" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
							}
						catch
							{
								#Write-Host $Error
							}
			
						# Sum totalSpace
						$results.reserved_space |foreach { $totalSpace += $_ }
						$totalSpace = ([System.Math]::Round($totalSpace / 1024,1))
						
						# Sum dataSpace
						$results.data_space |foreach { $dataSpace += $_ }
						$dataSpace = ([System.Math]::Round($dataSpace / 1024,1))
										
						#sum totalRows
						$results.Rows |foreach { $totalRows += $_ }
						$row.TableType = "Round Robin"
						$row.totalSpace = $totalSpace	
						$row.dataSpace = $dataSpace	 
						$row.totalRows = $totalRows
                        
						$tableRepSize.Rows.Add($row)
					}
				#trying adding total rows
				$tableRepSize |sort-object totalSpace -descending | ft databaseName, tableName, @{label = "Table Type" ; Expression = {$_.tableType}}, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}}, @{label = "Data Size MBs" ; Expression = {$_.dataSpace}}, @{label = "Total Rows" ; Expression = {$_.totalRows}} -auto
				$tableRepSize |sort-object totalSpace -descending | ft databaseName, tableName, @{label = "Table Type" ; Expression = {$_.tableType}}, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}}, @{label = "Data Size MBs" ; Expression = {$_.dataSpace}}, @{label = "Total Rows" ; Expression = {$_.totalRows}} -auto |out-file -append $OutputFile	
				$replicatedtables += $tableRepSize

			}
		}
    catch
		{
			write-eventlog -entrytype Error -Message "Failed on function `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
			Write-error "Failed on function `n`n $_.exception" #Writing an error and exit
		}

		$date=Get-Date
		$Appliance = (Get-Cluster).name.split("-")[0]

		#Empty body to hold the html fragments
		$body=@()

		#Defining the style
		$head = @"
			<style>
			BODY{background-color:AliceBlue;}
			TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
			TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:DarkCyan}
			TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:Lavender}
			</style>
"@

		write-host "Building report..."
		#build the body of the HTML
		$body += "<h2>______________________________________________________</h2>"
		if ($replicatedtables.count -gt 0)
		{
			$body += $replicatedtables |select databaseName, tableName, @{label = "Table Type" ; Expression = {$_.tableType}}, @{label = "Total Table Size (MB)" ; Expression = {$_.totalSpace}}, @{label = "Data Size MBs" ; Expression = {$_.dataSpace}}, @{label = "Total Rows" ; Expression = {$_.totalRows}} | ConvertTo-Html -Fragment 
		}
		else
		{
			$body += "No replicated table details found." 
		}
		$body += "<h2>______________________________________________________</h2>"
		$body += "<br>"

		# Create HTML using head and body values
		ConvertTo-Html -head $head -PostContent $body -body "<H1>Table Size Report</H1><H2>Appliance: $Appliance<br>Date: $date</H2>" | out-file $OutputFileHTML -Append
		$replicatedtables | Export-Csv -Append $OutputFileCSV -NoTypeInformation
		#start $OutputFileHTML
	
}
# Functions End


# Get list of database names
try
	{		
		$dbs = Invoke-Sqlcmd -querytimeout 0 -Query "select name from sys.databases where name not in ('master','tempdb','stagedb') order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}

if (!$database) 
{ 
	# Loop
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
		[string]$ans = OutputMenu -header "Check Table Size" -options $TableMenuOptions
		if($ans -eq "q"){break}

		# if option 
		if($ans -eq "All DBs") 
			{
				$databases = $dbs.name
				ReplicatedTableSize ($databases)
			}
		else
			{
				$databases = $ans
				ReplicatedTableSize ($databases)
			}
		Write-Host -ForegroundColor Cyan "Output also located at: $OutputFile"
	}while($ans -ne "q")
}
else 
{ 
			if($database -eq "all") 
			{
				$databases = $dbs.name
				ReplicatedTableSize ($databases)
			}

		else
			{
				$databases = $database
				ReplicatedTableSize ($databases)	
				
			}	
}
