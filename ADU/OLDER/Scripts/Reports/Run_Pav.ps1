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
#*	and collects logs with PDWDiag
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
		$PdwNodeList = GetNodeList -pdw -fqdn
		$mad01Name = $PdwNodeList | ? {$_ -like "*-MAD01*"}
		$pdwDomainName = ($mad01Name.split("-"))[0]
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error encountered Getting a nodelist. Ensure cluster is online `n $($_.exception)" -Source $source -logname "ADU" -EventID 9999
		Write-Error "Error encountered Getting a nodelist. Ensure cluster is online `n $($_.exception)"
	}
	
	###Test that we can get to MAD01
	if(!(Test-Path "\\$pdwDomainName-MAD01\C`$"))
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
		$CheckCred = CheckPdwCredentials -U $username -P $password -PdwDomain $pdwDomainName
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
	if(!$PavVersion)
	{
		Write-Host "wasn't able to get PAV version, trying with different credentials`nPlease enter the WORKLOAD DOMAIN credentials"
		$cred = Get-Credential -UserName "$pdwDomainName\administrator" -Message "Workload Domain credentials"
		$PavVersion = GetPavVersion -credential $cred
		
		if(!$PavVersion)
		{
			Write-EventLog -EntryType Error -message "Unable to get PAV Version - Verify that PAV is installed on MAD01 as Workload Domain Admin" -Source $source -logname "ADU" -EventID 9999
			Write-Host "`n"
			Write-Error "Unable to get PAV Version - Verify that PAV is installed on MAD01 as workload domain admin"
		}
	}
	$pavVersion

	###Check that versions match
	if($pavVersion -and ($PavVersion -ne $PDWVersion))
	{Write-Warning "PDW Version and PAV version mismatch - The installed PAV version should match the PDW version. If there were hotfixes installed a new version of PAV should be installed"}



	###Create the PAV command and output it to a file on MAD01
	$pavCommand = "cd 'c:\Program Files\Microsoft SQL Server PDW Appliance Validator\PSScripts';.\Run-PDWValidator.ps1 -buildnumber $PDWVersion -username $username -password $password -a"
	$pavCommand > "\\$mad01Name\c$\runPav.ps1"

	Write-Host -ForegroundColor Cyan "`nKicking off Appliance Validator. Please wait..."

	###Pull the content from the PS1, Delete it, then run the content in powershell this way there isn't a file with the password sitting there
	if($cred)
	{
		Invoke-Command -ComputerName "$mad01Name" -Credential $cred {$RunPav = get-content c:\runPav.ps1; rm c:\runPav.ps1;Powershell $runPav}
	}
	else
	{
		Invoke-Command -ComputerName "$mad01Name" {$RunPav = get-content c:\runPav.ps1; rm c:\runPav.ps1;Powershell $runPav}
	}
	###Collect PAV logs
	CollectPavLogs -nodelist $PdwNodeList
}


Function CollectPAVLogs
{	
	param($nodeList=$null)
	#Still just a test, but this works
	$date = get-date -f yyyy-MM-dd_hhmmss
	
	Try
	{
		CollectFiles -nodelist $nodeList -filepath "ProgramData\Microsoft\Microsoft SQL Server PDW Appliance Validator\Logs\0*\" -outputDir "C:\PdwDiagnostics\PAV_Logs\PavLogs_$date" -days 1
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error encountered collecting PAV files `n $($_.exception)" -Source $source -logname "ADU" -EventID 9999
		Write-error "Error encountered collecting PAV files `n $($_.exception)"
	}
}

. RunPav