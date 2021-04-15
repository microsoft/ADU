#* FileName: WSUS_Patch_Listing.ps1
#*=====================================================================
#* Script Name: WSUS_Patch_Listing.ps1
#* Created: [04/04/2017]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=====================================================================
#* Purpose: List installed patches by date
#*=====================================================================

#*=====================================================================
#* REVISION HISTORY
#*=====================================================================
#* Modified: 
#* Changes:
#* Modified: ??/??/?? [who ??]
#* Changes
#* 1. ??
#*=====================================================================

param()

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged


$CurrTime = get-date -Format yyyyMMddHHmmss
$OutputFileCSV = "D:\PDWDiagnostics\Misc\WSUSPatching_$CurrTime.csv"
if (!(test-path "D:\PDWDiagnostics\Misc"))
	{
		New-item "D:\PDWDiagnostics\Misc" -ItemType Dir | Out-Null
	}

$PatchHistoryOutputFolder = "D:\Temp\Patches"

if (!(test-path $PatchHistoryOutputFolder)) {New-item $PatchHistoryOutputFolder -ItemType Dir | Out-Null}

$ListToDelete = gci -Path $PatchHistoryOutputFolder

$PatchHistoryOutputFolderToDelete = $PatchHistoryOutputFolder + "\*"
Remove-Item -Path $PatchHistoryOutputFolderToDelete -Recurse -Force

$PatchHistoryOutputFile = "$PatchHistoryOutputFolder\Patches.txt"

Write-host "Capturing patching history data, please wait" -ForeGroundColor Yellow

$NodeList = GetNodeList -full
$command= "gwmi win32_quickfixengineering | sort-object -desc InstalledOn | ft -autosize Description,HotFixID,InstalledBy,InstalledOn"
ExecuteDistributedPowerShell $NodeList $command $PatchHistoryOutputFile

$PatchHistory = Get-Content -Path $PatchHistoryOutputFile

$HistoryCutoff = (Get-Date).AddYears(-1)

$InstalledDates = @{}
ForEach ($PatchHistoryRecord in $PatchHistory) {
    If (($PatchHistoryRecord).Length -lt 15) {
        $PatchHistoryRcdHdr = $PatchHistoryRecord
      }
    else {
        $PatchHistoryRcdHdr = ""
      }
    If ($PatchHistoryRcdHdr -match "-HST" -or $PatchHistoryRcdHdr -match "-HSA" -or $PatchHistoryRcdHdr -match "-CMP" -or $PatchHistoryRcdHdr -match "-CTL01" -or $PatchHistoryRcdHdr -match "-AD0" -or $PatchHistoryRcdHdr -match "-VMM" -or $PatchHistoryRcdHdr -match "-WDS" -or $PatchHistoryRcdHdr -match "-iSCSI") {
        $x = 1
      }
    ElseIf ($PatchHistoryRecord -match "InstalledOn") {
        $DateCol = $PatchHistoryRecord.IndexOf("InstalledOn")
      }
    ElseIf ($PatchHistoryRecord -match "--" -or $PatchHistoryRecord -eq "") {
        $x = 1
      }
    Else {
        $InstalledDate = $PatchHistoryRecord.Substring($DateCol, 12)
        $InstalledDate = $InstalledDate.Substring(0, ($InstalledDate.IndexOf(" ")))
        $dtInstalledDate=[datetime]$InstalledDate
        If ($InstalledDates.ContainsKey($InstalledDate) -ne $true -and $dtInstalledDate -ge $HistoryCutoff) {
            $InstalledDates.Add($InstalledDate, [datetime]$InstalledDate)
          }
      }
  }

Clear-Host

Write-Host "Select the Date or Date range to report on:" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""

[int]$DateIDX = 0

$InstalledDates.GetEnumerator() | Sort-Object Value -Descending | Foreach {
    $DateIDX+=1
    $DateString = [string]($_.Value)
    $DateString = $DateString.Substring(0,$DateString.IndexOf(" "))
    $IdxStr = "$DateIdx    ".Substring(0,4)
    Write-Host $IdxStr $dateString
  }

[string]$Response1 = Read-Host "Date (First date in range or the only date), or Q to Quit"
If ($Response1 -eq "Q") {
    return
  }
[string]$Response2 = Read-Host "Date (Second date in range), or blank, or Q to Quit"
If ($Response2 -eq "Q") {
    return
  }

$dt1 = 0
if ($Response1 -eq "") {
    Write-Host "The first entry is required, in the range 1 .. $DateIdx" -ForegroundColor Red
    $Response1 = "X" 
  }
else
  {
    try { 0 + $Response1 | Out-Null
        $dt1 = [int] $Response1
        If ($dt1 -gt $DateIDX) {
            Write-Host "The first entry ($Response1) is greater than the available entries ($DateIdx)" -ForegroundColor Red
            $Response1 = "X"
            }
        }
    catch{ 
        Write-Host "The first entry ($Response1) is not numeric" -ForegroundColor Red
        $Response1 = "Q"
      }
  }

$dt2 = 0
if ($Response2 -ne "") {
    try { 0 + $Response2 | Out-Null
        $dt2 = [int] $Response2
        If ($dt2 -gt $DateIDX) {
            Write-Host "The second entry ($Response2) is greater than the available entries ($DateIdx)" -ForegroundColor Red
            $Response2 = "X"
          }
      }
    catch{ 
        Write-Host "The second entry ($Response2) is not numeric" -ForegroundColor Red
        $Response2 = "XQ"
      }
  }

If ($Response1 -eq "X" -or $Response2 -eq "X") {
    pause
    return
  }


if (!(test-path $OutputFileCSv))
	{
		New-Item $OutputFileCSV -ItemType File|out-null
	}
"Node Name,Hotfix ID,Patch Type Description,Installed Date" > $OutputFileCSV


If ($Response2 -ne "") {
    If ($dt1 -gt $dt2) {
        $dtx = $dt1
        $dt1 = $dt2
        $dt2 = $dtx
      }
  }
Else {
    $dt2 = $dt1
  }

[int]$DateIDX = 0
$InstalledDates.GetEnumerator() | Sort-Object Value -Descending | Foreach {
    $DateIDX+=1
    if ($DateIDX -eq $dt1) {
        $EndDate = [datetime]($_.Value)               
       }
    if ($DateIDX -eq $dt2) {
        $StartDate = [datetime]($_.Value)               
       }
  }

$NodeName = ""

ForEach ($PatchHistoryRecord in $PatchHistory) {
    If (($PatchHistoryRecord).Length -lt 15) {
        $PatchHistoryRcdHdr = $PatchHistoryRecord
      }
    else {
        $PatchHistoryRcdHdr = ""
      }
    If ($PatchHistoryRcdHdr -match "-HST" -or $PatchHistoryRcdHdr -match "-HSA" -or $PatchHistoryRcdHdr -match "-CMP" -or $PatchHistoryRcdHdr -match "-CTL01" -or $PatchHistoryRcdHdr -match "-AD0" -or $PatchHistoryRcdHdr -match "-VMM" -or $PatchHistoryRcdHdr -match "-WDS" -or $PatchHistoryRcdHdr -match "-iSCSI") {
        $NodeName = $PatchHistoryRecord
      }
    ElseIf ($PatchHistoryRecord -match "InstalledOn") {
        $KBCol = $PatchHistoryRecord.IndexOf("HotFixID")
        $InstalledByCol = $PatchHistoryRecord.IndexOf("InstalledBy")
        $DateCol = $PatchHistoryRecord.IndexOf("InstalledOn")
      }
    ElseIf ($PatchHistoryRecord -match "--" -or $PatchHistoryRecord -eq "") {
        $x = 1
      }
    Else {
        $PatchTypeDesc = ($PatchHistoryRecord.Substring(0,$KBCol)).trim()
        $HotFixID = ($PatchHistoryRecord.Substring($KBCol, ($InstalledByCol - $KBCol))).trim()
        $InstalledDate = $PatchHistoryRecord.Substring($DateCol, 12)
        $InstalledDate = $InstalledDate.Substring(0, ($InstalledDate.IndexOf(" ")))

        If ([DateTime]$InstalledDate -ge $StartDate -and [DateTime]$InstalledDate -le $EndDate) {
            "$NodeName,$HotfixID,$PatchTypeDesc,$InstalledDate"  >> $OutputFileCSV
          }
      }
  }

$strStartDate = $StartDate.ToString("MM/dd/yyyy")
$strEndDate = $EndDate.ToString("MM/dd/yyyy")

if ($dt1 -eq $dt2) {
    Write-Host "Patching History for $strStartDate wrtten to $OutputFileCSV`n" -ForeGroundColor Green
  }
else {
    Write-Host "Patching History for $strStartDate through $strEndDate wrtten to $OutputFileCSV`n" -ForeGroundColor Green
  }

pause

