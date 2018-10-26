#* FileName: GetFullDump.ps1
#*=============================================
#* Script Name: GetFullDump.ps1
#* Created: [9/11/2018]
#* Author: Mario Barba Garcia
#* Company: Microsoft
#* Email: magarci@microsoft.com
#* Reqrmnts: Run from HST01
#* Keywords:
#*=============================================
#* Purpose: OneClick Get and Verify all information.
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Main code
Function OneClickGetAndVerify
{
    $scripts = Get-ChildItem -Path $PSScriptRoot | Where-Object {$_.Name.StartsWith("Verify-")}

    try
    {
        & "$PSScriptRoot\GetAPSData.ps1"
    }
    catch
    {
        Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem executing command $PSScriptRoot\GetFullDump.ps1 `n`n $($_.exception)"
        Write-Error "Problem executing command $PSScriptRoot\GetFullDump.ps1 `n`n $($_.exception)" -ErrorAction Continue 
    }

    try
    {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd-hh-mm")
        Start-Transcript -Path "D:\PDWDiagnostics\APS Verification\results_$timestamp.txt"
        & "$PSScriptRoot\VerifyFullDump.ps1"
        Stop-Transcript
		Write-Host "Results located in: D:\PDWDiagnostics\APS Verification"
    }
    catch
    {
        Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem executing command $PSScriptRoot\VerifyFullDump.ps1 `n`n $($_.exception)"
        Write-Error "Problem executing command $PSScriptRoot\VerifyFullDump.ps1 `n`n $($_.exception)" -ErrorAction Continue 
    }
}

. OneClickGetAndVerify