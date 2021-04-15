#* FileName: PDWBackupTestMOD.ps1
#*=============================================
#* Script Name: PDWBackupTestMOD.ps1
#* Created: 
#* Author: [Need to identify the original author]
#* Modified by: Victor Hermosillo        
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: PDW Backup Test 
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 
#* Changes:
#* Modified: 10/04/2018 sfacer
#* Changes
#* 1. Changed login failure error handling
#*=============================================

param($username, $password)
#Example: .\PDWBackupTestMOD.ps1 -PDWHOST <ApplianceName>-sqlctl01 -PDWUID sa -PDWPWD <Password>

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Get PdwDomainName
$PDWRegion = GetPdwRegionName
$PDWHOST = "$PDWRegion-sqlctl01"

# Get username and credentials		
if(!$username)
	{   $PDWUID = GetPdwUsername; $PDWPWD = GetPdwPassword }
else
	{   $PDWUID = $username; $PDWPWD = $password }	

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


$PDWTable = ""
$TotalTableSize = 0

$DateRun = Get-Date

#########################################################################

write-output "CONNECTING TO PDW..."
try 
	{
		$connection = New-Object System.Data.SqlClient.SqlConnection
		$connection.ConnectionString = "Server=${PDWHOST},17001; ;Database=master;User ID=${PDWUID};Password=${PDWPWD}";
		$connection.Open();
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to connect `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to connect to the APS PDW database... Exiting" #Writing an error and exit
	}

## Get Loads Names
$command = $connection.CreateCommand();
$command.CommandText =  "select sd.name
       ,a.name as name
       ,a.submit_time as submit_time
       ,a.status as status
   
from sys.databases sd
left outer join (sys.pdw_loader_backup_runs a
inner join (select max(run_id) as run_id
                  ,database_name
                  ,mode
            from sys.pdw_loader_backup_runs
            where operation_type = 'BACKUP' 
            and   mode in ('DIFFERENTIAL','FULL')
            group by  database_name
                     ,mode) b
ON  a.run_id = b.run_id)
ON sd.name = a.database_name
where (a.operation_type = 'BACKUP') OR (a.operation_type is null)
and   sd.name <> 'tempdb'
order by a.database_name;" 

$backup_results = @()

$ResultsDB = $command.ExecuteReader();

try
	{ 
		while($ResultsDB.Read()) 
		{ 
		  $name = $ResultsDB.Item("name")
		   $submit_time = $ResultsDB.Item("submit_time")
			$status = $ResultsDB.Item("status").ToString();
				if ($status -eq '') 
				{ $status = "Never Backed Up"}


			#if ($status -eq "FAILED" -or $status -eq "CANCELLED" -or $status -eq "Never Backed Up")
			#{
			  $temp = New-Object System.Object
						
			  $temp | Add-Member -MemberType noteproperty -name name -value ${name} 
			  $temp | Add-Member -MemberType noteproperty -name submit_time -value ${submit_time} 
			  $temp | Add-Member -MemberType noteproperty -name status -value ${status} 
			  $backup_results += $temp 
			#}
		}
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to collecting results `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to collecting results... Exiting" #Writing an error and exit
	}
	
$ResultsDB.Close();
$connection.Close();


$CurrTime = get-date -Format yyyyMMddHHmmss
$OutputFile = "D:\PDWDiagnostics\TableHealth\PDWBackupTestReport$CurrTime.txt"
$OutputFileCSV = "D:\PDWDiagnostics\TableHealth\PDWBackupTestReport$CurrTime.csv"
$OutputFileHTML = "D:\PDWDiagnostics\TableHealth\PDWBackupTestReport$CurrTime.html"

if (!(test-path "D:\PDWDiagnostics\TableHealth"))
{
	New-item "D:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
}
if (!(test-path $OutputFile))
{
	New-Item $OutputFile -ItemType File|out-null
}

$backup_results |ft -auto
$backup_results | out-file $OutputFile
$backup_results | Export-Csv $OutputFileCSV -NoTypeInformation


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
	if ($backup_results.count -gt 0)
	{
		$body += $backup_results  | ConvertTo-Html -Fragment 
	}
	else
	{
		$body += "No backup details found."  
	}
	$body += "<h2>______________________________________________________</h2>"
	$body += "<br>"

try
	{
		# Create HTML using head and body values
		ConvertTo-Html -head $head -PostContent $body -body "<H1> PDW Backup Report</H1><H2>Appliance: $Appliance<br>Date: $date</H2>" | out-file $OutputFileHTML
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed generating HTML report `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed generating HTML report... Exiting" #Writing an error and exit
	}
#start $OutputFileHTML


