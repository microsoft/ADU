#* FileName: Get-SystemInfo.ps1
#*=============================================
#* Script Name: Get-SystemInfo.ps1
#* Created: [9/11/2018]
#* Author: Mario Barba Garcia
#* Company: Microsoft
#* Email: magarci@microsoft.com
#* Reqrmnts: Run from HST01
#* Keywords:
#*=============================================
#* Purpose: Dumps MSI, SystemInfo and Hotfix information for all nodes.
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
$PatchJournalPath = "C:\Servicing\PatchJournal.xml"
$OutputFolder = "D:\PdwDiagnostics\APS Verification\"
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Creating node list
$nodelist = GetNodeList -full

#Main code
Function GetSystemInfo
{

    if (!(test-path $PatchJournalPath))
    {
        Write-Host "ERROR: File $PatchJournalPath doesn't exist."
        return
    }

    # Get baseline information.
    [xml]$xmlDoc = Get-Content $PatchJournalPath
    $Baseline = $xmlDoc.PdWUpdates.UpdateResult | Where-Object {$_.ExitCode -eq 0} | Select-Object -Last 1

    if($Baseline -eq $null) 
    {
        Write-Host "ERROR: Unable to retrieve baseline information for the appliance."
        return
    }

    $BaselineVersion = $Baseline.Name
    $timestamp = (Get-Date).ToString("yyyy-MM-dd-hh-mm")

    # Clean directory and move old files to archive before writing new files
    if (!(test-path "$OutputFolder\SystemInfo\archive"))
    {
        New-Item -ItemType Directory -Path "$OutputFolder\SystemInfo\archive" > $null
    }

    Move-Item -Path "$OutputFolder\SystemInfo\*.txt" -Destination "$OutputFolder\SystemInfo\archive" -Force

    # Clean directory and move old files to archive before writing new files
    if (!(test-path "$OutputFolder\MSInfo\archive"))
    {
        New-Item -ItemType Directory -Path "$OutputFolder\MSInfo\archive" > $null
    }

    Move-Item -Path "$OutputFolder\MSInfo\*.nfo" -Destination "$OutputFolder\MSInfo\archive" -Force

    # Clean directory and move old files to archive before writing new files
    if (!(test-path "$OutputFolder\KBInfo\archive"))
    {
        New-Item -ItemType Directory -Path "$OutputFolder\KBInfo\archive" > $null
    }

    Move-Item -Path "$OutputFolder\KBInfo\*.txt" -Destination "$OutputFolder\KBInfo\archive" -Force

    foreach ($node in $nodelist)
    {
        $SystemInfoOutputFile = "D:\PdwDiagnostics\APS Verification\SystemInfo\SystemInfo_$($timestamp)_$($BaselineVersion)_$($node).txt"
        $MSInfoOutputFile = "D:\PdwDiagnostics\APS Verification\MSInfo\MSInfo_$($timestamp)_$($BaselineVersion)_$($node).nfo"
        $KBInfoOutputFile = "D:\PdwDiagnostics\APS Verification\KBInfo\KBInfo_$($timestamp)_$($BaselineVersion)_$($node).txt"

        if (test-path $SystemInfoOutputFile)
        {
            Remove-Item $SystemInfoOutputFile
        }

        if (test-path $MSInfoOutputFile)
        {
            Remove-Item $MSInfoOutputFile
        }

        if (test-path $KBInfoOutputFile)
        {
            Remove-Item $KBInfoOutputFile
        }

        New-Item $SystemInfoOutputFile -Force -ItemType File|out-null
        New-Item $MSInfoOutputFile -Force -ItemType File|out-null
        New-Item $KBInfoOutputFile -Force -ItemType File|out-null

        Write-Host "Dumping system information for: $node..."

        try
        {
            systeminfo /S $node |out-file -append $SystemInfoOutputFile
        }
        catch
        {
            Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem executing systeminfo in $node `n`n $($_.exception)"
            Write-Error "Problem executing systeminfo in $node `n`n $($_.exception)" -ErrorAction Continue 
        }

        try
        {
            msinfo32 /nfo $MSInfoOutputFile /computer $node | Out-Null
        }
        catch
        {
            Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem executing msinfo32 in $node `n`n $($_.exception)"
            Write-Error "Problem executing msinfo32 in $node `n`n $($_.exception)" -ErrorAction Continue 
        }

        try
        {
            Get-HotFix -ComputerName $node | Format-Table hotfixid |out-file -append $KBInfoOutputFile
        }
        catch
        {
            Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem executing Get-Hotfix in $node `n`n $($_.exception)"
            Write-Error "Problem executing Get-Hotfix in $node `n`n $($_.exception)" -ErrorAction Continue 
        }
     }
}

. GetSystemInfo