#* FileName: Add_Canpool_Disks_to_SP.ps1
#*=============================================
#* Script Name: Add_Canpool_Disks_to_SP.ps1
#* Created: [1/27/2013]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#* Physical disk has already been replaced
#*
#* Keywords:
#*=============================================
#* Purpose: Adds a newly replaced disk back to
#* the storage pool as a hot spare
#*=============================================

#Set up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#If this is a V1 hardware appliance, exit
$CsvList = Get-ClusterSharedVolume
if ($csvList.name -like "*SQL*")
{
	Throw "***V1 HARDWARE DETECTED*** This tool is not applicable on V1 hardware"
}

#Make sure user is running this tool under the right condition
Write-host -foregroundcolor cyan "`n=====================================
= Add CanPool Disks to Storage Pool =
====================================="

Write-Host "This tool will add disks to the storage pool that have 'Canpool' equal to 'True'.
This will be true of a newly added disk after a disk replacement. The new disk is not automatically 
added to the storage pool, so this tool will determine the proper storage pool then add it.

This is an online operation"

Read-host "`nPress enter to continue (CTRL-C to exit)"
 
write-host -foregroundcolor cyan "`nFinding disks with Canpool = True"
write-host -foregroundcolor cyan "---------------------------------"


#get a list of disks with canpool equal to true
$canpoolDiskList=@()
$canpoolDiskList = Get-physicaldisk | ? {$_.canpool -eq "true"}

if(!$canpoolDiskList)
{
	Write-host -foregroundcolor Green "`nNo disks found with canpool equal to true"
	return
}
Else
{
	foreach ($disk in  $canpoolDiskList)
	{
		#find another disk that has a very similar physicalLocation (minus slot number) and add our disk to that same storage pool as that disk
		$sp = (get-physicaldisk | 
        ? {$_.canpool -ne "true"} |
		? {$_.UniqueId -ne $disk.UniqueId} | 
		? {$_.PhysicalLocation -like "$($($disk.PhysicalLocation).split(':')[0])*"})[0] |
		get-storagepool | ? {$_.friendlyname -ne "Primordial"}

        Write-host -ForegroundColor cyan -nonewline "`nAdding: " 
        write-host $disk.friendlyname 
        Write-host -ForegroundColor cyan -NoNewline "With UniqueID: "
        write-host $disk.UniqueId
        Write-host -ForegroundColor cyan  -NoNewline "and Physical Location: "
        write-host $disk.PhysicalLocation
        Write-host -ForegroundColor cyan  -NoNewline "and CanPool Status: "
        write-host $disk.CanPool
        Write-host -ForegroundColor cyan -NoNewline "To Storage Pool: "
        write-host $sp.FriendlyName
        Write-host -ForegroundColor cyan -Nonewline "As a hot spare..."

        Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Adding $($disk.friendlyname) with uniqueID $($disk.uniqueID) and PhysicalLocation `'$($disk.PhysicalLocation)`' to storage pool $($sp.friendlyname) as a hot spare" #log that we are going to add the disk
        #Write-host -foregroundcolor cyan "`nAdding $($disk.friendlyname) `nuniqueID $($disk.uniqueID) `nPhysicalLocation $($disk.PhysicalLocation) to storage pool $($sp.friendlyname)"
		
        try
        {
            Add-PhysicalDisk -PhysicalDisks $disk -StoragePool $sp -Usage HotSpare
        }
        catch
        {
            Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "error encountered while attempting to add $($disk.friendlyname) with uniqueID $($disk.uniqueID) and PhysicalLocation `'$($disk.PhysicalLocation)`' to storage pool $($sp.friendlyname)" #log that the add failed
            Write-error "error encountered while attempting to add $($disk.friendlyname) with uniqueID $($disk.uniqueID) and PhysicalLocation `'$($disk.PhysicalLocation)`' to storage pool $($sp.friendlyname)" #write error to user
        }
        
        Write-host -ForegroundColor Green "Success"

        #read-host "`nPress Enter to proceed to the next disk"
	}

    Write-host -foregroundcolor cyan "`nUpdating storage cache on this node..."
    Update-HostStorageCache
    Update-StorageProviderCache -DiscoveryLevel Full
}

If (Get-physicaldisk | ? {$_.canpool -eq "true"})
{
    Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Found disks that still have canpool equal to true. Further troubleshooting may be required"
	Write-host -foregroundcolor red "`nFound disks that still have canpool equal to true. Further troubleshooting may be required"
}
else
{
    Write-host "Operation completed and no more disks found where `'canpool = true`'. It is reccomended that you run the update storage cache tool in ADU now."
}