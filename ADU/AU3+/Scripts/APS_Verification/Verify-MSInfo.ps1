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
$CustomerMSInfoPath = "D:\PdwDiagnostics\APS Verification\MSInfo"
$BaselineMSInfoPath = "D:\PDWDiagnostics\APS Verification\Baselines\MSInfo"
$CategoriesToFilter = "$rootPath\Config\MSInfoCategories.txt"
$PropertiesToFilter = "$rootPath\Config\MSInfoIgnoreProperties.txt"
$CategoriesList = New-Object System.Collections.ArrayList
$IgnoreList = New-Object System.Collections.ArrayList


# This function will be called in Invoke-Command of VerifyBinaryInfo and will run in all nodes.
function CompareBaselineAndTarget
{
    Param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$MSInfoBaseline,
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$MSInfoClient
    )

    try 
    {
        $baseFile = "$BaselineMSInfoPath\$MSInfoBaseline"
        $clientFile = "$CustomerMSInfoPath\$MSInfoClient"

        if (!(test-path $baseFile) -or !(test-path $clientFile))
        {
            Write-Host "ERROR: File doesn't exist" -ForegroundColor Red
            return
        }

        [xml]$baseXml = Get-Content $baseFile
        [xml]$clientXml = Get-Content $clientFile

        $baseDict = @{}
        $clientDict = @{}

        if (!(test-path $CategoriesToFilter))
        {
            # default values
            $CategoriesList.Add('System Summary')  > $null
            $CategoriesList.Add('Services')  > $null
            $CategoriesList.Add('System Drivers')  > $null
        }        
        else
        {
            # Read file to gather categories to filter.
            $reader = [System.IO.File]::OpenText($CategoriesToFilter)
            try 
            {
                for() 
                {
                    $item = $reader.ReadLine()
                    if ($item -eq $null) { break }
                    # process the line
                    $CategoriesList.Add($item)  > $null
                }
            }
            finally
            {
                $reader.Close()
            }
        }
        
        if (!(test-path $PropertiesToFilter))
        {
            # default values
            $IgnoreList.Add('System Name')  > $null
        }        
        else
        {
            # Read file to gather categories to filter.
            $reader = [System.IO.File]::OpenText($PropertiesToFilter)
            try 
            {
                for() 
                {
                    $item = $reader.ReadLine()
                    if ($item -eq $null) { break }
                    # process the line
                    $IgnoreList.Add($item)  > $null
                }
            }
            finally
            {
                $reader.Close()
            }
        }

        # collecting all of base information
        foreach($Category in $CategoriesList)
        {
            $filterCategory = $baseXml.SelectNodes("//Category[@name='$($Category)']").Data
            
            foreach($item in $filterCategory)
            {
                if($baseDict[$item.ChildNodes[0].InnerText] -eq $null)
                {
                    $properties = ""
                    foreach($property in $item.ChildNodes)
                    {
                        $properties += " $($property.InnerText) |"
                    }

                    $properties = $properties.replace($($item.ChildNodes[0].InnerText), "")
                    $baseDict.Add($item.ChildNodes[0].InnerText, $properties)
                }
            }
        }

        # collecting all of client information
        foreach($Category in $CategoriesList)
        {
            $filterCategory = $clientXml.SelectNodes("//Category[@name='$($Category)']").Data
            
            foreach($item in $filterCategory)
            {
                if($clientDict[$item.ChildNodes[0].InnerText] -eq $null)
                {
                    $properties = ""
                    foreach($property in $item.ChildNodes)
                    {
                        $properties += " $($property.InnerText) |"
                    }
 
                    $properties = $properties.replace($($item.ChildNodes[0].InnerText), "")
                    $clientDict.Add($item.ChildNodes[0].InnerText, $properties)
                }
            }
        }

        Write-Host "Comparing Baseline: $($MSInfoBaseline) and Customer file: $($MSInfoClient)`n"

        $errors = $false;

        foreach($propertyKey in $baseDict.Keys)
        {
            # First check ignore list.
            if($IgnoreList.Contains($propertyKey)){ continue }

            if($clientDict[$propertyKey] -eq $null)
            {
                Write-Host "Error: Client is missing $propertyKey property.`n" -ForegroundColor Red
                $errors = $true
            }
            else
            {
                if($baseDict[$propertyKey] -ne $clientDict[$propertyKey])
                {
                    Write-Host "ERROR: property '$propertyKey' in $MSInfoClient contains unexpected value"
                    Write-Host "Expected: $($baseDict[$propertyKey])" -ForegroundColor Red
                    Write-Host "Actual:   $($clientDict[$propertyKey])`n" -ForegroundColor Red
                    $errors = $true
                }
            }
        }

        if(!$errors){ Write-Host "Check complete, no differences found" -ForegroundColor Green }

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
    $CustomerMSInfoFiles = Get-ChildItem -Path $CustomerMSInfoPath -Filter "*.nfo"
    $BaselineMSInfoFiles = Get-ChildItem -Path $BaselineMSInfoPath -Filter "*.nfo"

    foreach ($file in $CustomerMSInfoFiles)
    {
        switch($file.Name)
        {
            {($_ -like "*CTL*")}   { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*CTL*"  } }
            {($_ -like "*CMP*")}   { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*CMP*"  } }
            {($_ -like "*HST*")}   { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*HST*"  } }
            {($_ -like "*HSA*")}   { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*HSA*"  } }
            {($_ -like "*AD*")}    { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*AD*"   } }
            {($_ -like "*ISCSI*")} { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*ISCSI*"} }
            {($_ -like "*VMM*")}   { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*VMM*"  } }
            {($_ -like "*WDS*")}   { $MSInfoBaseFile = $BaselineMSInfoFiles | Where-Object {$_ -like "*WDS*"  } }
            default     { break }
        }

        if($MSInfoBaseFile -eq $null)
        {
            Write-Host "Warning: Unable to locate baseline for $($file.Name)`n" -ForegroundColor Yellow
        }
        else
        {
            $BaseFile = $MSInfoBaseFile | Select-Object -First 1
            CompareBaselineAndTarget $BaseFile $file
            Write-Host "`n******************************************************************`n"
        }
        
    }
}

. VerifyBinaryInfo