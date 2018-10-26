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
#* Purpose: Verifies dump information for all files collected.
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Main code
Function VerifyFullDump
{
    $scripts = Get-ChildItem -Path $PSScriptRoot | Where-Object {$_.Name.StartsWith("Verify-")}

    foreach($script in $scripts)
    {
        try
        {
            Write-Host "+++++++++++++++++++++ Executing $($script.Name) +++++++++++++++++++++`n`n"
            & "$PSScriptRoot\$($script.Name)"
        }
        catch
        {
            Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem executing command $script `n`n $($_.exception)"
            Write-Error "Problem executing command $script `n`n $($_.exception)" -ErrorAction Continue 
        }
    }

}

. VerifyFullDump