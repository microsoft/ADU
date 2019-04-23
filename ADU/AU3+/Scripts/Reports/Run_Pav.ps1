#* FileName: RunPav.ps1
#*=============================================
#* Script Name: RunPav.ps1
#* Created: [1/3/2014]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*	Must be Pdw domain admin
#* Keywords:
#*=============================================
#* Purpose: Runs PAV from HST01 with less parameters 
#*	and collects logs with Diagnostics_Collection
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Date: [1/29/2014]
#* Issue:
#* Solution:
#*	Added event logging
#*=============================================
param($username=$null,$password=$null)
. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

function RunPav
{
	####Get  nodelist and set some names
	Try
	{
		$CtlNode = GetNodeList -ctl
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error encountered Getting a nodelist. Ensure cluster is online `n $($_.exception)" -Source $source -logname "ADU" -EventID 9999
		Write-Error "Error encountered Getting a nodelist. Ensure cluster is online `n $($_.exception)"
	}
	
	###Test that we can get to MAD01
	if(!(Test-Path "\\$CtlNode\C`$"))
	{
		Write-EventLog -EntryType Error -message "Error: User not PDW Domain Admin or MAD01\C`$ not reachable... Exiting" -Source $source -logname "ADU" -EventID 9999
		Throw "You must be PDW domain admin and MAD01 must be reachable to run this tool"
	}
	
	###get creds if we dont' have them already
	if(!$username){$username = GetPdwUsername}
	if(!$password){$password = GetPdwPassword}

	###Check the PDW creds
	Try
	{
		$CheckCred = CheckPdwCredentials -U $username -P $password
		if(!$CheckCred){Write-Error "failed to validate credentials"}
	}
	Catch
	{
		Write-EventLog -EntryType Error -message "Unable to validate Credentials" -Source $source -logname "ADU" -EventID 9999
		Write-Error "Unable to validate Credentials"
	}
	
	####Get PDW Version
	Try
	{
		Write-Host -NoNewline "Getting PDW Version... "
		$PDWVersion = GetPdwVersion -U $username -P $password
		write-host "$PdwVersion"
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error encountered getting PDW Version $($_.exception)" -Source $source -logname "ADU" -EventID 9999
		Write-Error "Error getting PDW Version: `n $($_.exception)"
	}
		
	####get PAV Version
	Try
	{
		Write-Host -NoNewline "Getting PAV Version... "
		$PavVersion = GetPavVersion
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error encountered getting PAV Version $($_.exception)" -Source $source -logname "ADU" -EventID 9999
		Write-Error "Error encountered getting PAV Version $($_.exception)" 
	}

	$pavVersion

	###Check that versions match
	if($pavVersion -and ($PavVersion -ne $PDWVersion))
	{Write-Warning "PDW Version and PAV version mismatch - The installed PAV version should match the PDW version. If there were hotfixes installed a new version of PAV should be installed"}

	###Create the PAV command and output it to a file on MAD01
	$pavCommand = "cd 'c:\Program Files\Microsoft SQL Server PDW Appliance Validator\PSScripts';.\Run-PDWValidator.ps1 -buildnumber $PDWVersion -username $username -password $password -a"
	$pavCommand > "\\$CtlNode\c$\runPav.ps1"
	
	#Get Domain password/regionname and create a cred object
	$fabreg = GetFabRegionName
	$domPass = GetDomainPassword
	
	#create the cred object
	$secpasswd = ConvertTo-SecureString "$domPass" -AsPlainText -Force
	$domainCred = New-Object System.Management.Automation.PSCredential("$fabreg\$env:username",$secpasswd)
	
	#start the CTL01 pssession
	Write-host "`nEntering CTL01 PSSession..."
	$Ctl01Session = New-Pssession -computername $CtlNode -credential $domainCred -Authentication Credssp
	
	#send the various commands to the session on CTL01 to start PAV
	invoke-command -session $Ctl01Session -scriptblock {$runPav = get-content C:\RunPav.ps1}
	invoke-command -session $Ctl01Session -scriptblock {rm c:\runPav.ps1}
	Write-Host -ForegroundColor Cyan "`nKicking off Appliance Validator. Please wait..."
	invoke-command -session $Ctl01Session -scriptblock {Invoke-expression $runPav}
	
	#clean up the session
	remove-pssession $Ctl01Session
	
	###Collect PAV logs
	Write-Host -foregroundcolor Cyan "`nCollecting results"
	CollectPavLogs -nodelist $CtlNode
}



Function CollectPAVLogs
{	
	param($nodeList=$null)

	$date = get-date -f yyyy-MM-dd_hhmmss
	
	Try
	{
		CollectFiles -nodelist $nodeList -filepath "ProgramData\Microsoft\Microsoft SQL Server PDW Appliance Validator\Logs\0*\" -outputDir "D:\PdwDiagnostics\PAV_Logs\PavLogs_$date" -days 1
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error encountered collecting PAV files `n $($_.exception)" -Source $source -logname "ADU" -EventID 9999
		Write-error "Error encountered collecting PAV files `n $($_.exception)"
	}
}


. RunPav