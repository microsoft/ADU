#* FileName: AddDiskToStoragePool.ps1
#*=============================================
#* Script Name: AddDiskToStoragePool.ps1
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

#Make sure user is running this tool under the right condition
Write-Host "This tool should only be ran when the following conditions are met:"
Write-Host "`t1. There has been one or multiple physical disk failures"
Write-Host "`t2. The physical disk(s) has already been replaced by a technician"
Read-Host "Press Enter to continue"

#initialize variables
$poolOwnerList=@() #list of storage pool owners
$canPoolDisks=@() #List of disks with canpool equal to true
$canPoolDiskOwner=@() #list owners found with disks to be added

#Get the Storage Pool Owners
$poolOwnerList = (get-clusterGroup | ? {$_.grouptype -eq "ClusterStoragePool"}).ownernode.name

$hostname = hostname
$domainName = $hostname.split("-")[0]

Write-Host "`nChecking storage pool owners for newly added disks..."
#Get list of disks with canpool = true
$poolOwnerList | foreach {
	Write-host -NoNewline "$_"
	$Disks=@() #temporary variable for the loop
	try
	{
		$Disks = Invoke-Command -ComputerName "$_.$domainName.fab.local" -ScriptBlock {get-physicaldisk | where {$_.canpool -eq "true"}}
	}
	catch
	{
		write-eventlog -entrytype Error -Message "Failed to get physical disk listing on $_ `n`n $_.exception" -Source $source -LogName ADU -EventId 9999
		Write-Error -ErrorAction Continue "Failed to get physical disk listing on $_ ... Exiting `n`n $_.exception"
		return
	}
	
	if($Disks)
	{
		Write-Host $canPoolDisks
		$canPoolDiskOwner+=$_
		$canPoolDisks+=$Disks
	}
	else
	{
		Write-Host -ForegroundColor Green " Done"
	}
}

if($canPoolDiskOwner)
{
	#Inform user of disk to be added
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Found disks to be added on the following hosts: $canPoolDiskOwner" 
	Write-Host "`nFound disks to be added on the following hosts: " $canPoolDiskOwner
	write-host "The following disks will be added to the storage pool: " ;$canPoolDisks | ft friendlyname,uniqueid,enclosurenumber,slotnumber,size,healthstatus,usage,serialnumber -AutoSize
	$userInput = Read-Host "Would you like to continue (y/n)?"

	if ($userInput -ne "y")
	{
		return
	}
	
	Write-Host "`nAdding disk(s) to storage Pool..."
	#Add disk to storage pool usage = hotspare
	$canPoolDiskOwner | foreach {
		Write-host "$_"
		$scriptblock = {
			$Disks=@()
			$sp = Get-StoragePool | ? {$_.friendlyname -ne "Primordial"}
			$disks = get-physicaldisk | where {$_.canpool -eq "true"}
			Add-PhysicalDisk -PhysicalDisks $disks -StoragePool $sp -Usage HotSpare
		}
		try
		{
			Invoke-Command -ComputerName "$_.$domainName.fab.local" -ScriptBlock $scriptblock
		}
		catch
		{
			Write-Error -ErrorAction Continue "Error adding canpool disks to pool on $_`n$_.exception"
			return
		}
	}

	Write-Host "`nDone"
	Write-Host "`n***Verifying no disks are left with `'canpool`' equal to true***`n"

	#rest the variables
	$canPoolDisks=@() #List of disks with canpool equal to true
	$canPoolDiskOwner=@() #list owners found with disks to be added
	$poolOwnerList | foreach {
		Write-host -NoNewline "$_"
		$Disks=@() #temporary variable for the loop
		$Disks = Invoke-Command -ComputerName "$_.$domainName.fab.local" -ScriptBlock {get-physicaldisk | where {$_.canpool -eq "true"}}
		if($Disks)
		{
			Write-Host $canPoolDisks
			$canPoolDiskOwner+=$_
			$canPoolDisks+=$Disks
		}
		else
		{
			Write-Host -ForegroundColor Green " Done"
		}
	}

	if($canPoolDiskOwner)
	{
		Write-Host -ForegroundColor Red "***Found disk that are still not part of the storage pool***"
		$canPoolDisks | ft friendlyname,uniqueid,enclosurenumber,slotnumber,size,healthstatus,usage,serialnumber -AutoSize
	}
	else
	{
		Write-Host -ForegroundColor Green "`n***No more disks found to be added to storage pool***`n"
	}
}
else
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "***No Disks found to add to storage pool***" #first event logged
	Write-Host -ForegroundColor Green "`n***No Disks found to add to storage pool***`n"
	return
}

