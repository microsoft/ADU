#* FileName: distributedTableSize.ps1
#*=============================================
#* Script Name: distributedTableSize.ps1
#* Created: [1/31/2014]
#* Author: Vic Hermosillo
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	Cluster must be up
#* 
#* Keywords:
#*=============================================
#* Purpose: Test distributed table size details
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
#* 2. Modified table name SELECT to add '[]' around schema and table name
#* Modified: 10/04/2018 sfacer
#* Changes
#* 1. Changed login failure error handling
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
		$OutputFile = "D:\PDWDiagnostics\TableHealth\DistributedTableSize_$CurrTime.txt"
		$OutputFileCSV = "D:\PDWDiagnostics\TableHealth\DistributedTableSize_$CurrTime.csv"
		$OutputFileHTML = "D:\PDWDiagnostics\TableHealth\DistributedTableSize_$CurrTime.html"

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
function distributedTableSize()
{
    	try
		{
            #Loop control variabls for progress bars
            $outerLCV = 0

			$distributedtables = @()
			foreach ($db in $databases) 
			{
                ##########################
                #outer progress bar code
                #must set $outerLCV to 0 outside outer loop
                $innerLCV = 0
                [int]$percentComplete = ($outerLCV/$($databases.count))*100
                Write-Progress -Activity "Looping through databases" -Status "$percentComplete Percent Complete" -PercentComplete $percentComplete
                $outerLCV++
                ##########################

				Write-Host -ForegroundColor Cyan "Gathering data for DB: $db"
				# Create a RepSizeTable
				$tableRepSize = New-Object system.Data.DataTable "RepSizeTable"
				$colDatabaseName = New-Object system.Data.DataColumn databaseName,([string])
				$colTableName = New-Object system.Data.DataColumn tableName,([string])
				$coltotalSpace = New-Object system.Data.DataColumn totalSpace,([decimal])
				$coltotalRows = New-Object system.Data.DataColumn totalRows,([int64])
				$tableRepSize.columns.add($colDatabaseName)
				$tableRepSize.columns.add($colTableName)
				$tableRepSize.columns.add($coltotalSpace)	
				$tableRepSize.columns.add($coltotalRows)
                
                try
                {
				    $tbls = Invoke-Sqlcmd -querytimeout 0 -Query "use $db; SELECT '[' + sc.name + '].[' + ta.name + ']' TableName FROM sys.tables ta INNER JOIN sys.partitions pa ON pa.OBJECT_ID = ta.OBJECT_ID INNER JOIN sys.schemas sc ON ta.schema_id = sc.schema_id, sys.pdw_table_mappings b, sys.pdw_table_distribution_properties c WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1,0) and ta.object_id = b.object_id AND b.object_id = c.object_id AND c.distribution_policy = '2' GROUP BY sc.name,ta.name ORDER BY SUM(pa.rows) DESC;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
				}
                catch	
                {
                    write-eventlog -entrytype Error -Message "failed gathering table list with Invoke-SQLCMD $db`n`n $_" -Source $source -LogName ADU -EventId 9999	
                    Write-Error "failed gathering table list with Invoke-SQLCMD $db`n`n $_" -ErrorAction Stop
                }


				foreach($tbl in $tbls.tablename) 
					{
                        ########################
                        #Inner progress bar code
                        #must set $innerLCV to 0 outside inner loop, but inside outer loop.
                        if ($($tbls.count) -eq 0)
                        {
                            "Found 0 tables"
                        }
                        else
                        {
					        [int]$innerPercentComplete = ($innerLCV/$($tbls.tablename.count))*100
                        }

                         Write-Progress -id 1 -Activity "Looping through tables in $db" -Status "$innerPercentComplete Percent Complete" -PercentComplete $innerPercentComplete
                         $innerLCV++
                        ########################
                        					
						#Write-Host -ForegroundColor Cyan "`nData for" $db".dbo."$tbl
						#"Data for $db.dbo.$tbl" |out-file -append $OutputFile
						#Write-Host -ForegroundColor Green "Table name:" $tbl
						#"Table: $tbl" |out-file -append $OutputFile
					

						# Varaibles
						$totalDataSpace=0
						$totalRows=0
						$row = $tableRepSize.NewRow()
						$row.databaseName = $db
						$row.tableName = $tbl

						# Capture DBCC PDW_SHOWSPACED output
						try
							{
								$results = Invoke-Sqlcmd -Query "use $db; DBCC PDW_SHOWSPACEUSED ('$tbl');" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
							}
						catch
							{
                                write-eventlog -entrytype Error -Message "failed on invoke-sqlcmd for $tbl`n`n $_" -Source $source -LogName ADU -EventId 9999	
								Write-error "failed on invoke-sqlcmd for $tbl`n`n $_" -ErrorAction Continue
							}
			
						# Sum totalDataSpace
						$results.reserved_space |foreach { $totalDataSpace += $_ }
						$totalDataSpace = ([System.Math]::Round($totalDataspace / 1024,1))
						


						if($totalDataSpace -gt 1)
							{
								#Write-Host -foreground red "Total data space:" $totalDataSpace "MB -Failed"
								#"Total data space: $totalDataSpace MB -Failed" |out-file -append $OutputFile
							}
						else
							{
								#Write-Host "Total data space:" $totalDataSpace "MB"
								#"Total data space: $totalDataSpace MB" |out-file -append $OutputFile
							}
						
						#sum totalRows
						$results.Rows |foreach { $totalRows += $_ }
						
						$row.totalSpace = $totalDataSpace	
						$row.totalRows = $totalRows
						$tableRepSize.Rows.Add($row)
						
						
					}
				
				$tableRepSize |sort-object totalSpace -descending | ft databaseName, tableName, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}}, @{label="Total Rows";Expression={$_.totalRows}} -auto
				$tableRepSize |sort-object totalSpace -descending | ft databaseName, tableName, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}}, @{label="Total Rows";Expression={$_.totalRows}} -auto |out-file -append $OutputFile	
				$distributedtables += $tableRepSize
			}
		}
    catch
		{
			write-eventlog -entrytype Error -Message "Failed on function `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
			Write-error "Failed gathering table sizes for $db, last table was $tbl... Exiting `n`n $_.exception" #Writing an error and exit
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
		if ($distributedtables.count -gt 0)
		{
			$body += $distributedtables |select databaseName, tableName, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}} | ConvertTo-Html -Fragment 
		}
		else
		{
			$body += "No distributed table details found." 
		}
		$body += "<h2>______________________________________________________</h2>"
		$body += "<br>"

		# Create HTML using head and body values
		ConvertTo-Html -head $head -PostContent $body -body "<H1>distributed Table Size Report</H1><H2>Appliance: $Appliance<br>Date: $date</H2>" | out-file $OutputFileHTML -Append
		$distributedtables | Export-Csv -Append $OutputFileCSV -NoTypeInformation
		#start $OutputFileHTML
	
}
# Functions End


# Get list of database names
try
	{		
		$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb', 'mavtdb') order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
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
		[string]$ans = OutputMenu -header "Check distributed Table Size" -options $TableMenuOptions
		if($ans -eq "q"){break}

		# if option 
		if($ans -eq "All DBs") 
			{
				$databases = $dbs.name
				distributedTableSize ($databases)
			}
		else
			{
				$databases = $ans
				distributedTableSize ($databases)
			}
		Write-Host -ForegroundColor Cyan "Output also located at: $OutputFile"
	}while($ans -ne "q")
}
else 
{ 
			if($database -eq "all") 
			{
				$databases = $dbs.name
				distributedTableSize ($databases)
			}

		else
			{
				$databases = $database
				distributedTableSize ($databases)	
				
			}	
}
