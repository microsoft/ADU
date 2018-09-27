#* FileName: Fix_Network_Connection_Public_Profile.ps1
#*=============================================
#* Script Name: Fix_Network_Connection_Public_Profile.ps1
#* Created: [9/1/2015]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: nicksalc@microsoft.com
#* Reqrmnts:
#* Keywords:
#*=============================================
#* Purpose: Will attempt to fix the "network connection
#* is on public profile" error that the admin console
#* may throw
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#
#*
#*=============================================
. $rootpath\Functions\PdwFunctions.ps1

$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire"
$source = $MyInvocation.MyCommand.Name #Set Source to scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Starting $source" 

#set node list to all physical nodes
$physNodeList = GetNodeList -phys

#check that nodes are all reachable	
Write-Host -ForegroundColor Cyan "`nChecking node connectivity"
$unreachableNodes = CheckNodeConnectivity $physNodeList

#remove any unreachable nodes from the nodeList
if($unreachableNodes)
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Warning -message "Removing the following unreachable nodes from the nodelist:`n$unreachableNodes"		
	Write-Host -ForegroundColor Yellow "The following nodes are unreachable, removing them from the node list"
	$unreachableNodes
	
	#remove the unreachable nodes from the list
	$physNodeList = $physNodeList | ? {$_ -notin $unreachableNodes}
	Write-Host "`n"
}
else 
{
	Write-Host -ForegroundColor Green "All nodes in list reachable`n"
}

#will return the adapter name if it found one
$CheckAdaptersFirewallProfiles =  
{
	$VmsAdaptersList = get-netadapter | ? {$_.name -like "*VMS*" }#-or (($_ | get-NetConnectionProfile -erroraction SilentlyContinue) -and ($_ | get-NetConnectionProfile).networkcategory -like "Public")}
	Foreach ($adapter in $VmsAdaptersList)
	{
		$profile = $adapter | Get-NetConnectionProfile
		if (($profile.networkcategory) -ne "DomainAuthenticated")
		{
			Write-host -ForegroundColor Red "$($adapter.name) is on the $($profile.networkCategory) Profile!"
	        
            Return $adapter.Name
		}
		else
		{
			Write-host "$($adapter.name) is on the $($profile.networkCategory) Profile"
		}
	}
}

$routeAddDeleteCmd = "route add 4.2.2.1 mask 255.255.255.255 4.2.2.2 ; route delete 4.2.2.1"


Write-host -foregroundcolor cyan "`nChecking all nodes in parallel for adapters on the public profile"
If ((ExecuteDistributedPowerShell -nodelist $physNodeList -command $CheckAdaptersFirewallProfiles))
{
	Write-host "`nFound adapter(s) not on public profile, attempting fix in parallel..."
	ExecuteDistributedPowerShell -nodelist $physNodeList -command $routeAddDeleteCmd

	Write-host "`nChecking if problem was resolved..."
	if ((ExecuteDistributedPowerShell -nodelist $physNodeList -command $CheckAdaptersFirewallProfiles))
	{
		Write-error "Was not able to fix firewall profiles using this method of adding and deleting a route. Please pursue other methods."
	}
}
else
{
	Write-host -foregroundcolor green "`nAll Adapters on the domain profile"
}




