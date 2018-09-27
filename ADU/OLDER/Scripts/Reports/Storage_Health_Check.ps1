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
#* to include PSComputerName
#*=============================================
. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire"
$source = $MyInvocation.MyCommand.Name #Set Source to scriptname
New-EventLog -Source $source -LogName ADU -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Starting $source" 

function StorageHealthCheck
{
	#Get the list of storage pool owners to invoke the commands on
	$SpOwnersArray=@()
	[string[]]$SpOwnersArray = ((Get-ClusterGroup | ? {$_.groupType -eq "ClusterStoragePool"}).ownernode).name
	[String[]]$PhysNodelist = GetNodeList -fqdn -phys

	#Add FQDN to the SP Owners nodelist
	$SpOwnersArray = $SpOwnersArray | % {$_ + "." + $($PhysNodelist[0].split(".")[1]) + ".fab.local"}

	$HsaNodeList = GetNodeList -FQDN -HSA

	##################################
	# Collect raw physical disk data #
	##################################
	Write-host "`nCollecting raw physical disk data from all storage attached Nodes..."
	try
	{
		$PdiskCommand = {        
		        $disklist = get-physicaldisk | ? {($_ | get-storagepool).friendlyname -like "*StoragePool*" -and $_.model -notlike "Virtual HD*"}
		        $counters = $disklist | Get-StorageReliabilityCounter

		        $disklist = $disklist | 
		        select-object PsComputerName,@{Expression={(($_ | Get-StoragePool)[0]).FriendlyName};Label="Storage Pool"},
		        @{Expression={($_ | Get-VirtualDisk).FriendlyName};Label="Vdisk"},
		        Friendlyname,UniqueID,ObjectId,CanPool,DeviceId,FirmwareVersion,operationalStatus,healthstatus,usage,SerialNumber,PhysicalLocation,
		        @{label="Size (TB)";Expression={$a= $_.size/1024/1024/1024/1024;"{0:N2}" -f $a}} 
				

				foreach($disk in $disklist)
				{
				    $disk | add-member -MemberType NoteProperty -name ReadErrorsUncorrected -Value $(($counters | ? {$_.DeviceId -eq $disk.DeviceId}).ReadErrorsUncorrected)
				    $disk | add-member -MemberType NoteProperty -name ReadLatencyMax -Value $(($counters | ? {$_.DeviceId -eq $disk.DeviceId}).ReadLatencyMax)
				    $disk | add-member -MemberType NoteProperty -name writeErrorsUncorrected -Value $(($counters | ? {$_.DeviceId -eq $disk.DeviceId}).writeErrorsUncorrected)
				    $disk | add-member -MemberType NoteProperty -name writeLatencyMax -Value $(($counters | ? {$_.DeviceId -eq $disk.DeviceId}).writeLatencyMax)
				}
		        return $disklist 
		    }
		$PDiskData=@()
		#$PDiskData += ExecuteParallelDistributedPowerShell2 -command $PdiskCommand -nodelist $SpOwnersArray
		$PDiskData += ExecuteParallelDistributedPowerShell2 -command $PdiskCommand -nodelist $HsaNodeList

		#order the raw disk data
		$PDiskData = $PDiskData | Sort-Object "Storage Pool",Usage,Vdisk
		
		if (!$PDiskData)
		{
			Throw "RAW PHYSICAL DISK DATA WAS NULL!!!"
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error collecting Physical Disk data accross appliance`n$_" -Source $source -logname "ADU" -EventID 9999
		Throw "Error Collecting Physical disk data accross the appliance... Exiting`n$_"
	}

	########################
	# Collect raw CSV data #
	########################
	try
	{
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
		Write-host "`nCollecting raw virtual disk data from all storage attached nodes..."
		$vdiskCmd = {
		        get-virtualdisk | ? {$_.OperationalStatus -ne "Detached"}|
		        select-object Friendlyname,@{Expression={($_ | Get-physicaldisk).UniqueID};Label="Physical Disks (UniqueID's)"},@{Label="PD_Count";Expression={($_ | get-physicaldisk).count}},
		        ObjectId,OperationalStatus,HealthStatus
		    }
		$VDiskData=@()
		$VDiskData += ExecuteParallelDistributedPowerShell2 -command $vdiskCmd -nodelist $HsaNodeList

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
		Write-Host "`nCollecting raw Storage Pool Data from all storage pool owners..."
		$spCmd = {
				Get-StoragePool | ? {$_.FriendlyName -ne "Primordial"} | 
				Select-Object Friendlyname,OperationalStatus,HealthStatus
			}
		$SPData = @()
		$SPData += ExecuteParallelDistributedPowerShell2 -command $spCmd -nodelist $SpOwnersArray

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

	Write-host "Running tests..."

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

			$PdHealthyTest.properties = @{Expression={(($_.PSComputerName).split("."))[0]};Label="Reporting Node"},"friendlyname","uniqueID","canpool","operationalStatus","healthstatus","Size (TB)","SerialNumber","PhysicalLocation"
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
			$PdRetiredTest.comment = "<pre>This test checks accross all storage attached nodes for disks Where `'Usage`' is not equal to `'retired`'. <br>Below is a description of what different disk states mean<br>Note the reporting node as a disk can be reported as different states from different nodes.

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
			
			$PdRetiredTest.properties = @{Expression={(($_.PSComputerName).split("."))[0]};Label="Reporting Node"},"friendlyname","uniqueID","Usage","canpool","operationalStatus","healthstatus","Size (TB)","SerialNumber","PhysicalLocation"
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
			$CanPoolTrueTest.comment = "All physical disks in PDW should have canpool = false because they should all already be participating in a storage pool. <br>If canpool is true, the disk was likely physically added, but never added back to the storage pool.<br>"
			$CanPoolTrueTest.properties = @{Expression={(($_.PSComputerName).split("."))[0]};Label="Reporting Node"},"friendlyname","uniqueID","canpool","operationalStatus","healthstatus"
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
			$VdHealthyTest.properties = "friendlyname","operationalStatus","healthstatus","Physical Disks (UniqueIDs)"
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
			$CsvAlignedTest.comment = "CSV's below are not owned by the correct nodes. This will cause a significant performance impact. Use the option in ADU to check and align these CSVs. This is an online operation.<br>"
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
			$SpHealthyTest.comment = "Unhealthy storage pools found listed below<br>"
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

		$VDiskData | % {if ($_.PD_Count -ne 2) 
		    {
		        $NumPdsInVdTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $VdsWrongNumPds += $_
		    }
		}
		if ($VdsWrongNumPds.result -ne "Pass")
		{
			$NumPdsInVdTest.comment = "Each Virtual disk should have two and only two physical disks in it. The Virtual disks below do not have exactly two physical disks in them.<br>This will need to be addressed by a support engineer<br>"
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
		$PDiskData | % {if (($_.ReadLatencyMax -gt 50000) -or ($_.writeLatencyMax -gt 50000)) 
		    {
		        $PdRelCountersTest.result = "Warning"
		        if ($OverallTest.result -ne "Fail")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $BadPdCounters += $_
			}
		}
		$PDiskData | % {if (($_.ReadErrorsUncorrected -gt 0) -or ($_.writeErrorsUncorrected -gt 0)) 
		    {
		        $PdRelCountersTest.result = "Fail"
				$OverallTest.result = "Fail"
		        $BadPdCounters += $_
		    }
		}
		
		if($PdRelCountersTest.result -ne "Pass")
		{
			$PdRelCountersTest.comment = "<pre>This test checks the values of the counters below and confirms they are within accepted limits. <br>A failure indicates a problem was found and a warning indicates that there could be an issue. A warning is not definitive as read and write latency vary depending on workload. <br>High latency or uncorrected errors could indicate a hardware issue. 

COUNTER			ACCEPTED VALUE		RESULT
ReadErrorsUncorrected	0			Fail on greater than 0
WriteErrorsUncorrected	0			Fail on greater than 0
ReadLatencyMax		< 1000			Warn for greater than 50000
WriteLatencyMax		< 1000			Warn for greater than 50000</pre>"

			$PdRelCountersTest.properties = @{Expression={(($_.PSComputerName).split("."))[0]};Label="Reporting Node"},"friendlyname","uniqueID","Vdisk","usage","canpool","operationalStatus","healthstatus","Size (TB)","SerialNumber","PhysicalLocation","ReadErrorsUncorrected","ReadlatencyMax","WriteErrorsUncorrected","WriteLatencyMax"
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
	Try{$fabDomain = GetFabDomainNameFromXML}
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
	mkdir "C:\PDWDiagnostics\StorageReport\" -Force | out-null

	#create the XML
	$timestamp = get-date -Format MMddyy-hhmmss
	ConvertTo-Html -head $head -PostContent $body -body "<H1> Storage Subsystem Health Report</H1><H2>Appliance: $fabdomain<br>Date: $timestamp</H2>" | out-file "C:\PDWDiagnostics\StorageReport\StorageReport$timestamp.htm"

	#open the XML
	invoke-expression "C:\PDWDiagnostics\StorageReport\StorageReport$timestamp.htm"
	Write-Host "Output file saved to C:\PDWDiagnostics\StorageReport\StorageReport$timestamp.htm"
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