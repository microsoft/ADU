#* FileName: ReplicatedTableSize.ps1
#*=============================================
#* Script Name: ReplicatedTableSize.ps1
#* Created: [1/31/2014]
#* Author: Vic Hermosillo
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	Cluster must be up
#* 
#* Keywords:
#*=============================================
#* Purpose: Test replicated table size details
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
		$PDWHOST = $PdwDomainName + '-CTL01'
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "c:\PDWDiagnostics\TableHealth\ReplicatedTableSize_$CurrTime.txt"
		$OutputFileCSV = "c:\PDWDiagnostics\TableHealth\ReplicatedTableSize_$CurrTime.csv"
		$OutputFileHTML = "c:\PDWDiagnostics\TableHealth\ReplicatedTableSize_$CurrTime.html"

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


Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

# Functions
#* Start function
function ReplicatedTableSize()
{
    	try
		{
			$replicatedtables = @()
			foreach ($db in $databases) 
			{
				Write-Host -ForegroundColor Cyan "Gathering data for DB: $db"
				# Create a RepSizeTable
				$tableRepSize = New-Object system.Data.DataTable "RepSizeTable"
				$colDatabaseName = New-Object system.Data.DataColumn databaseName,([string])
				$colTableName = New-Object system.Data.DataColumn tableName,([string])
				$coltotalSpace = New-Object system.Data.DataColumn totalSpace,([decimal])
				$tableRepSize.columns.add($colDatabaseName)
				$tableRepSize.columns.add($colTableName)
				$tableRepSize.columns.add($coltotalSpace)	
			

				$tbls = Invoke-Sqlcmd -Query "use [$db]; SELECT ta.name TableName FROM sys.tables ta INNER JOIN sys.partitions pa ON pa.OBJECT_ID = ta.OBJECT_ID INNER JOIN sys.schemas sc ON ta.schema_id = sc.schema_id, sys.pdw_table_mappings b, sys.pdw_table_distribution_properties c WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1,0) and ta.object_id = b.object_id AND b.object_id = c.object_id AND c.distribution_policy = '3' GROUP BY sc.name,ta.name ORDER BY SUM(pa.rows) DESC;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
						
				foreach($tbl in $tbls.tablename) 
					{
					
						#Write-Host -ForegroundColor Cyan "`nData for" $db".dbo."$tbl
						#"Data for $db.dbo.$tbl" |out-file -append $OutputFile
						#Write-Host -ForegroundColor Green "Table name:" $tbl
						#"Table: $tbl" |out-file -append $OutputFile
					

						# Varaibles
						$totalDataSpace=0
						$row = $tableRepSize.NewRow()
						$row.databaseName = $db
						$row.tableName = $tbl

						# Capture DBCC PDW_SHOWSPACED output
						try
							{
								$results = Invoke-Sqlcmd -Query "use [$db]; DBCC PDW_SHOWSPACEUSED ([$tbl]);" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
							}
						catch
							{
								#Write-Host $Error
							}
			
						# Sum totalDataSpace
						$results.data_space |foreach { $totalDataSpace = $_ }
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
										
						$row.totalSpace = $totalDataSpace			
						$tableRepSize.Rows.Add($row)
					}
				
				$tableRepSize |sort-object totalSpace -descending | ft databaseName, tableName, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}} -auto
				$tableRepSize |sort-object totalSpace -descending | ft databaseName, tableName, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}} -auto |out-file -append $OutputFile	
				$replicatedtables += $tableRepSize
			}
		}
    catch
		{
			write-eventlog -entrytype Error -Message "Failed on function `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
			Write-error "Failed on function... Exiting" #Writing an error and exit
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
			$body += $replicatedtables |select databaseName, tableName, @{label = "Total Table Size MBs" ; Expression = {$_.totalSpace}} | ConvertTo-Html -Fragment 
		}
		else
		{
			$body += "No replicated table details found." 
		}
		$body += "<h2>______________________________________________________</h2>"
		$body += "<br>"

		# Create HTML using head and body values
		ConvertTo-Html -head $head -PostContent $body -body "<H1>Replicated Table Size Report</H1><H2>Appliance: $Appliance<br>Date: $date</H2>" | out-file $OutputFileHTML
		$replicatedtables | Export-Csv $OutputFileCSV -NoTypeInformation
		#start $OutputFileHTML
	
}
# Functions End


# Get list of database names
try
	{		
		$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb') order by name desc;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
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
		for ($i=1;$i -le $dbs.count; $i++) {$TableMenuOptions+=($dbs[$i-1].name)}

		[string]$ans = OutputMenu -header "Check Replicated Table Size" -options $TableMenuOptions
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
