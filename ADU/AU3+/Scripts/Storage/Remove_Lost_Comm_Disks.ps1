#* FileName: Remove_Lost_Comm_Disks.ps1
#*=============================================
#* Script Name: Remove_Lost_Comm_Disks.ps1
#* Created: [9/1/2015]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*
#* Keywords:
#*=============================================
#* Purpose: Removes disks from the storage pool that are in the 
#* "Lost Communication" state
#*=============================================
Param([switch]$forceDiskRemoval)#This parameter only to be used by a senior engineer that understands the risk

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

Write-host -Foregroundcolor red "`nPLEASE READ BEFORE PROCEEDING"
Write-host -ForeGroundColor cyan "
After a disk is physically removed from a storage enclosure, the metadata for that disk
will remain in the storage pool. This will be in the form of a disk with 'OperationalStatus'
of 'Lost Communication'. 

This tool will remove from the storage pool that leftover metadata from the old disk.
"

$userinput1 = Read-host "`nWould you like to continue? (Y/N)"
if ($userinput1 -ne "Y")
{
	return
}

#Check that all of the virtual disks were healthy before proceeding
$vdList = Get-VirtualDisk
$badVdList = $vdList	| ? {$_.operationalstatus -ne "OK" -or $_.HealthStatus -ne "Healthy"}

if ($badVdList)
{
	if ($forceDiskRemoval)
	{
		$badVdList | ft -autosize
		Write-host -foregroundcolor yellow -backgroundcolor black "`nWARNING: Unhealthy virtual disks were found as seen above, but the `'ForceDiskRemoval`' switch was also specified"
		Write-host -foregroundcolor yellow -backgroundcolor black "Type `'Continue`' to continue with disk removal even though there are unhealthy virtual disks."
		Write-host -foregroundcolor red -backgroundcolor black "THIS HAS THE POTENTIAL TO CAUSE DATA LOSS!!!"
		$answer = read-host "CTRL-C to exit"
		
		if ($answer -ne "Continue")
		{
			write-host "`nExiting script..."
			return
		}
	}
	else
	{
		$badVdList
		Write-host ""
		write-error "UNHEALHTY VIRTUAL DISKS FOUND as seen above. Removing disks at this point could cause data loss. Exiting..."
	}
}
else
{
	Write-host "`nAll virtual disks healthy, proceeding with removal of lost communication disks"
}

#Get a list of disks in the lost communication state
$LostCommDisks = get-physicaldisk | ? {$_.OperationalStatus -eq "Lost Communication"}

If ($LostCommDisks)
{
	Write-host "Found the following disks in the 'Lost Communication' state:"
	$LostCommDisks | ft -autosize 
	
	Write-host "The list of disks above will attempted to be removed from teh storage pool. 
	There is no way to undo this action"
	
	$userinput2 = read-host "Would you like to continue? (Y/N)"
	if ($userinput2 -ne "Y")
	{
		return
	}
	
	foreach ($Disk in $lostCommDisks)
	{
		$sp = $disk | get-storagepool | ? {$_.friendlyname -ne "Primordial"}
		
		#attempt to remove the lost comm disks from the storage pool 
		Remove-PhysicalDisk -PhysicalDisks $disk -StoragePool $sp -confirm:$false
	}
}
Else
{
	Write-host -Foregroundcolor green -backgroundcolor black "`nDid not find any disks in the 'Lost Communication' state"
	Return
}

#recheck for lost comm disks
if( get-physicaldisk | ? {$_.OperationalStatus -eq "Lost Communication"})
{
	Write-host -foregroundcolor red "Still found disks in the 'Lost Communication' state. Further troubleshooting may be required"
}
