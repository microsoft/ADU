#--------------------------------------------------------------
# Verify_Domain_Admin_Pswd.ps1
#
# Author: sfacer 
#
# (C) 2018 Microsoft Corporation
#--------------------------------------------------------------

$ScriptAction = "Verify the Domain Admin Password" 

[void][System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.AccountManagement")

function Validate-Credentials([System.Management.Automation.PSCredential]$credentials)
{
    $pctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $Domain)
    $nc = $credentials.GetNetworkCredential()
    return $pctx.ValidateCredentials($nc.UserName, $nc.Password)
}

    $HostName = HostName

    If ($HostName -notlike "*HST0*")
      {
        Write-Host "Must be run on HST01 or HST02 ($HostName)" -ForegroundColor Red
        RETURN
      }

    $Domain = ($HostName.split("-"))[0]
    $AdminUser = $Hostname -replace "-HST01", "\Administrator"
    $Message = "Enter the Password for the domain Administrator account"

    $Cred = Get-Credential -UserName $AdminUser -Message $Message
    If(!$Cred) 
      {
        Write-Host "No Credential Supplied (user clicked CANCEL)" -ForegroundColor Yellow
        Pause
      }

    Elseif ((Validate-Credentials $cred) -eq $false)  
      {
        Write-Host "Authentication Failed" -ForegroundColor Red
        Pause
      }

    Else
      {
        Write-Host "Authentication Succeeded"  -ForegroundColor Green
        Pause
      }

