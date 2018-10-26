#* FileName: Get-RegistryInfo.ps1
#*=============================================
#* Script Name: Get-RegistryInfo.ps1
#* Created: [9/11/2018]
#* Author: Mario Barba Garcia
#* Company: Microsoft
#* Email: magarci@microsoft.com
#* Reqrmnts: Run from HST01
#* Keywords:
#*=============================================
#* Purpose: Dumps registry information for all nodes.
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Variables
$DefaultRegistryPath = "HKLM:SOFTWARE\Microsoft\Microsoft SQL Server Parallel Data Warehouse"
$PatchJournalPath = "C:\Servicing\PatchJournal.xml"
$RegistryPathsFile = "$rootPath\Config\RegistryPaths.txt"
$OutputFolder = "D:\PdwDiagnostics\APS Verification\RegistryInfo"

#Creating node list
$nodelist = GetNodeList -full

# This function will be called in Invoke-Command of GetRegistryInfo and will run in all nodes.
function CommandToExecute ($path)
{
    if (test-path $path)
    {
        $reg = Get-ChildItem -Path $path -Recurse
        foreach($item in $reg)
        {
            $properties = Get-ItemProperty $item.pspath | select * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSProvider
            Write-Output "$($item.PSChildName)|$properties"
        }
            
    }
}

#Main code
Function GetRegistryInfo
{
    # Get list of paths to scan.
    $RegistryPaths = New-Object System.Collections.ArrayList
    
    
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
            
    if (!(test-path $RegistryPathsFile))
    {
        # By default we check this folder.
        $RegistryPaths.Add($DefaultRegistryPath)  > $null
    }
    else
    {
        # Read file to gather all paths to scan.
        $reader = [System.IO.File]::OpenText($RegistryPathsFile)
        try 
        {
            for() 
            {
                $Path = $reader.ReadLine()
                if ($Path -eq $null) { break }
                # process the line
                $RegistryPaths.Add($Path) > $null
            }
        }
        finally
        {
            $reader.Close()
        }

        if($BinaryPaths.Count -eq 0)
        {
            $RegistryPaths.Add($DefaultRegistryPath)  > $null
        }
    }

    # Clean directory and move old files to archive before writing new files
    if (!(test-path "$OutputFolder\archive"))
    {
        New-Item -ItemType Directory -Path "$OutputFolder\archive" > $null
    }

    Move-Item -Path "$OutputFolder\*.txt" -Destination "$OutputFolder\archive" -Force

    foreach ($node in $nodelist)
    {
        $OutputFile = "$OutputFolder\RegistryInfo_$($timestamp)_$($BaselineVersion)_$($node).txt"

        if (test-path $OutputFile)
        {
            Remove-Item $OutputFile
        }

        New-Item $OutputFile -Force -ItemType File|out-null

        Write-Host "Dumping registry information for: $node..."

        "Baseline: $BaselineVersion" > $OutputFile

        foreach ($path in $RegistryPaths)
        {
            try
            {
                Invoke-Command $node -SCRIPTBLOCK ${function:CommandToExecute} -ArgumentList $path |out-file -append $OutputFile
            }
            catch
            {
                  Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem using path: $path and connecting to $node `n`n $($_.exception)"
                Write-Error "Problem using path: $path and connecting to $node `n`n $($_.exception)" -ErrorAction Continue 
            }
        }
     }
}

. GetRegistryInfo