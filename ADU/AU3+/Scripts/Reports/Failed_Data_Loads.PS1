#* FileName: FailedDataLoadMOD.ps1
#*=============================================
#* Script Name: FailedDataLoadMOD.ps1
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
#* Purpose: Failed Data Load Test 
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
#Example: .\FailedDataLoadMOD.ps1 -PDWHOST <ApplianceName>-ctl01 -PDWUID sa -PDWPWD <Password>

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1


#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

$PdwRegionName = GetPdwRegionName
$PDWHOST = $PdwRegionName + '-CTL01'
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

write-host "`nConnecting to PDW..."

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
Write-host "`nSearching for failed loads in Loader_backup_runs"
$command = $connection.CreateCommand();
$command.CommandText =  "select top 100 total_elapsed_time/60000 as ElapseTime_Mins,name,submit_time,mode,database_name,table_name,rows_processed,rows_rejected,rows_inserted,command,total_elapsed_time from sys.pdw_loader_backup_runs where operation_type = 'load' AND Status = 'FAILED' and start_time is not null and end_time is not null order by SUBMIT_TIME desc"
$ResultsDB = $command.ExecuteReader();


$failedloads = @() 
try
{
	# Write-output "Load Name|Total Elapsed Time"
	#  Write-output "-----------------------------" 
	while($ResultsDB.Read()) 
	{ 
	  $name = $ResultsDB.Item("name")
	  $submit_time = $ResultsDB.Item("submit_time")
	  $total_elapsed_time = [int]$ResultsDB.Item("total_elapsed_time")
	  $ElapseTime_Mins = [int]$ResultsDB.Item("ElapseTime_Mins")
	  $mode = $ResultsDB.Item("mode")
	  $database_name = $ResultsDB.Item("database_name")
	  $table_name = $ResultsDB.Item("table_name")
	  $rows_processed = $ResultsDB.Item("rows_processed")
	  $rows_rejected = $ResultsDB.Item("rows_rejected")
	  $rows_inserted = $ResultsDB.Item("rows_inserted")
	  $command = $ResultsDB.Item("command")

	  $temp = New-Object System.Object
	  $temp | Add-Member -MemberType noteproperty -name name -value ${name} 
	  $temp | Add-Member -MemberType noteproperty -name Elapsed_Time_in_Mins -value ${ElapseTime_Mins} 
	  $temp | Add-Member -MemberType noteproperty -name submit_time -value ${submit_time} 
	  $temp | Add-Member -MemberType noteproperty -name mode -value ${mode} 
	  $temp | Add-Member -MemberType noteproperty -name database_name -value ${database_name} 
	  $temp | Add-Member -MemberType noteproperty -name table_name -value ${table_name} 
	  $temp | Add-Member -MemberType noteproperty -name rows_processed -value ${rows_processed} 
	  $temp | Add-Member -MemberType noteproperty -name rows_rejected -value ${rows_rejected} 
	  $temp | Add-Member -MemberType noteproperty -name rows_inserted -value ${rows_inserted} 
	  $temp | Add-Member -MemberType noteproperty -name command -value ${command} 
	  $failedloads += $temp
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
$OutputFile = "D:\PDWDiagnostics\TableHealth\FailedDataLoadReport$CurrTime.txt"
$OutputFileCSV = "D:\PDWDiagnostics\TableHealth\FailedDataLoadReport$CurrTime.csv"
$OutputFileHTML = "D:\PDWDiagnostics\TableHealth\FailedDataLoadReport$CurrTime.html"

if (!(test-path "D:\PDWDiagnostics\TableHealth"))
{
	New-item "D:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
}
if (!(test-path $OutputFile))
{
	New-Item $OutputFile -ItemType File|out-null
}

if(!$failedloads){Write-host -foregroundcolor green "`n***No failed data loads found***"}
$failedloads |ft -auto
$failedloads | out-file $OutputFile
$failedloads | Export-Csv $OutputFileCSV -NoTypeInformation

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

	write-host "`nBuilding reports..."
	#build the body of the HTML
	$body += "<h2>______________________________________________________</h2>"
	if ($failedloads.count -gt 0)
	{
		$body += $failedloads  | ConvertTo-Html -Fragment 
	}
	else
	{
		$body += "No failed data load details found." 
	}
	$body += "<h2>______________________________________________________</h2>"
	$body += "<br>"
try
	{
		# Create HTML using head and body values
		ConvertTo-Html -head $head -PostContent $body -body "<H1> Failed Data Loads Report</H1><H2>Appliance: $Appliance<br>Date: $date</H2>" | out-file $OutputFileHTML
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed generating HTML report `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed generating HTML report... Exiting" #Writing an error and exit
	}
#start $OutputFileHTML