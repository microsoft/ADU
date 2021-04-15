#* FileName: DataBase_SpaceUtil_ByVolume.ps1
#*=============================================
#* Script Name: DataBase_SpaceUtil_ByVolume.ps1
#* Created: [11/22/2017]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Requirements:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: DataBase Space Utilization By Volume
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 11/22/2017 sfacer
#* Changes
#* 1. Original version
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set up logging
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



Try
{
	$CMPList=@()
	$CMPList = GetNodeList -cmp
}
catch
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
}

$CurrTime = get-date -Format yyyyMMddHHmmss
$FileName = "DBSpaceUtilByVolume_$CurrTime.csv"
$OutputFile = "D:\PDWDiagnostics\StorageReport\$FileName"

If (!(test-path "D:\PDWDiagnostics\StorageReport"))
  {
	New-item "D:\PDWDiagnostics\StorageReport" -ItemType Dir | Out-Null
  }

$OutputFileLocal = "C:\Temp\$FileName"

## Get the volume list on each CMP node
$Script  = "`$CMPNode = @{Name=`"NodeName`";expression={`$env:computername}};"
$Script += "`$FileSizeGB = @{Name=`"FileSize`";expression={[math]::round(($`_.Length / 1073741824),4)}};"
$Script += "Get-ChildItem G:\Data*\Data\*.*df -Recurse  | ?{$`_.Name -notlike `"*temp*`"} | SELECT `$CMPNode, Directory, Name, `$FileSizeGB "

$results = ExecuteDistributedPowerShell -nodeList $CMPList -command $Script


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
        return
	}


$command = $connection.CreateCommand();
$command.CommandText =  "SELECT d.name as DBName, dm.physical_name as Mapped_DB
FROM sys.databases d INNER JOIN sys.pdw_database_mappings dm ON d.database_id = dm.database_id
WHERE  d.name NOT IN ('master', 'tempdb');" 

$DBName_results = $command.ExecuteReader();



$results | SELECT NodeName, Directory, Name, FileSize | export-csv -NoTypeInformation $OutputFile

Write-Host "`nOutput file saved to $OutputFile" -ForegroundColor Green
