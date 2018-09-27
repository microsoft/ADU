#* FileName: DataVolume_Utilization.ps1
#*=============================================
#* Script Name: Disk_FreeSpace.ps1
#* Created: [3/8/2017]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Requirements:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: Data Volume Space Report
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 06/09/2017 sfacer
#* Changes
#* 1. Removed CTL node - has no Data Volumes allocated
#* 2. Filtered OSDISKS out from the results
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

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
$FileName = "DataVolumeUtilization_$CurrTime.csv"
$OutputFile = "D:\PDWDiagnostics\StorageReport\$FileName"

If (!(test-path "D:\PDWDiagnostics\StorageReport"))
  {
	New-item "D:\PDWDiagnostics\StorageReport" -ItemType Dir | Out-Null
  }

$OutputFileLocal = "C:\Temp\$FileName"

## Get the volume list on each CMP node
$Script  = "`$TotalGB = @{Name=`"Capacity(GB)`";expression={[math]::round(($`_.Capacity/ 1073741824),4)}};"
$Script += "`$FreeGB = @{Name=`"FreeSpace(GB)`";expression={[math]::round(($`_.FreeSpace / 1073741824),4)}};"
$Script += "`$FreePerc = @{Name=`"Free(%)`";expression={[math]::round(((($`_.FreeSpace / 1073741824)/($`_.Capacity / 1073741824)) * 100),2)}};"
$Script += "Get-WmiObject win32_volume | Sort-Object Label | select SystemName, Label, Capacity, `$TotalGB, FreeSpace, `$FreeGB, `$FreePerc  "

$results = ExecuteDistributedPowerShell -nodeList $CMPList -command $Script

$results | ?{$_.Label -ne "OSDISK"} | export-csv -NoTypeInformation $OutputFile

Write-Host "`nOutput file saved to $OutputFile" -ForegroundColor Green
