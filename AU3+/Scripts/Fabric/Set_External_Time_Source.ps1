#Set up PDW to use an external time Source (AU3+)

param([string]$ipList)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

##Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

function Set_External_Time_Source
{
	#Set up our nodelists
	$nodelist = getNodeList -fullPdw
	$ADNodeList = $nodelist | select-string "-AD"
	$VmNodeList = $nodelist | select-string -NotMatch "-HS","-AD"
	$NodelistNoAD = $Nodelist | select-string -NotMatch "-AD"
	
	#Check that time is close enough on all servers for this process to work
	write-host -foregroundcolor cyan "`n________________________________________________________"
	Write-host -foregroundcolor cyan "Checking time on all servers is correct within 5 minutes"
	write-host -foregroundcolor cyan "________________________________________________________"	
	
	$dateList = ExecuteDistributedPowerShell -nodelist $NodeList -command "Get-Date"
	$HST01Date = $datelist | ? {$_.pscomputername -like "*-HST01"}
	foreach ($date in $dateList)
	{
		$difference = $HST01Date - $date 
		if ($difference.Totalminutes -gt 5)
		{
			write-host ""
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "DATE ON $($date.pscomputername) (AND POSSIBLY OTHERS) IS MORE THAN 5 MINUTES OFF FROM HST01. GET ALL SERVERS WITHIN 5 MINUTES BEFORE ATTEMPTING THIS OPERATION"
			Write-error "DATE ON $($date.pscomputername) (AND POSSIBLY OTHERS) IS MORE THAN 5 MINUTES OFF FROM HST01. GET ALL SERVERS WITHIN 5 MINUTES BEFORE ATTEMPTING THIS OPERATION"
		}
	}
	
	if (!$ipList)
	{
		$ipList += read-host "`nPlease Enter the names(s) or IP(s) of the external Time source(s) in a space-separated list`n(leave blank to revert to not sync from NTP)"
	}
	
	If($ipList)
	{
		Write-host -foregroundcolor cyan "`nExternal time server(s) will be set to: $IpList"
	}
	Else
	{
		Write-host -foregroundcolor cyan "`nTime setting will now be reverted to not sync to an NTP server"
		[switch]$disableNtp=$true
	}
	Read-host "Press Enter to continue"
	
	

	
	#set commands for the rest of the script
	$RegAddCmd = "reg add HKLM\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider /v Enabled /t reg_dword /d 0 /f"
	$ADTimeSourceCmd = "w32tm /config /manualpeerlist:`"$iplist`" /syncfromflags:MANUAL /reliable:yes /update"
	$ServerTimeSourceCmd = "w32tm /config /syncfromflags:DOMHIER /update"
	$restartW32TimeCmd = "net stop w32time ; net start w32time"
	$resyncW32TimeCmd = "w32tm /resync /force"
	$queryTimeSourceCmd = "w32tm /query /source"
	
	$ChangeTimeSourceMessage = "Setting this appliance to sync to the following external time source(s): $ipList"
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "$ChangeTimeSourceMessage" #log that we are changing the time source
	
	try
	{
		#Set up AD servers
		write-host -foregroundcolor cyan "`n___________________________________________________"
		Write-host -foregroundcolor cyan "Setting VMICTimeProvider Registry key on AD Servers"
		write-host -foregroundcolor cyan "___________________________________________________"
		ExecuteDistributedPowerShell -nodelist $AdNodeList -command $RegAddCmd
		

		ExecuteDistributedPowerShell -nodelist $AdNodeList -command $ADTimeSourceCmd
		if ($disableNtp)
		{
			write-host -foregroundcolor cyan "`n_____________________________________"
			Write-host -foregroundcolor cyan "Setting AD02 to point to AD01 for time"
			write-host -foregroundcolor cyan "______________________________________"
			
			#set AD02 to sync to AD01
			$AD01 = $ADNodeList | select-string "-AD01"
			$AD02 = $ADNodeList | select-string "-AD02"
			$disableNtpAd02Cmd = "w32tm /config /manualpeerlist:`"$AD01`" /syncfromflags:MANUAL /reliable:yes /update"
			ExecuteDistributedPowerShell -nodelist $AD02 -command $disableNtpAd02Cmd
			
		}
		
		write-host -foregroundcolor cyan "`n________________________________"
		Write-host -foregroundcolor cyan "Restarting W32Time on AD Servers"
		write-host -foregroundcolor cyan "________________________________"
		ExecuteDistributedPowerShell -nodelist $AdNodeList -command $restartW32TimeCmd
		
		write-host -foregroundcolor cyan "`n________________________________"
		Write-host -foregroundcolor cyan "Re-syncing w32Time on AD Servers"
		write-host -foregroundcolor cyan "________________________________"
		ExecuteDistributedPowerShell -nodelist $AdNodeList -command $resyncW32TimeCmd
		
		write-host -foregroundcolor cyan "`n______________________________________________________________"
		Write-host -foregroundcolor cyan "Querying AD Time Source, this should be one of the IPs you set"
		write-host -foregroundcolor cyan "______________________________________________________________"
		ExecuteDistributedPowerShell -nodelist $AdNodeList -command $queryTimeSourceCmd
		
		#set registry key on VMs to not sync to physical host
		write-host -foregroundcolor cyan "`n________________________________________________"
		Write-host -foregroundcolor cyan "Setting VMICTimeProvider Registry key on all VMs"
		write-host -foregroundcolor cyan "________________________________________________"
		ExecuteDistributedPowerShell -nodelist $VmNodeList -command $RegAddCmd
		
		#Set the time source to AD on all servers
		write-host -foregroundcolor cyan "`n_________________________________"
		Write-host -foregroundcolor cyan "Restarting W32Time on all Servers" 
		write-host -foregroundcolor cyan "_________________________________"
		ExecuteDistributedPowerShell -nodelist $NodelistNoAD -command $ServerTimeSourceCmd
		
		write-host -foregroundcolor cyan "`n___________________________________________"
		Write-host -foregroundcolor cyan "Re-syncing w32Time on all servers except AD"
		write-host -foregroundcolor cyan "___________________________________________"
		ExecuteDistributedPowerShell -nodelist $NodelistNoAD -command $resyncW32TimeCmd

		write-host -foregroundcolor cyan "`n___________________________________________________________________________________________________________________"
		Write-host -foregroundcolor cyan "Querying Time Source, this should return the AD server on all servers except AD, which should return an External IP"
		write-host -foregroundcolor cyan "___________________________________________________________________________________________________________________"
		ExecuteDistributedPowerShell -nodelist $Nodelist -command $queryTimeSourceCmd
	}
	catch
	{
		Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Changing the time source to an external source failed at some point in the process with the following error: $_" 
		write-error "Failed to change time source: $_"
	}
	
	Write-host -foregroundcolor cyan "`n***Review the output of the last command above to make sure everything was set successfully***"
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Time source successfully changed to $ipList" 
}

. Set_External_Time_Source