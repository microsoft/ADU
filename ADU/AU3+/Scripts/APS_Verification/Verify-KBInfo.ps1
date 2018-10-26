#* FileName: Verify-KBInfo.ps1
#*=============================================
#* Script Name: Verify-KBInfo.ps1
#* Created: [9/11/2018]
#* Author: Mario Barba Garcia
#* Company: Microsoft
#* Email: magarci@microsoft.com
#* Reqrmnts: Run from HST01
#* Keywords:
#*=============================================
#* Purpose: Verifies KB information for all nodes.
#*=============================================

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Variables
$CustomerKBInfoPath = "D:\PdwDiagnostics\APS Verification\KBInfo"
$BaselineKBInfoPath = "D:\PDWDiagnostics\APS Verification\Baselines\KBInfo"


# This function will be called in Invoke-Command of VerifyBinaryInfo and will run in all nodes.
function CompareBaselineAndTarget
{
    Param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$KBInfoBaseline,
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$KBInfoClient
    )

    try 
    {
        $baseDict = New-Object 'System.Collections.Generic.HashSet[string]'
        $clientDict = New-Object 'System.Collections.Generic.HashSet[string]'
        $missingEntries = New-Object 'System.Collections.Generic.HashSet[string]'

        Write-Host "Comparing Baseline: $($KBInfoBaseline) and Customer file: $($KBInfoClient)"
        Write-Host ""


        # Read baseline KBInfo file
        $reader = [System.IO.File]::OpenText("$BaselineKBInfoPath\$KBInfoBaseline")
        try 
        {
            for() 
            {
                $item = $reader.ReadLine()
                if ($item -eq $null) { break }
                if($item.StartsWith("KB"))
                {
                    # process KB line
                    $baseDict.Add($item.trimend())  > $null
                }
            }
        }
        finally
        {
            $reader.Close()
        }

        # Read target KBInfo file
        $reader = [System.IO.File]::OpenText("$CustomerKBInfoPath\$KBInfoClient")
        try 
        {
            for() 
            {
                $item = $reader.ReadLine()
                if ($item -eq $null) { break }
                if($item.StartsWith("KB"))
                {
                    # process KB line
                    $clientDict.Add($item.trimend())  > $null
                }
            }
        }
        finally
        {
            $reader.Close()
        }
        
        
        if((Compare-Object $baseDict $clientDict) -eq $null)
        {
                Write-Host "Verified: $($KBInfoClient), no issues found." -ForegroundColor Green
                return
        }

        # collecting all of base information
        foreach($kb in $baseDict)
        {
            if(!$clientDict.Contains($kb))
            {
                $missingEntries.Add($kb) > $null
            }
            else
            {
                $clientDict.Remove($kb) > $null
            }
        }

        if($missingEntries.Count -ne 0)
        {
            Write-Host "ERROR: Client is missing the following hotfixes:" -ForegroundColor Red
            $missingEntries
            Write-Host ""
        }
        if($clientDict.Count -ne 0)
        {
            Write-Host "WARNING: Additional hotfixes found in client's node:" -ForegroundColor Yellow
            $clientDict
            Write-Host ""
        }
    }
    catch
    {
        Write-Host "Exception Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
        Write-Host "Exception Message: $($_.Exception.Message)" -ForegroundColor Red
    }
}

#Main code
Function VerifyBinaryInfo
{
    # Gather files to compare against baseline
    $CustomerKBInfoFiles = Get-ChildItem -Path $CustomerKBInfoPath -Filter "*.txt"
    $BaselineKBInfoFiles = Get-ChildItem -Path $BaselineKBInfoPath -Filter "*.txt"

    foreach ($file in $CustomerKBInfoFiles)
    {
        switch($file.Name)
        {
            {($_ -like "*CTL*")}   { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*CTL*"  } }
            {($_ -like "*CMP*")}   { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*CMP*"  } }
            {($_ -like "*HST*")}   { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*HST*"  } }
            {($_ -like "*HSA*")}   { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*HSA*"  } }
            {($_ -like "*AD*")}    { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*AD*"   } }
            {($_ -like "*ISCSI*")} { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*ISCSI*"} }
            {($_ -like "*VMM*")}   { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*VMM*"  } }
            {($_ -like "*WDS*")}   { $KBInfoBaseFile = $BaselineKBInfoFiles | Where-Object {$_ -like "*WDS*"  } }
            default     { break }
        }

        if($KBInfoBaseFile -eq $null)
        {
            Write-Host "Unable to locate baseline for $($file.Name)"
            Write-Host ""
        }
        else
        {
            $BaseFile = $KBInfoBaseFile | Select-Object -First 1
            CompareBaselineAndTarget $BaseFile $file
            Write-Host "`n******************************************************************`n"
        }
        
    }
}

. VerifyBinaryInfo