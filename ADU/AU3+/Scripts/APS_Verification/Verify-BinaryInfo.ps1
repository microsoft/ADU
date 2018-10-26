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
$PatchJournalPath = "C:\Servicing\PatchJournal.xml"
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Variables
$CustomerInfoPath = "D:\PdwDiagnostics\APS Verification\BinaryInfo"
$BaselineInfoPath = "D:\PDWDiagnostics\APS Verification\Baselines\BinaryInfo"


# This function will be called in Invoke-Command of VerifyBinaryInfo and will run in all nodes.
function CompareBaselineAndTarget
{
    Param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$Baseline,
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$target
    )

    try 
    {
        Write-Host "Comparing Baseline: $($Baseline.Name) and Customer file: $($target.Name)"

        $BaselineContent = Get-Content "$BaselineInfoPath\$Baseline"
        $TargetContent = Get-Content "$CustomerInfoPath\$Target"

        #First we have to check if we are comparing for same baseline, the version is in the first line of each file.
        $BaselineVersion = $BaselineContent| Select -Index 0
        $TargetVersion = $TargetContent | Select -Index 0

        if($BaselineVersion -ne $TargetVersion)
        {
            Write-Host "Error: Cannot compare files with different baseline version."
            Write-Host "Baseline file: $BaselineVersion"
            Write-Host "Customer file: $TargetVersion"
        }
        else
        {
            Write-Host "Baseline file and Client file are using same patch version: $BaselineVersion" -ForegroundColor Green

            if($(diff $BaselineContent $TargetContent).count -eq 0)
            {
                Write-Host "Verified: $($Target.Name), no differences found." -ForegroundColor Green
            }
            else
            {
                # We now check which lines are missing in client's file.
                $missingLinesInClientsFile = $BaselineContent | where { $TargetContent -notcontains $_}
                if($missingLinesInClientsFile.count -ne 0)
                {
                    # Now we convert the mismatch entries into BinaryObjects
                    [System.Collections.ArrayList]$missingClientsBinaryList = @()
                    [System.Collections.ArrayList]$BaselineBinaryList = @()

                    foreach($TargetEntry in $missingLinesInClientsFile)
                    {
                        $LineProperties = $TargetEntry.Split("|")

                        if($LineProperties.count -eq 4)
                        {
                            $BinaryObject = New-Object PSObject
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name Filename -Value $LineProperties[0]
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name Version -Value $LineProperties[1]
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name Size -Value $LineProperties[2]
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name LastModified -Value $LineProperties[3]
                            $missingClientsBinaryList += $BinaryObject
                        }
                    }

                    $missingBaselineEntries = $TargetContent | where { $BaselineContent -notcontains $_}
                    foreach($BaseEntry in $missingBaselineEntries)
                    {
                        $LineProperties = $BaseEntry.Split("|")

                        if($LineProperties.count -eq 4)
                        {
                            $BinaryObject = New-Object PSObject
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name Filename -Value $LineProperties[0]
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name Version -Value $LineProperties[1]
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name Size -Value $LineProperties[2]
                            Add-Member -InputObject $BinaryObject -MemberType NoteProperty -Name LastModified -Value $LineProperties[3]
                            $BaselineBinaryList += $BinaryObject
                        }
                    }

                    foreach($missingBinary in $missingClientsBinaryList)
                    {
                        $matchingfile = $BaselineBinaryList | Where-Object { $_.Filename -eq $missingBinary.Filename}
                        if($matchingfile -eq $null)
                        {
                           Write-Host "ERROR: Missing binary: $($missingBinary.Filename)" -ForegroundColor Red
                        }
                        else
                        {
                            if($($missingBinary.Version) -ne $($matchingfile.Version))
                            {
                                Write-Host "ERROR: Incorrect binary version for file: $($missingBinary.Filename)" -ForegroundColor Red    
                                Write-Host "Expected: $($missingBinary.Version)" -ForegroundColor Red
                                Write-Host "Actual:   $($matchingfile.Version)`n" -ForegroundColor Red
                            }
                            if($($missingBinary.Size) -ne $($matchingfile.Size))
                            {
                                Write-Host "ERROR: Incorrect binary size for file: $($missingBinary.Filename)" -ForegroundColor Red     
                                Write-Host "Expected: $($missingBinary.Size)" -ForegroundColor Red
                                Write-Host "Actual:   $($matchingfile.Size)`n" -ForegroundColor Red
                            }
                            if($($missingBinary.LastModified) -ne $($matchingfile.LastModified))
                            {
                                Write-Host "WARNING: File '$($missingBinary.Filename)' was modified" -ForegroundColor Yellow     
                                Write-Host "Expected: $($missingBinary.LastModified)" -ForegroundColor Yellow
                                Write-Host "Actual:   $($matchingfile.LastModified)`n" -ForegroundColor Yellow
                            }

                            $BaselineBinaryList.Remove($matchingfile)
                        }
                        Write-Host " "
                    }
                    
                    if($BaselineBinaryList.Count -ne 0)
                    {
                        Write-Host "WARNING: Found extra binaries in $Target that we didn't expect." -ForegroundColor Yellow 
                        $BaselineBinaryList | Format-Table Filename
                    }
                }
            }
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

    # Gather files to compare against baseline
    $CustomerBinaryInfoFiles = Get-ChildItem -Path $CustomerInfoPath -Filter "*$BaselineVersion*.txt"
    $BaselineBinaryInfoFiles = Get-ChildItem -Path $BaselineInfoPath -Filter "*$BaselineVersion*.txt"
    $BaselineVersion
    $BaselineInfoPath
    $BaselineBinaryInfoFiles
    foreach ($BinaryTargetFile in $CustomerBinaryInfoFiles)
    {
        switch($BinaryTargetFile.Name)
        {
            {($_ -like "*CTL*")}   { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*CTL*"  } }
            {($_ -like "*CMP*")}   { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*CMP*"  } }
            {($_ -like "*HST*")}   { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*HST*"  } }
            {($_ -like "*HSA*")}   { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*HSA*"  } }
            {($_ -like "*AD*")}    { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*AD*"   } }
            {($_ -like "*ISCSI*")} { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*ISCSI*"} }
            {($_ -like "*VMM*")}   { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*VMM*"  } }
            {($_ -like "*WDS*")}   { $BinaryBaseFile = $BaselineBinaryInfoFiles | Where-Object {$_ -like "*WDS*"  } }
            default     { break }
        }

        if($BinaryBaseFile -eq $null)
        {
            Write-Host "Unable to locate baseline for $($BinaryTargetFile.Name)`n" -ForegroundColor Red
        }
        else
        {
            $BaseFile = $BinaryBaseFile | Select-Object -First 1
            CompareBaselineAndTarget $BaseFile $BinaryTargetFile
            Write-Host "`n******************************************************************`n"
        }
        
    }
}

. VerifyBinaryInfo