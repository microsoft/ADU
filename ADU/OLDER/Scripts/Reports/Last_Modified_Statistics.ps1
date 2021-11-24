#* FileName: LastModifiedStatistics.ps1
#*=============================================
#* Script Name: LastModifiedStatistics.ps1
#* Created: [2/5/2014]
#* Author: Vic Hermosillo
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: Last Modified Statistics
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
		# Domain name and CTL host name
		$PdwDomainName = GetPdwDomainName
		$PDWHOST = $PdwDomainName + '-SQLCTL01'
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "c:\PDWDiagnostics\TableHealth\LastModifiedStatistics_$CurrTime.txt"
		$OutputFileCSV = "c:\PDWDiagnostics\TableHealth\LastModifiedStatistics_$CurrTime.csv"
		$OutputFileHTML = "c:\PDWDiagnostics\TableHealth\LastModifiedStatistics_$CurrTime.html"

		if (!(test-path "c:\PDWDiagnostics\TableHealth"))
			{
				New-item "c:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
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

if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD -pdwDomain $PdwDomainName))
{

    write-error "failed to validate credentials"
}

# Functions

function LastModifiedStatistics($databases)
	{
		$lastmodifiedstats = @()		
		#* Loop through DB's
		foreach ($db in $databases) 
		{
			Write-Host -ForegroundColor Cyan "Gathering data for DB: $db"
			try
				{       
					#* Collect table details
					$results = Invoke-Sqlcmd -Query "use [$db]; select a.name as table_name, b.name AS stats_name, STATS_DATE(b.object_id,stats_id) AS stats_last_update from sys.tables a, sys.stats b where a.object_id = b.object_id" -ServerInstance "$PDWHOST" -Username $PDWUID -Password $PDWPWD -ErrorAction SilentlyContinue
				}
			catch
				{
					Write-Eventlog -entrytype Error -Message "Failed to collect statistics details `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed to collect statistics details... Exiting" -ErrorAction Stop #Writing an error and exit
				} 
			
			# Create a CurrentStatsTable
			$tableCurrentStats = New-Object system.Data.DataTable "CurrentStatsTable"
			$colDatabaseName = New-Object system.Data.DataColumn databaseName,([string])
			$colTableName = New-Object system.Data.DataColumn tableName,([string])
			$colStatsName = New-Object system.Data.DataColumn statsName,([string])
			$colStatsDate = New-Object system.Data.DataColumn statsDate,([datetime])
			$tableCurrentStats.columns.add($colDatabaseName)
			$tableCurrentStats.columns.add($colTableName)
			$tableCurrentStats.columns.add($colStatsName)
			$tableCurrentStats.columns.add($colStatsDate)
		
			$counter = $results.count - 1
			try 
				{
					foreach ($a in 0..$counter)
					{
						if(![system.dbnull]::value.equals($results.stats_last_update[$a]))
						#if($results.stats_last_update[$a] -ne $Null)
						{	
							# Add rows to cols
							$row = $tableCurrentStats.NewRow()
							$row.databaseName = $db
							$row.tableName = $results.table_name[$a]
							$row.statsName = $results.stats_name[$a]				
							$row.statsDate = $results.stats_last_update[$a]
							$tableCurrentStats.Rows.Add($row)
							
							# Print screen
							#write-host "Table: $row.tableName[$a] Updates: $results.stats_last_update[$a]"
							#write-host $counter
						}
					}
						
					$tableCurrentStats |ft databaseName, tableName, statsName, statsDate -auto
					$tableCurrentStats |ft databaseName, tableName, statsName, statsDate -auto  |out-file -append $OutputFile
					$lastmodifiedstats += $tableCurrentStats  			
				}
			catch 
				{
					Write-Eventlog -entrytype Error -Message "Failed looping through results `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed looping through results... Exiting .... Table: $results.table_name[$a] Updates: $results.stats_last_update[$a]" -ErrorAction SilentlyContinue #Writing an error and exit
				}  

			#$lastmodifiedstats.count				
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
		if ($lastmodifiedstats.count -gt 0)
		{
			$body += $lastmodifiedstats |select databaseName,tableName,statsName,statsDate | ConvertTo-Html -Fragment 
		}
		else
		{
			$body += "No statistics details found."  
		}
		$body += "<h2>______________________________________________________</h2>"
		$body += "<br>"

		# Create HTML using head and body values
		ConvertTo-Html -head $head -PostContent $body -body "<H1>Last Modified Statistics Report</H1><H2>Appliance: $Appliance<br>Date: $date</H2>" | out-file $OutputFileHTML
		$lastmodifiedstats | Export-Csv $OutputFileCSV -NoTypeInformation
		#start $OutputFileHTML



		
	}
#* End Function

Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

# Get list of database names
try
	{
		
		$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb','model','msdb','dwqueue','dwdiagnostics','dwconfiguration') order by name desc;" -ServerInstance "$PDWHOST" -Username $PDWUID -Password $PDWPWD
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed connecting or querying for database names `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed connecting or querying for database names... Exiting" #Writing an error and exit
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
	for ($i=1;$i -le $dbs.count; $i++) {$TableMenuOptions+=($dbs[$i-1].name)}

	[string]$ans = OutputMenu -header "Check Last Modified Statistics Date" -options $TableMenuOptions
	if($ans -eq "q"){break}
	
	# if 
	if($ans -eq "All DBs") 
		{
			$databases = $dbs.name
			LastModifiedStatistics ($databases)
		}

	else
		{
			$databases = $ans
			LastModifiedStatistics ($databases)
			
		}
	Write-Host -ForegroundColor Cyan "Output also located at: $OutputFile"
	}while($ans -ne "q")
}
else 
{ 
			if($database -eq "all") 
			{
				$databases = $dbs.name
				LastModifiedStatistics ($databases)
			}

		else
			{
				$databases = $database
				LastModifiedStatistics ($databases)	
				
			}	
}