#* FileName: StoragehealthCheck.ps1
#*=============================================
#* Script Name: StoragehealthCheck.ps1
#* Created: [3/26/2014]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*
#* Keywords:
#*
#*=============================================
#* Purpose: Runs a health check against the storage subsystem
#*=============================================
#Tests: 
# All physical disks healthy
# All Virtual disks healthy
# All Storage Pools healthy
# No physical disks with canpool = true
# All CSV's online
# All CSV's aligned
# All Virtual disks have 2 Physical disks
#-------
# there are 2 Hot spares available for each enclosure
# The proper # of virtual disks exist
# Every disk belongs to only 1 virtual disk

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Date: 4/8/2014
#* Time: 11:29 AM PST
#* ChangeList: Added Storage reliability counters
#* test. Made the data collection run in parallel 
#* accross SP owners. Old code is still in comments 
#* if there are issues. 
#*
#* Date: 4/14/2014
#* Time: 1:17 PM
#* Changelist: Created a function to create a test object.
#* outputting made easier due to function usage
#*
#* Date: 4/22/2014
#* Time: 10:42 AM
#* ChangeList: Collect PD Data from all HSAs - modify output
#* to include PSComputerName#* 
#* 
#* Date: 10/142019
#* Simon Facer
#* ChangeList:
#* 1. Streamlined work-around processing for invalid # p-disk in v-disk, to read data one time only
#* 2. Corrected reporting for invalid # p-disk in v-disk, to correctly report # of p-disks found
#*=============================================
. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire"
$source = $MyInvocation.MyCommand.Name #Set Source to scriptname
New-EventLog -Source $source -LogName ADU -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Starting $source" 

#########################
# Version Number        #
#########################
$toolVersion="v1.3"
#########################

$CsvList = Get-ClusterSharedVolume

#If this is a V1 hardware appliance, exit
if ($csvList.name -like "*SQL*")
{
	Throw "***V1 HARDWARE DETECTED*** This tool is not applicable on V1 hardware"
}

function StorageHealthCheck
{
	##################################
	# Collect raw physical disk data #
	##################################
	Write-host "`nCollecting raw physical disk data"
	try
	{
		write-debug "Getting Disk list"
		$disklist = get-physicaldisk | ? {$_.PhysicalLocation -like "SES Enclosure*"} #gets list of external disks
		
		write-debug "Getting storage reliability counters from disks in disklist"
		$counters = $disklist | Get-StorageReliabilityCounter #gets storage reliability counters from all disks
		
		Write-Debug "Adding reliability Counter results to output"
		foreach($disk in $disklist)
		{
			write-debug "$($disk.friendlyname)"
			$disk | Add-Member -MemberType NoteProperty -Name Reliability -Value ($counters | ? {"$($_.objectid.split("{").split("}")[5])" -eq "$($disk.objectid.split("{").split("}")[5])"})
		}
		
		$PDiskData = $disklist | 
		select-object Friendlyname,UniqueID,ObjectId,CanPool,DeviceId,FirmwareVersion,operationalStatus,healthstatus,usage,SerialNumber,PhysicalLocation,
		@{label="Size (TB)";Expression={$a= $_.size/1024/1024/1024/1024;"{0:N2}" -f $a}},reliability 

		if (!$PDiskData)
		{
			Throw "RAW PHYSICAL DISK DATA WAS NULL!!!"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error collecting Physical Disk data across appliance`n$_" -Source $source -logname "ADU" -EventID 9999
		Throw "Error Collecting Physical disk data across the appliance... Exiting`n$_"
	}

	########################
	# Collect raw CSV data #
	########################
	try
	{
		write-host "`nCollecting CSV data"
		$CsvData = Get-ClusterSharedVolume
		
		if (!$CsvData)
		{
			Throw "RAW CSV DATA WAS NULL!!!"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error collecting Cluster Shared Volume data, The cluster is probably not running`n$_" -Source $source -logname "ADU" -EventID 9999
		Throw "Error collecting Cluster Shared Volume data, The cluster is probably not running`n$_"
	}

	#################################
	# Collect raw virtual disk data #
	#################################
	Try
	{
		Write-host "`nCollecting raw virtual disk data"
		$VDiskData=@()
		$VDiskData= get-virtualdisk | ? {$_.OperationalStatus -ne "Detached"}|
		        select-object Friendlyname,@{Expression={($_ | Get-physicaldisk).UniqueID};Label="Physical Disks (UniqueID's)"},@{Label="PD_Count";Expression={($_ | get-physicaldisk).count}},
		        ObjectId,OperationalStatus,HealthStatus
	
		#order the raw virtual disk data
		$VDiskData = $VDiskData | Sort-Object Friendlyname
		
		if (!$VdiskData)
		{
			Throw "RAW VIRTUAL DISK DATA WAS NULL!!!"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error collecting Virtual Disk data accross appliance`n$_" -Source $source -logname "ADU" -EventID 9999
		Throw "Error collecting Virtual Disk data accross appliance... Exiting`n$_"
	}

	#################################
	# Collect raw Storage Pool data #
	#################################
	try
	{
		Write-Host "`nCollecting raw Storage Pool Data"
		$SPData = @()
		$SPData =	Get-StoragePool | ? {$_.FriendlyName -ne "Primordial"} | 
			Select-Object Friendlyname,OperationalStatus,HealthStatus

		#create an object for the overall test result (gets marked as failed if anything fails)
		$OverallTest = New-Object system.object
		$OverallTest | add-member -type NoteProperty -Name "Test Name" -value "Overall Health Test"
		$OverallTest | add-member -type NoteProperty -Name "Result" -Value "Pass"
		
		if (!$SPData)
		{
			Throw "RAW STORAGE POOL DATA WAS NULL!!!"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error collecting storage pool data accross appliance`n$_" -Source $source -logname "ADU" -EventID 9999
		Throw "Error collecting storage pool data accross appliance... Exiting`n$_"
	}

	Write-host "`nRunning tests..."

	######################################
	# Check for unhealthy Physical Disks #
	######################################
	try
	{
		$PdHealthyTest = New-TestObj -test_name "Healthy Physical Disks" -outputObj "`$unhealthyPds"

		#variable to hold the unhealthy physicaldisks found
		$unhealthyPds=@()

		$PDiskData | % {if ($_.healthstatus -ne "healthy" -or $_.OperationalStatus -ne "OK") 
		    {
		        $PdHealthyTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $unhealthyPds += $_
		    }
		}
		if($PdHealthyTest.result -ne "Pass")
		{
			$PdHealthyTest.comment = "<pre>This test checks accross all storage attached nodes for disks that either have a healthstatus that is not equal to `'healthy`',<br>or operationalStatus that is not equal to `'OK`'. Below is a description of what different disk states mean<br>Note the reporting node as a disk can be reported as different states from different nodes.

OPERATIONALSTATUS	DESCRIPTION
OK:			No rebuild jobs running on this disk. Disk is operational
Lost Communication:	Could not communicate with disk
InService:		Rebuild job is currently running. Get-storagejob will show current rebuilds in the current storage pool
Degraded:		Drives in the virtual disk have failed or been removed and it is running in a degraded state
Starting:		Disk is attempting to start. If it is in this state for a long period – more than 5 minutes there could be an issue.

HEALTHSTATUS	DESCRIPTION
Healthy:	Disk is Healthy
Unhealthy:	Disk Is Unhealthy. Could happen if a drive fails and there is not spare to take over.
Unknown:	Cannot communicate with disk. Generally the unknown status is shows because the current node is not the storage pool owner. Do a get-clustergroup to get the owners (the owners of the long GUIDS).
Warning:	There is a warning on the disk – This state will happen while the disk is ‘inService’ meaning a storage rebuild job is running. 

USAGE		DESCRIPTION
AutoSelect:	Disk that is playing an active role in the storage space
HotSpare:	Standby drive ready to take over when another drive fails
ManualSelect:	Disk may be in use, but it is set to not change usage automatically. Our ISCSI disks are generally manualSelect
Retired:	Disk is not currently in use. A disk will get marked retired sometimes during failure, but can also happen if a disk is removed and re-added
Unknown:	Cannot communicate with disk. Generally the unknown status is shows because the current node is not the storage pool owner. Do a get-clustergroup to get the owners (the owners of the long GUIDS).</pre>."

			$PdHealthyTest.properties = "friendlyname","uniqueID","canpool","operationalStatus","healthstatus","Size (TB)","SerialNumber","PhysicalLocation"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'Check for unhealthy physical disks`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'Check for unhealthy physical disks`'`n$_"
		
		$PdHealthyTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	####################################
	# Check for retired Physical Disks #
	####################################
	try
	{
		$PdRetiredTest = New-TestObj -test_name "Retired Physical Disks" -outputObj "`$RetiredPds"

		#variable to hold the unhealthy physicaldisks found
		$RetiredPds=@()

		$PDiskData | % {if ($_.usage -eq "retired") 
		    {
		        $PdRetiredTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $RetiredPds += $_
		    }
		}
		if($PdRetiredTest.result -ne "Pass")
		{
			$PdRetiredTest.comment = "<pre>This test checks across all storage attached nodes for disks Where `'Usage`' is equal to `'retired`'. <br>Below is a description of what different disk states mean<br>Note the reporting node as a disk can be reported as different states from different nodes.

OPERATIONALSTATUS	DESCRIPTION
OK:			No rebuild jobs running on this disk. Disk is operational
Lost Communication:	Could not communicate with disk
InService:		Rebuild job is currently running. Get-storagejob will show current rebuilds in the current storage pool
Degraded:		Drives in the virtual disk have failed or been removed and it is running in a degraded state
Starting:		Disk is attempting to start. If it is in this state for a long period – more than 5 minutes there could be an issue.

HEALTHSTATUS	DESCRIPTION
Healthy:	Disk is Healthy
Unhealthy:	Disk Is Unhealthy. Could happen if a drive fails and there is not spare to take over.
Unknown:	Cannot communicate with disk. Generally the unknown status is shows because the current node is not the storage pool owner. Do a get-clustergroup to get the owners (the owners of the long GUIDS).
Warning:	There is a warning on the disk – This state will happen while the disk is ‘inService’ meaning a storage rebuild job is running. 

USAGE		DESCRIPTION
AutoSelect:	Disk that is playing an active role in the storage space
HotSpare:	Standby drive ready to take over when another drive fails
ManualSelect:	Disk may be in use, but it is set to not change usage automatically. Our ISCSI disks are generally manualSelect
Retired:	Disk is not currently in use. A disk will get marked retired sometimes during failure, but can also happen if a disk is removed and re-added
Unknown:	Cannot communicate with disk. Generally the unknown status is shows because the current node is not the storage pool owner. Do a get-clustergroup to get the owners (the owners of the long GUIDS).</pre>."
			
			$PdRetiredTest.properties = "friendlyname","uniqueID","Usage","canpool","operationalStatus","healthstatus","Size (TB)","SerialNumber","PhysicalLocation"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'Check for retired physical disks`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'Check for retired physical disks`'`n$_"
		
		$PdRetiredTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}
	
	#########################################
	# Check for Disks with canpool -eq true #
	#########################################
	try
	{
		$CanPoolTrueTest = New-TestObj -test_name "Physical Disk canpool Status" -outputObj "`$canpoolDisks"

		#variable to hold the canpool disks
		$canpoolDisks=@()

		$PDiskData | % {if ($_.canpool -eq $true) 
		    {
		        $CanPoolTrueTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $canpoolDisks += $_
		    }
		}
		
		if ($CanPoolTrueTest.result -ne "Pass")
		{
			$CanPoolTrueTest.comment = "All physical disks in PDW should have canpool = false because they should all already be participating in a storage pool. 
If canpool is true, the disk was likely physically added, but never added back to the storage pool.

You can add disks to the storage pool automatically using the ADU tool `'Add_Canpool_Disks_to_SP`'.

This is an online operation.
"
			$CanPoolTrueTest.properties = "friendlyname","uniqueID","canpool","operationalStatus","healthstatus"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'disks with canpool -eq true`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'disks with canpool -eq true`'`n$_"
		
		$CanPoolTrueTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	######################################
	# Check for unhealthy Virtual Disks  #
	######################################
	try
	{
		$VdHealthyTest = New-TestObj -test_name "Healthy Virtual Disks" -outputObject "`$unhealthyVds"

		#variable to hold the unhealthy physicaldisks found
		$unhealthyVds=@()
		
		$VDiskData | % {if ($_.operationalStatus -eq "InService")
			{
				$VdHealthyTest.result = "Warning"
				if ($OverallTest.result -ne "Fail")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $unhealthyVds += $_				
			}
		}
		
		$VDiskData | % {if (($_.healthstatus -ne "healthy") -and ($_.operationalStatus -ne "InService")) 
		    {
				$VdHealthyTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $unhealthyVds += $_
		    }
		}
		if ($VdHealthyTest.result -ne "Pass")
		{
			$VdHealthyTest.comment = "An unhealthy virtual disk is marked as unhealthy likely because one of the physical disks that participates in the Vdisk is unhealthy.<br>An operationalStatus of `'InService`' indicates that there is currently a rebuild running on this virtual disk. This is normally if a disk was recently added to the array.<br>"
			$VdHealthyTest.properties = "friendlyname","operationalStatus","healthstatus","Physical Disks (UniqueID's)"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'unhealthy virtual disks`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'unhealthy virtual disks`'`n$_"
		
		$VdHealthyTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	##########################
	# Check CSV's are online #
	##########################
	try
	{
		$CsvOnlineTest = New-TestObj -test_name "CSVs online" -outputObject "`$OfflineCsvs"

		#variable to hold the unhealthy physicaldisks found
		$OfflineCsvs=@()

		$CsvData | % {if ($_.state -ne "Online") 
		    {
		        $CsvOnlineTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $OfflineCsvs += $_
		    }
		}
		if ($CsvOnlineTest.result -ne "Pass")
		{
			$CsvOnlineTest.comment = "CSVs below are not in the online state<br>"
			$CsvOnlineTest.properties = "Name","State","OwnerNode"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'CSV`'s online`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'CSV`'s online`'`n$_"
		
		$CsvOnlineTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	################################
	# Check CSV owners are aligned #
	################################
	try
	{
		$CsvAlignedTest = New-TestObj -test_name "CSV Owners Aligned" -outputObject "`$misAlignedCsvs"

		#variable to hold the unhealthy physicaldisks found
		$misAlignedCsvs=@()

		#if digit 1 and 2 of name are not equal to the last two of ownernode they are misalinged
		$CsvData | % {if ($_.name.substring(1,2) -ne $_.ownernode.name.substring($_.ownernode.name.length-2,2)) 
		    {
		        $CsvAlignedTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $misAlignedCsvs += $_
		    }
		}
		if ($CsvAlignedTest.result -ne "pass")
		{
			$CsvAlignedTest.comment = "CSV's below are not owned by the correct nodes. This can cause a significant performance impact. Use the option in ADU to check and align these CSVs. This is an online operation.<br>"
			$CsvAlignedTest.properties = "Name","State","OwnerNode"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'CSV`'s aligned`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'CSV`'s aligned`'`n$_"
		
		$CsvAlignedTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	#####################################
	# Check for unhealthy Storage Pools #
	#####################################
	try
	{
		$SpHealthyTest = New-TestObj -test_name "Healthy Storage Pools" -outputObject "`$unhealthySps"

		#variable to hold the unhealthy storage pools found
		$unhealthySps=@()

		$spdata | % {if ($_.healthStatus -ne "Healthy" -or $_.OperationalStatus -ne "OK") 
		    {
		        $SpHealthyTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $unhealthySps += $_
		    }
		}
		if ($SpHealthyTest.result -ne "Pass")
		{
			$SpHealthyTest.comment = "Unhealthy storage pools found listed below. A storage pool in the unhealthy state is 
			generally an indicator that a virtual disk or physical disk in that storage pool is also unhealthy.<br>"
			$SpHealthyTest.properties = "Friendlyname","OperationalStatus","HealthStatus"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'unhealthy SP`'s`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'unhealthy SP`'s`'`n$_"
		
		$SpHealthyTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	#######################
	# Check num PDs in VD #
	#######################
	try
	{
		$NumPdsInVdTest = New-TestObj -test_name "2 PDs in all VDs" -outputObject "`$VdsWrongNumPds"

		#variable to hold the unhealthy storage pools found
		$VdsWrongNumPds=@()

        foreach ($vdisk in $VDiskData)
        {
            ##########################
            ## START Bug WORKAROUND ##
            ##########################
            #this is to work around a reporting bug in storage spaces where after a disk replacement
            #a virtual disk may show that it has 0 physical disks
            if ($vdisk.PD_Count -eq 0) 
            {
                if ($tblvpDiskData -eq $null) {
                    
                    write-host "`nFound 1 or more virtual disk reporting 0 physical disks - loading virtual-disk / physical-disk data for work-around" -ForegroundColor DarkYellow
                    Write-Host "This may happen due to a reporting bug in storage spaces, usually after a disk replacement." -ForegroundColor DarkYellow

                    $tblvpDiskData = @{}

                    $disklist = Get-PhysicalDisk | ? {$_.PhysicalLocation -like "SES Enclosure*"} | sort FriendlyName

                    foreach($pdisk in $disklist)
		              {
                        $vdiskname = ($pdisk | Get-VirtualDisk | select FriendlyName).FriendlyName
		                $pdiskname =  ($pdisk | select FriendlyName).FriendlyName + " UID=" + ($pdisk | select uniqueId).uniqueId
                        $tblvpDiskData.add($pdiskname, $vdiskname)
  		              }

                  }

                Write-host -foregroundcolor Yellow "`nFound virtual disk $($vdisk.friendlyname) reporting 0 physical disks."
                
                $diskcount=0

                $pDisksinvDisk =  $tblvpDiskData.GetEnumerator() | ?{$_.Value -eq $vdisk.friendlyname}
                $diskcount = $pDisksinvDisk.Count
                if ($diskcount -gt 0)
                  {
                    Write-Host "Found Physical Disks:" -ForegroundColor Yellow
                    $pDisksinvDisk.GetEnumerator().name
                  }

                if ($diskcount -eq 2)
                {
                    $bugWorkaroundWorked=$true
                    Write-host -Foregroundcolor Green "Workaround correctly detected $diskcount disks in virtual disk $($vdisk.name)
No issues to report on in test results."
                }
                else
                {
                    $bugWorkaroundWorked=$false
                    Write-host -Foregroundcolor Red "Workaround detected $diskcount disks in virtual disk $($vdisk.name). 
Adding to test results"
                }
            }
            ########################
            ## End Bug WORKAROUND ##
            ########################

            if ($vdisk.PD_Count -ne 2 -and !$bugWorkaroundWorked) 
		    {
		        $NumPdsInVdTest.result = "Fail"
				$OverallTest.result = "Fail"
                $vdisk.PD_Count = $diskcount
		        $VdsWrongNumPds += $vdisk
		    }
		}


	<#	$VDiskData | % {if ($_.PD_Count -ne 2) 
		    {
		        $NumPdsInVdTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $VdsWrongNumPds += $_
		    }
		}#>
		if ($VdsWrongNumPds.result -ne "Pass")
		{
			$NumPdsInVdTest.comment = "Each Virtual disk should have two and only two physical disks in it. The Virtual disks below do not have exactly two physical disks in them.
It is normal after a disk failure to see 3 disks in a virtual disk. This is because you have 1 healthy disk, 1 failed disk, and 1 hot spare in the virtual disk
If the test below shows '0', this is likely a bug in storage space reporting that causes the virtual disk to not show any physical disks. This is a reporting issue
only and does not affect functionality. This does not need to be addressed, but will eventually come back - likely after a reboot of the physical node.<br>"
			$NumPdsInVdTest.properties = "FriendlyName","OperationalStatus","Healthstatus","PD_Count"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'Num PD`'s in VD'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'Num PD`'s in VD`'`n$_"
		
		$NumPdsInVdTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	#################################
	# Check PD Reliability Counters #
	#################################
	try
	{
		$PdRelCountersTest = New-TestObj -test_name "PD Reliabilty Counters" -outputObject "`$BadPdCounters"

		#variable to hold the unhealthy physicaldisks found
		$BadPdCounters=@()

		#warning if first because the second test will supercede it and mark failed if they both fail
		$PDiskData | % {if (($_.Reliability.ReadLatencyMax -gt 100000) -or ($_.Reliability.writeLatencyMax -gt 100000)) 
		    {
		        $PdRelCountersTest.result = "Warning"
		        if ($OverallTest.result -ne "Fail")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $BadPdCounters += $_
			}
		}
		$PDiskData | % {if (($_.Reliability.ReadErrorsUncorrected -gt 0) -or ($_.Reliability.writeErrorsUncorrected -gt 0)) 
		    {
		        $PdRelCountersTest.result = "Warning"
		        if ($OverallTest.result -ne "Fail")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $BadPdCounters += $_
		    }
		}
		
		if($PdRelCountersTest.result -ne "Pass")
		{
			$PdRelCountersTest.comment = "<pre>This test checks the values of the counters below and confirms they are within accepted limits. 
A WARNING IS NOT DEFINITIVE OF AN ISSUE as read and write latency vary depending on workload and Uncorrected read/write errors 
may take place from time to time. 
				
ReadErrorsUncorrected & WriteErrorsUncorrected
For these two tests, we will throw a warning if there are any, but what you really want to watch for is if these numbers are rapidly increasing
as that could be an indication of a hardware issue. The recommendation is to watch these counters over time and if they do not increase
in a significant way (at least in the thousands) and you are not seeing performance issues, then there is no action necessary. 

ReadLatencyMax & WriteLatencyMax
These counters vary depending on workload, but generally when there is an issue then all disks will have a very low latency, then one will have
latency in the hundreds of thousands. That could be an indication of a hardware issue. 

COUNTER			ACCEPTED VALUE		RESULT
ReadErrorsUncorrected	0			Warn on greater than 0
WriteErrorsUncorrected	0			Warn on greater than 0
ReadLatencyMax		< 100000			Warn for greater than 100000
WriteLatencyMax		< 100000			Warn for greater than 100000</pre>"

			$PdRelCountersTest.properties = "friendlyname","uniqueID",@{Expression={$(($_ | get-virtualdisk).friendlyname)};Label="Vdisk"},"usage","canpool","operationalStatus","healthstatus","Size (TB)","SerialNumber","PhysicalLocation",@{Expression={$_.reliability.ReadErrorsUncorrected};Label="ReadErrorsUncorrected"},@{Expression={$_.reliability.ReadlatencyMax};Label="ReadlatencyMax"},@{Expression={$_.reliability.WriteErrorsUncorrected};Label="WriteErrorsUncorrected"},@{Expression={$_.reliability.WriteLatencyMax};Label="WriteLatencyMax"}
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'PD Reliability Counters'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'PD Reliability Counters`'`n$_"
		
		$PdRelCountersTest.result = "Failed_Execution"
		$OverallTest.result = "Fail"
	}

	############################
	# Start the XML formatting #
	############################
	Write-host "Formatting Output..."
	
	#Get the domain name for the main heading in the output
	Try{$fabReg = GetFabRegionName}
	catch
	{
		Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Error -message "Error retrieving the fabric domain name from the applainceFabric.xml - continuing anyway" 
		Write-Error -ErrorAction Continue "Error retrieving the fabric domain name from the applainceFabric.xml - continuing anyway" 
	}
	
	#Build the summary table
	$TestSummary=@()
	$TestSummary += $PdHealthyTest
	$TestSummary += $PdRetiredTest
	$TestSummary += $VdHealthyTest
	$TestSummary += $SpHealthyTest
	$TestSummary += $CSVOnlineTest
	$TestSummary += $CsvAlignedTest
	$TestSummary += $CanPoolTrueTest
	$TestSummary += $NumPdsInVdTest
	$TestSummary += $PdRelCountersTest

	#Empty body to hold the html fragments
	$body=@()

	#Defining the style
	$head = @"
	    <style>
	    BODY{background-color:AliceBlue;}
	    TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
	    TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:DarkCyan}
	    TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:Lavender}
	    </style>
"@

	#build the body of the HTML
	$body += "<h2>______________________________________________________</h2>"
	if($OverallTest.result -eq "Pass")
	{
	$body += "<h2>Overall Storage Test result: <font color=Green>Pass</font></h2>"
	}
	elseif ($OverallTest.result -eq "Warning")
	{
	$body += "<h2>Overall Storage Test result: <font color=FF6600>Warning</font></h2>"
	}
	else
	{
	$body += "<h2>Overall Storage Test result: <font color=red>Fail</font></h2>"
	}

	$body += $TestSummary | select-object Test_name,Result | ConvertTo-Html -Fragment 
	$body += "<h2>______________________________________________________</h2>"
	$body += "<br>"


	#Check each test for each of teh 3 states possible
	foreach($test in $TestSummary)
	{
		if ($test.result -eq "Warning")
		{
			$body += "<h3>$($test.Test_Name): <font color=FF6600>Warning</font></h3>"
			$body += "$($test.comment)"
			$body += "<br>"
			$body += invoke-expression ($($test.outputObject)) | select-object $($test.properties) | ConvertTo-Html -Fragment 
		}
		elseif ($test.result -eq "Fail")
		{
			$body += "<h3>$($test.Test_Name): <font color=Red>Fail</font></h3>"
			$body += "$($test.comment)"
			$body += "<br>"
			$body += invoke-expression ($($test.outputObject)) | select-object $($test.properties) | ConvertTo-Html -Fragment 
		}
		elseif ($test.result -eq "Failed_execution")
		{
			$body += "<h3>$($test.Test_Name): <font color=Red>Failed_Execution</font></h3>"
			$body += "This Test Failed to execute. Errors can be found in the PowerShell window and in the ADU event log in Event Viewer."
			$body += "<br>"
		}
	}

	#create the output Dir
	mkdir "D:\PdwDiagnostics\StorageReport\" -Force | out-null

	#create the XML
	$timestamp = get-date -Format yyyyMMddHHmmss
	ConvertTo-Html -head $head -PostContent $body -body "<H1> Storage Subsystem Health Report $toolVersion</H1><H2>Appliance: $fabReg<br>Date: $timestamp</H2>" | out-file "D:\PdwDiagnostics\StorageReport\StorageReport$timestamp.htm"

	#open the XML
	invoke-expression "D:\PdwDiagnostics\StorageReport\StorageReport$timestamp.htm"
	Write-Host "Output file saved to D:\PdwDiagnostics\StorageReport\StorageReport$timestamp.htm"
}

####################################
# function to create a test object #
####################################
Function New-TestObj
{
	param ($test_name=$null,$result="Pass",$comment=$null,$properties=$null,$outputObject=$null)
	
	$testobj = New-Object PSObject
	
	$testobj | add-member -type NoteProperty -Name "Test_Name" -value "$test_name"
	$testobj | add-member -type NoteProperty -Name "Result" -Value "$result"
	$testobj | add-member -type NoteProperty -Name "Comment" -Value "$comment"
	$testobj | add-member -type NoteProperty -Name "properties" -Value $properties
	$testobj | add-member -type NoteProperty -Name "outputObject" -Value "$outputObject"
	
	return $testObj
}

. storageHealthCheck