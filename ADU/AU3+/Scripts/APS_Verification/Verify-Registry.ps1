#* FileName: VerifyBinaryInfo.ps1
#*=============================================
#* Script Name: VerifyBinaryInfo.ps1
#* Created: [9/11/2018]
#* Author: Mario Barba Garcia
#* Company: Microsoft
#* Email: magarci@microsoft.com
#* Reqrmnts: Run from HST01
#* Keywords:
#*=============================================
#* Purpose: Prints out binary information for all PDW binaries.
#*=============================================

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Variables
$CustomerRegistryInfoPath = "D:\PdwDiagnostics\APS Verification\RegistryInfo"
$BaselineRegistryInfoPath = "D:\PDWDiagnostics\APS Verification\Baselines\RegistryInfo"

# This function will be called in Invoke-Command of VerifyBinaryInfo and will run in all nodes.
function CompareBaselineAndTarget
{
    Param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$RegistryInfoBaseline,
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$RegistryInfoClient
    )

    try 
    {
        $baseFile =  "$BaselineRegistryInfoPath\$RegistryInfoBaseline"
        $clientFile = "$CustomerRegistryInfoPath\$RegistryInfoClient"

        $baseDict = @{}
        $clientDict = @{}
        $mismatchData = @{}
        $missingData = New-Object 'System.Collections.Generic.HashSet[string]'
        

        if (!(test-path $baseFile) -or !(test-path $clientFile))
        {
            Write-Host "ERROR: File doesn't exist" -ForegroundColor Red
            return
        }

        Write-Host "Comparing Baseline: $($RegistryInfoBaseline) and Customer file: $($RegistryInfoClient)`n"

        $rawDiff = diff (Get-Content $baseFile) (Get-Content $clientFile)
        if(($rawDiff).count -eq 0)
        {
            Write-Host "Check complete, no differences found`n" -ForegroundColor Green
            return
        }

        # Read file to gather categories to filter.
        $reader = [System.IO.File]::OpenText($baseFile)
        try 
        {
            for() 
            {
                $item = $reader.ReadLine()
                if ($item -eq $null) { break }
                # process the line
                $LineProperties = $item.Split("|")
                if($LineProperties.count -eq 2)
                {
                    if($baseDict[$LineProperties[0]] -eq $null)
                    {
                        $baseDict.Add($LineProperties[0],"$LineProperties[1]") > $null
                    }
                }
            }
        }
        finally
        {
            $reader.Close()
        }

        # Read file to gather categories to filter.
        $reader = [System.IO.File]::OpenText($clientFile)
        try 
        {
            for() 
            {
                $item = $reader.ReadLine()
                if ($item -eq $null) { break }
                # process the line
                $LineProperties = $item.Split("|")
                if($LineProperties.count -eq 2)
                {
                    if($clientDict[$LineProperties[0]] -eq $null)
                    {
                        $clientDict.Add($LineProperties[0],"$LineProperties[1]") > $null
                    }
                }
            }
        }
        finally
        {
            $reader.Close()
        }

        $diffFlag = $false;

        foreach($propertyKey in $baseDict.Keys)
        {
            if($clientDict[$propertyKey] -eq $null)
            {
                $missingData.Add($propertyKey) > $null
                $diffFlag = $true;
            }
            else
            {
                if($baseDict[$propertyKey] -ne $clientDict[$propertyKey])
                {
                    $mismatchData.Add($propertyKey,"Expected: $($baseDict[$propertyKey])|Actual:   $($clientDict[$propertyKey])") > $null
                    $diffFlag = $true;
                }
                $clientDict.Remove($propertyKey)
            }
        }

        if($missingData.Count -ne 0)
        {
            Write-Host "ERROR: Missing the following registry key entries in $RegistryInfoClient" -ForegroundColor Red
            $missingData
            Write-Host ""

        }
        if($mismatchData.Count -ne 0)
        {
            Write-Host "ERROR: Mismatch data found in the following registry key entries in $RegistryInfoClient" -ForegroundColor Red
            foreach($item in $mismatchData.Keys)
            {
                Write-Host "Property: $item"
                $values = $mismatchData[$item].Split('|')
                Write-Host $values[0]
                Write-Host $values[1]
                Write-Host ""
            }  
        }
        if($clientDict.Count -ne 0)
        {
            $diffFlag = $true
            Write-Host "WARNING: Extra regkeys found in client's registry:" -ForegroundColor Yellow
            $clientDict.Keys
        }
        
        if(!$diffFlag){
            # Missed an entry due to a duplicate key value in registry, dump raw diff.
            Write-Host "WARNING: Raw differences found in files:" -ForegroundColor Yellow
            $rawDiff
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
    $CustomerRegistryInfoFiles = Get-ChildItem -Path $CustomerRegistryInfoPath -Filter "*.txt"
    $BaselineRegistryInfoFiles = Get-ChildItem -Path $BaselineRegistryInfoPath -Filter "*.txt"

    foreach ($file in $CustomerRegistryInfoFiles)
    {
        switch($file.Name)
        {
            {($_ -like "*CTL*")}   { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*CTL*"  } }
            {($_ -like "*CMP*")}   { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*CMP*"  } }
            {($_ -like "*HST*")}   { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*HST*"  } }
            {($_ -like "*HSA*")}   { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*HSA*"  } }
            {($_ -like "*AD*")}    { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*AD*"   } }
            {($_ -like "*ISCSI*")} { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*ISCSI*"} }
            {($_ -like "*VMM*")}   { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*VMM*"  } }
            {($_ -like "*WDS*")}   { $RegistryInfoBaseFile = $BaselineRegistryInfoFiles | Where-Object {$_ -like "*WDS*"  } }
            default     { break }
        }

        if($RegistryInfoBaseFile -eq $null)
        {
            Write-Host "Warning: Unable to locate baseline for $($file.Name)`n" -ForegroundColor Yellow
        }
        else
        {
            $BaseFile = $RegistryInfoBaseFile | Select-Object -First 1
            CompareBaselineAndTarget $BaseFile $file
            Write-Host "`n******************************************************************`n"
        }
        
    }
}

. VerifyBinaryInfo