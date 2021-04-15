#* FileName: Export_APS_Logins.ps1
#*=====================================================================
#* Script Name: Export_APS_Logins.ps1
#* Created: [02/15/2018]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=====================================================================
#* Purpose: Export APS Logins, for re-import
#*=====================================================================

#*=====================================================================
#* REVISION HISTORY
#*=====================================================================
#* Modified: 03/02/2018
#* Changes:
#* Original Version
#*=====================================================================

param([string]$username,[string]$password,[string]$database)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged


$HostName = HostName
$DomainName = ($HostName.Split("-"))[0]

[void][System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.AccountManagement")

function Validate-Credentials([System.Management.Automation.PSCredential]$credentials)
{
    $pctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainName)
    $nc = $credentials.GetNetworkCredential()
    return $pctx.ValidateCredentials($nc.UserName, $nc.Password)
}


#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
	{
		# Domain name and CTL host name
		$PDWHOST = GetNodeList -ctl	
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
        $ApplianceName = ($PDWHOST.Split("-"))[0]
		$OutputFile = "D:\PDWDiagnostics\Login\" + $ApplianceName + "_" + $CurrTime+ ".txt"

		if (!(test-path "D:\PDWDiagnostics\Login"))
			{
				New-item "D:\PDWDiagnostics\Login" -ItemType Dir | Out-Null
			}
		if (!(test-path $OutputFile))
			{
				New-Item $OutputFile -ItemType File|out-null
			}

	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}	


    $HostName = hostname
    $AdminUser = $Hostname -replace "-HST01", "\Administrator"

    $Message = "Export APS Logins"
    $Message += "`r`n`r`nEnter the Password for the domain Administrator account"


    $Cred = Get-Credential -UserName $AdminUser -Message $Message
    if(!$Cred) 
      {
        Write-Host "No Credential Supplied - Exiting Function"  -BackgroundColor Yellow -ForegroundColor DarkRed
        Pause
        Return
      }

    if ((Validate-Credentials $cred) -eq $false)  
      {
        Write-Host "Authentication Failed - Exiting Function"  -BackgroundColor Yellow -ForegroundColor DarkRed
        Pause
        Return
      }






## ===================================================================================================================================================================
Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

Try
  {
	$CTLNode=@()
	$CTLNode = GetNodeList -ctl
  }
catch
  {
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
  }


$SQLFileName_Drop = ".\AU3+\Config\explogin_Drop.txt"
$SQLFileName_Create1 = ".\AU3+\Config\explogin_Create1.txt"
$SQLFileName_Create2 = ".\AU3+\Config\explogin_Create2.txt"
$SQLExecute = "EXEC sp_explogin_APS"

Invoke-Sqlcmd -InputFile $SQLFileName_Drop -ServerInstance $CTLNode  -Database "TempDB"
Invoke-Sqlcmd -InputFile $SQLFileName_Create1 -ServerInstance $CTLNode  -Database "TempDB"
Invoke-Sqlcmd -InputFile $SQLFileName_Create2 -ServerInstance $CTLNode  -Database "TempDB"
$ScriptData = @()
$ScriptData = Invoke-Sqlcmd -Query "$SQLExecute" -ServerInstance $CTLNode  -Database "TempDB" -QueryTimeout 3600
Invoke-Sqlcmd -InputFile $SQLFileName_Drop -ServerInstance $CTLNode  -Database "TempDB"

$ScriptData | Export-Csv $OutputFile -NoTypeInformation -Append


Write-Host -ForegroundColor Cyan "`nOutput located at: $OutputFile"

Write-Host -ForegroundColor Magenta "`n/**----------------------------------------------------------------------------**/"
Write-Host -ForegroundColor Magenta "/**   >>>>>>> NOTE - CONTENTS OF THIS SCRIPT MUST NOT BE MODIFIED <<<<<<<      **/"
Write-Host -ForegroundColor Magenta "/**   >>>>>>> NOTE - BUT - ROWS MAY BE DELETED                    <<<<<<<      **/"
Write-Host -ForegroundColor Magenta "/**----------------------------------------------------------------------------**/"
Write-Host -ForegroundColor Cyan "/** Copy this file to D:\PDWDiagnostics\Login on HST01 on the target Appliance **/"
Write-Host -ForegroundColor Cyan "/** And execute the Import_APS_Logins option from ADU on that Appliance.       **/"
PAUSE

