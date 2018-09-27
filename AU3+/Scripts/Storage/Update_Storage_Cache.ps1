#* FileName: Update_Storage_Cache.ps1
#*=============================================
#* Script Name: Update_Storage_Cache.ps1
#* Created: [9/2/2015]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#* Keywords:
#*=============================================
#* Purpose:
#*	Will update storage cache on all physical nodes
#*=============================================
. $rootPath\Functions\PdwFunctions.ps1

#Set up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

Try
{
	$physList=@()
	$physList = GetNodeList -phys
}
catch
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
}

$updateCacheCmd = "Update-HostStorageCache;Update-StorageProviderCache -DiscoveryLevel Full"

Write-host -Foregroundcolor cyan "`nUpdating Storage cache across all physical nodes in parallel"

ExecuteDistributedPowerShell -nodeList $physList -command $updateCacheCmd