param($username=$null,$password=$null)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1


<# To add a new test:
    1. Add the function for the new test
    2. Add the function call to the spart between comments in the main Wellnesscheck function
    3. Add the output to the 
#>

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged


Function WellnessCheck
{
    #set some variables
    $OutputDir = "D:\PDWDiagnostics\WellnessCheck" #directory for output

    #create the directory for output if it doesn't exist already
    CreateOutputDir $OutputDir 

    #create an object for the overall test result (gets marked as failed if anything fails)
	$OverallTest = New-Object system.object
	$OverallTest | add-member -type NoteProperty -Name "Test Name" -value "Overall Wellness Test"
	$OverallTest | add-member -type NoteProperty -Name "Result" -Value "Pass"


###########################################################################
###########################################################################
<#
TO ADD A NEW TEST:
    1. Add the new test as a function below
    2. Insert the name of the test in the test list
    3. Add the execution of the test to the switch statement
    4. Add the results variable to the outputReport statement
#>
    #create a test list
    #do not use any special characters in test names
    [String[]]$FullTestList = (
        "Run_PAV",
        "Analyze_PAV_Results",
        "Active_Alerts",
        "PDW_Password_Expiry",
        "C_Drive_Free_Space",
        "D_Drive_Free_Space",
        "WMI_Health",
        "Replicated_Table_Sizes",
        "Statistics_Accuracy",
        "CCI_Health",
        "Unhealthy_Physical_Disks",
        "Retired_Physical_Disks",
        "Disks_with_Canpool_True",
        "Unhealthy_Virtual_Disks",
        "CSVs_Online",
        "CSVs_Aligned",
        "Unhealthy_Storage_Pools",
        "Number_PDs_in_VD",
        "PD_Reliability_Counters",
        "Orphaned_Tables",
        "Data_Skew",
        "Network_Adapter_Profile",
        "Time_Sync_Config",
        "Nullable_Dist_Columns"
        )

    [String[]]$FullTestListNoSpaces = $FullTestList.Replace(" ","") 


    #output the form and collect the results
    $userInput = outputForm $FullTestList
    $username = $userinput.Username
    $password =$userinput.password
    $TestsToRun = $userinput.checkedTestList
    #$TestsToRun = outputForm $FullTestList

    #Check if storage tests will be ran - if so run storage collection
    if ($TestsToRun -contains "Unhealthy_Physical_Disks" -or
        $TestsToRun -contains "Retired_Physical_Disks" -or
        $TestsToRun -contains "Disks_with_Canpool_True" -or
        $TestsToRun -contains "Unhealthy_Virtual_Disks" -or
        $TestsToRun -contains "CSVs_Online" -or
        $TestsToRun -contains "CSVs_Aligned" -or
        $TestsToRun -contains "Unhealthy_Storage_Pools" -or
        $TestsToRun -contains "Number_PDs_in_VD" -or
        $TestsToRun -contains "PD_Reliability_Counters") 
        {
            #Collect raw data for the storage tests. These need to be run if you are running any storage tests below
            $RawPdData = CollectRawPhysicalDiskData
            $RawSpData = CollectRawStoragePoolData
            $rawCsvData = CollectRawCSVData
            $rawVdData = CollectRawVirtualDiskData
        }

    #Run the tests
    Foreach ($test in $TestsToRun)
    {
        Switch ($test)
        {
            "Run_PAV"{if (!$username) {$username = GetPdwUserName}
                     if (!$password) {$password = GetPdwPassword}
                     RunPAV -username $username -password $password}
            "Analyze_PAV_Results" {$PAVResults = PAVTest}
            "Active_Alerts" {$ActiveAlertsResults = ActiveAlerts -username $username -password $password}
            "PDW_Password_Expiry" {$PdwUsersNearExpiryResults = PdwPasswordTest}
            "C_Drive_Free_Space" {$CFreeSpaceResults = CFreeSpace}
            "D_Drive_Free_Space" {$DFreeSpaceResults = DFreeSpace}
            "WMI_Health" {$WmiResults = WmiTest}
            "Replicated_Table_Sizes" {$replicatedTableSizeResults = ReplicatedTableSizeTest $username,$password}
            "Statistics_Accuracy" {$statsAccuracyResults = StatsAccuracyTest $username,$password}
            "CCI_Health" {$CciHealthResults = CciHealthTest $username,$password}
            "Unhealthy_Physical_Disks" {$UnhealthyPhysicalDisksResults = UnhealthyPhysicalDisks $RawPdData}
            "Retired_Physical_Disks" { $RetiredPDResults = RetiredPhysicalDisksTest $RawPdData}
            "Disks_with_Canpool_True" {$CanpoolTrueResults = DisksWithCanpoolTrueTest $RawPdData}
            "Unhealthy_Virtual_Disks" {$UnhealthyVirtualDisksResults = UnhealthyVirtualDisksTest $rawVdData}
            "CSVs_Online" {$CsvsOnlineResults = CsvsOnlineTest $rawCsvData}
            "CSVs_Aligned" {$CsvAlignedResults = CsvsAlignedTest $rawCsvData}
            "Unhealthy_Storage_Pools" {$UnhealthySpResults = UnhealthyStoragePoolsTest $RawSpData}
            "Number_PDs_in_VD" {$numPdsInVdResults = NumPdsInVdTest $rawVdData}
            "PD_Reliability_Counters" {$PDReliabilityCountersResults = PdReliabilityCountersTest $RawPdData}
            "Orphaned_Tables" {$OrphanedTableTestResults = OrphanedTableTest $username,$password}
            "Data_Skew" {$DataSkewTestResults = DataSkewTest $username,$password}
            "Network_Adapter_Profile" {$NetworkAdapterProfileResults = NetworkAdapterProfileTest}
            "Time_Sync_Config" {$TimeSyncConfigTestResults = TimeSyncConfigTest}
            "Nullable_Dist_Columns" {$NullableDistColResults = NullableDistColTest}
        }
    }

    #Output and save the HTML report to the outputDir above
    OutputReport $PAVResults,
                $ActiveAlertsResults,
                $PdwUsersNearExpiryResults,
                $DiskAlignmentResults,
                $WmiResults,
                $CFreeSpaceResults,
                $DFreeSpaceResults,
                $UnhealthyPhysicalDisksResults,
                $RetiredPDResults,
                $CanpoolTrueResults,
                $UnhealthyVirtualDisksResults,
                $CsvsOnlineResults,
                $CsvAlignedResults,
                $UnhealthySpResults,
                $numPdsInVdResults,
                $PDReliabilityCountersResults,
                $OrphanedTableTestResults,
                $replicatedTableSizeResults,
                $DataSkewTestResults,
                $statsAccuracyResults,
                $CciHealthResults,
                $NetworkAdapterProfileResults,
                $TimeSyncConfigTestResults,
                $NullableDistColResults
}

###########################################################################
#Start Functions
###########################################################################

Function ActiveAlerts
{
    param($username=$null,$password=$null)
    ####################################################################
    <#
    Name: Active Alerts Test
    Purpose: Fails if there are any currently active alerts

    Future: Warning if only non-critical alerts
    #>
    ####################################################################
    #param($username=$null,$password=$null)
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning Active Alerts Check"

	    $ActiveAlertsTest = New-TestObj -test_name "Active Alerts"

	    #variable to hold the activeAlerts found
	    $ActiveAlerts=@()
        
        #get the PDW Domain Name for querying PDW
        $pdwDomainName = GetPdwRegionName

        #Set username and password if they weren't passed in
        if(!$username){$username = GetPdwUsername}
        if(!$password){$password = GetPdwPassword}

        #Check the PDW creds
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

        #Set the query to retrieve alerts
        $ActiveAlertsQuery = "
        --Query to collect active alerts
        SELECT 
	        pn.[name] as [Node Name],
	        pn.[region] as [Region],
	        pchaa.[component_instance_id] as [Component ID],
	        hcg.[group_name] as [Group],
	        phc.[component_name] as [Component],
	        pchaa.[current_value] as [Status],
	        pchaa.[create_time] as [Create Time],
	        pha.[alert_name] as [Alert]
        FROM [sys].[dm_pdw_component_health_active_alerts] pchaa
        JOIN [sys].[dm_pdw_nodes] pn
	        ON pn.[pdw_node_id] = pchaa.[pdw_node_id]
        JOIN [sys].[pdw_health_alerts] pha
	        ON pha.[alert_id] = pchaa.[alert_id]
        JOIN [sys].[pdw_health_components] AS phc
           ON pchaa.[component_id] = phc.[component_id]
        JOIN [sys].[pdw_health_component_groups] AS hcg
           ON phc.[group_id] = hcg.[group_id]
        ORDER BY 
	        pn.name,
	        pchaa.component_instance_id
        "

        #Run the query 
        LoadSqlPowerShell
        $activeAlerts = Invoke-Sqlcmd -QueryTimeout 0 -ServerInstance "$PdwDomainName-ctl01,17001" -query $ActiveAlertsQuery

        #work with resutls
	    if ($activeAlerts) 
		    {
		        $ActiveAlertsTest.result = "FAILED"
			    $OverallTest.result = "FAILED"
		    }
	    

        #If the test didn't pass, populate some data for output
	    if ($ActiveAlertsTest.result -ne "Pass")
	    {
		    $ActiveAlertsTest.comment = "Below is a list of all of the currently active alerts in PDW. These alerts can also be found through DMV's or through the admin console. Some of these alerts may also trigger other tests to fail.<br>"
		    $ActiveAlertsTest.properties = "Node Name","Region","Component ID","Group","Component","Status","Create Time","Alert"
            $ActiveAlertsTest.outputObject = $ActiveAlerts
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Active Alerts`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Active Alerts`'`n$_"
		
	    $ActiveAlertsTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $ActiveAlertsTest
}

Function CFreeSpace
{
    ####################################################################
    <#
    Name: Free Space CHeck
    Purpose: warns if over 75% used, fail if over 90%

    Future: Warning if only non-critical alerts
    #>
    ####################################################################
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning C Drive Free Space Check"

	    $CFreeSpaceTest = New-TestObj -test_name "C Drive Free Space"

	    #variable to hold the bad free space Nodes
	    $FreeSpaceProblemNodes=@()


        
        $nodelist = getNodeList -Full -fqdn

        $FreeSpaceCommand = {
            $drive = get-psdrive C
    
            [int]$PercentUsed = $drive.used / ($drive.used+$drive.free)*100
            $percentUsed
            }

        Foreach ($node in $nodelist)
        {
            Write-host "$node"
            $PercentUsedResult = invoke-command -ComputerName $node -ScriptBlock $FreeSpaceCommand
            if ($PercentUsedResult -gt 75)
            {
                if ($PercentUsedResult -gt 90)
                {
                    $CFreeSpaceTest.result = "FAILED"
			        $OverallTest.result = "FAILED"
                }
                Else
                {
                    if ($CFreeSpaceTest.result -ne "FAILED")
                    {
                        $CFreeSpaceTest.result = "Warning"
                    }
                    if ($OverallTest.result -ne "FAILED")
                    {
			            $OverallTest.result = "Warning"
                    }
                }
                $problemNode = New-Object -TypeName PSOBJECT
                $problemNode | Add-Member -MemberType NoteProperty -name "Node" -value $node
                $problemNode | Add-Member -MemberType NoteProperty -name "PercentUsed" -value $PercentUsedResult
                
                $FreeSpaceProblemNodes += $problemNode
            }
        }
	    

        #If the test didn't pass, populate some data for output
	    if ($CFreeSpaceTest.result -ne "Pass")
	    {
		    $CFreeSpaceTest.comment = "<pre>This test will Warn if the C drive more than 75% utilized and Fail if it is over 90% utilized
The C drive filling up is usually becuase of extra files placed by the user or diagnostic files that were created while troubleshooting an issue. 
If the server runs out of space on the c drive it will no longer function properly.
You should investigate what is taking up space and try to free it up so that it is less than 75% utilized. <br></pre>"
		    $CFreeSpaceTest.properties = "Node","PercentUsed"
            $CFreeSpaceTest.outputObject = $FreeSpaceProblemNodes
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'C Drive Free Space Check`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'C Drive Free Space Check`'`nMake sure all nodes are online`n$_"
		
	    $CFreeSpaceTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $CFreeSpaceTest
}

Function DFreeSpace
{
    ####################################################################
    <#
    Name: Free Space CHeck
    Purpose: warns if over 75% used, fail if over 90%

    Future: Warning if only non-critical alerts
    #>
    ####################################################################
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning D drive Free Space Check"

	    $DFreeSpaceTest = New-TestObj -test_name " D drive Free Space"

	    #variable to hold the bad free space Nodes
	    $FreeSpaceProblemNodes=@()


        
        $nodelist = getNodeList -Full -fqdn

        $FreeSpaceCommand = {
        If (test-path "D:\"){

            $drive = get-psdrive D
    
            [int]$PercentUsed = $drive.used / ($drive.used+$drive.free)*100
            $percentUsed
            }
            }

        Foreach ($node in $nodelist)
        {
            Write-host "$node"
            $PercentUsedResult = invoke-command -ComputerName $node -ScriptBlock $FreeSpaceCommand
            if ($PercentUsedResult -gt 75)
            {
                if ($PercentUsedResult -gt 90)
                {
                    $DFreeSpaceTest.result = "FAILED"
			        $OverallTest.result = "FAILED"
                }
                Else
                {
                    if ($DFreeSpaceTest.result -ne "FAILED")
                    {
                        $DFreeSpaceTest.result = "Warning"
                    }
                    if ($OverallTest.result -ne "FAILED")
                    {
			            $OverallTest.result = "Warning"
                    }
                }
                $problemNode = New-Object -TypeName PSOBJECT
                $problemNode | Add-Member -MemberType NoteProperty -name "Node" -value $node
                $problemNode | Add-Member -MemberType NoteProperty -name "PercentUsed" -value $PercentUsedResult
                
                $FreeSpaceProblemNodes += $problemNode
            }
        }
	    

        #If the test didn't pass, populate some data for output
	    if ($DFreeSpaceTest.result -ne "Pass")
	    {
		    $DFreeSpaceTest.comment = "<pre>This test will Warn if the D drive more than 75% utilized and Fail if it is over 90% utilized
The D drive filling up is usually becuase of extra files placed by the user or diagnostic files that were created while troubleshooting an issue. 
If the server runs out of space on the D drive it may no longer function properly.
You should investigate what is taking up space and try to free it up so that it is less than 75% utilized. <br></pre>"
		    $DFreeSpaceTest.properties = "Node","PercentUsed"
            $DFreeSpaceTest.outputObject = $FreeSpaceProblemNodes
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'D Drive Free Space Check`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'D Drive Free Space Check`'`nMake sure all nodes are online`n$_"
		
	    $DFreeSpaceTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $DFreeSpaceTest
}

function CollectRawPhysicalDiskData
{
    Write-host -foregroundcolor Cyan "Collecting Raw Storage data for testing"

	#Get the list of storage pool owners to invoke the commands on
	$SpOwnersArray=@()
	[string[]]$SpOwnersArray = ((Get-ClusterGroup | ? {$_.groupType -eq "ClusterStoragePool"}).ownernode).name
	[String[]]$PhysNodelist = GetNodeList -fqdn -phys

	#Add FQDN to the SP Owners nodelist
	#$SpOwnersArray = $SpOwnersArray | % {$_ + "." + $($PhysNodelist[0].split(".")[1]) + ".local"}
    $SpOwnersArray = $SpOwnersArray | % {$_ + $physNodeList[0].Replace($PhysNodelist[1].split(".")[0],"")}

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
		$PDiskData += ExecuteDistributedPowerShell -command $PdiskCommand -nodelist $HsaNodeList

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
    Return $PDiskData
}

Function CollectRawCSVData
{
	########################
	# Collect raw CSV data #
	########################
	#Get the list of storage pool owners to invoke the commands on
	$SpOwnersArray=@()
	[string[]]$SpOwnersArray = ((Get-ClusterGroup | ? {$_.groupType -eq "ClusterStoragePool"}).ownernode).name
	[String[]]$PhysNodelist = GetNodeList -fqdn -phys

	#Add FQDN to the SP Owners nodelist
	#$SpOwnersArray = $SpOwnersArray | % {$_ + "." + $($PhysNodelist[0].split(".")[1]) + ".local"}
    $SpOwnersArray = $SpOwnersArray | % {$_ + $physNodeList[0].Replace($PhysNodelist[1].split(".")[0],"")}

	$HsaNodeList = GetNodeList -FQDN -HSA	

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

    Return $CsvData
}

Function CollectRawVirtualDiskData
{
	#Get the list of storage pool owners to invoke the commands on
	$SpOwnersArray=@()
	[string[]]$SpOwnersArray = ((Get-ClusterGroup | ? {$_.groupType -eq "ClusterStoragePool"}).ownernode).name
	[String[]]$PhysNodelist = GetNodeList -fqdn -phys

	#Add FQDN to the SP Owners nodelist
	#$SpOwnersArray = $SpOwnersArray | % {$_ + "." + $($PhysNodelist[0].split(".")[1]) + ".local"}
    $SpOwnersArray = $SpOwnersArray | % {$_ + $physNodeList[0].Replace($PhysNodelist[1].split(".")[0],"")}

	$HsaNodeList = GetNodeList -FQDN -HSA

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
		$VDiskData += ExecuteDistributedPowerShell -command $vdiskCmd -nodelist $HsaNodeList

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

    return $VDiskData
}

Function CollectRawStoragePoolData
{
	#Get the list of storage pool owners to invoke the commands on
	$SpOwnersArray=@()
	[string[]]$SpOwnersArray = ((Get-ClusterGroup | ? {$_.groupType -eq "ClusterStoragePool"}).ownernode).name
	[String[]]$PhysNodelist = GetNodeList -fqdn -phys

	#Add FQDN to the SP Owners nodelist
	#$SpOwnersArray = $SpOwnersArray | % {$_ + "." + $($PhysNodelist[0].split(".")[1]) + ".local"}
    $SpOwnersArray = $SpOwnersArray | % {$_ + $physNodeList[0].Replace($PhysNodelist[1].split(".")[0],"")}

	$HsaNodeList = GetNodeList -FQDN -HSA

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
		$SPData += ExecuteDistributedPowerShell -command $spCmd -nodelist $SpOwnersArray
		
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

    Return $SPData
}

Function UnhealthyPhysicalDisks
{
    param($pdiskData)
    Write-host -ForegroundColor Cyan "`nRunning unhealthy Physical Disk check"
	######################################
	# Check for unhealthy Physical Disks #
	######################################
	try
	{
		$PdHealthyTest = New-TestObj -test_name "Healthy Physical Disks"

		#variable to hold the unhealthy physicaldisks found
		$unhealthyPds=@()

		$PDiskData | % {if ($_.healthstatus -ne "healthy" -or $_.OperationalStatus -ne "OK") 
		    {
		        $PdHealthyTest.result = "FAILED"
				$OverallTest.result = "FAILED"
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
            $PdHealthyTest.outputObject = $unhealthyPds
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'Check for unhealthy physical disks`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'Check for unhealthy physical disks`'`n$_"
		
		$PdHealthyTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    Return $PdHealthyTest
}

Function RetiredPhysicalDisksTest
{
	param($pdiskData)
    Write-host -ForegroundColor Cyan "`nRunning Retired Physical Disk check"
    ####################################
	# Check for retired Physical Disks #
	####################################
	try
	{
		$PdRetiredTest = New-TestObj -test_name "Retired Physical Disks" 

		#variable to hold the unhealthy physicaldisks found
		$RetiredPds=@()

		$PDiskData | % {if ($_.usage -eq "retired") 
		    {
		        $PdRetiredTest.result = "FAILED"
				$OverallTest.result = "FAILED"
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
            $PdRetiredTest.outputObject = $RetiredPds
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'Check for retired physical disks`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'Check for retired physical disks`'`n$_"
		
		$PdRetiredTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    
    return $PdRetiredTest
}

Function DisksWithCanpoolTrueTest
{	
    param($pdiskData)
    Write-host -ForegroundColor Cyan "`nRunning Canpool Disk check"
	#########################################
	# Check for Disks with canpool -eq true #
	#########################################
	try
	{
		$CanPoolTrueTest = New-TestObj -test_name "Physical Disk canpool Status"

		#variable to hold the canpool disks
		$canpoolDisks=@()

		$PDiskData | % {if ($_.canpool -eq $true) 
		    {
		        $CanPoolTrueTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $canpoolDisks += $_
		    }
		}
		
		if ($CanPoolTrueTest.result -ne "Pass")
		{
			$CanPoolTrueTest.comment = "All physical disks in PDW should have canpool set to false because they should all already be participating in a storage pool. <br>If canpool is true, the disk was likely physically added, but never added back to the storage pool. This should be addressed by adding the disk to the storage pool as a hot spare and confirming that all virtual disks have 2 healthy disks in them.<br>"
			$CanPoolTrueTest.properties = @{Expression={(($_.PSComputerName).split("."))[0]};Label="Reporting Node"},"friendlyname","uniqueID","canpool","operationalStatus","healthstatus"
            $CanPoolTrueTest.outputObject = $canpoolDisks
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'disks with canpool -eq true`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'disks with canpool -eq true`'`n$_"
		
		$CanPoolTrueTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}

    Return $CanPoolTrueTest
}

Function UnhealthyVirtualDisksTest
{
    param($VDiskData)
    Write-host -ForegroundColor Cyan "`nRunning unhealthy virtual disk check"
	######################################
	# Check for unhealthy Virtual Disks  #
	######################################
	try
	{
		$VdHealthyTest = New-TestObj -test_name "Healthy Virtual Disks"

		#variable to hold the unhealthy physicaldisks found
		$unhealthyVds=@()
		
		$VDiskData | % {if ($_.operationalStatus -eq "InService")
			{
				$VdHealthyTest.result = "Warning"
				if ($OverallTest.result -ne "FAILED")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $unhealthyVds += $_				
			}
		}
		
		$VDiskData | % {if (($_.healthstatus -ne "healthy") -and ($_.operationalStatus -ne "InService")) 
		    {
				$VdHealthyTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $unhealthyVds += $_
		    }
		}
		if ($VdHealthyTest.result -ne "Pass")
		{
			$VdHealthyTest.comment = "An unhealthy virtual disk is marked as unhealthy likely because one of the physical disks that participates in the Vdisk is unhealthy.<br>An operationalStatus of `'InService`' indicates that there is currently a rebuild running on this virtual disk. This is normally if a disk was recently added to the array. An unhealthy virtual disk should be investgated because if there is only one healthy drive then the loss of the healthy drive could cause data loss. However, if a hot spare has taken over and the failed disk is still in the virtual disk, then the virtual disk may be marked as unehalthy, but the data is still redundant on the two healhty disks.<br>"
			$VdHealthyTest.properties = "friendlyname","operationalStatus","healthstatus"
            $VdHealthyTest.outputObject = $unhealthyVds
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'unhealthy virtual disks`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'unhealthy virtual disks`'`n$_"
		
		$VdHealthyTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}

    Return $VdHealthyTest
}

Function CsvsOnlineTest
{
    param($CsvData)

    Write-host -ForegroundColor Cyan "`nRunning CSV Online Check"
	##########################
	# Check CSV's are online #
	##########################
	try
	{
		$CsvOnlineTest = New-TestObj -test_name "CSVs online"

		#variable to hold the unhealthy physicaldisks found
		$OfflineCsvs=@()

		$CsvData | % {if ($_.state -ne "Online") 
		    {
		        $CsvOnlineTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $OfflineCsvs += $_
		    }
		}
		if ($CsvOnlineTest.result -ne "Pass")
		{
			$CsvOnlineTest.comment = "CSVs below are not in the online state. In order to have access to all of your data, all CSV's need to be online. You can bring CSV's online in failover cluter administrator. If there is an error bringing it online then it should be investigated.<br>"
			$CsvOnlineTest.properties = "Name","State","OwnerNode"
            $CsvOnlineTest.outputObject = $OfflineCsvs
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'CSV`'s online`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'CSV`'s online`'`n$_"
		
		$CsvOnlineTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}

    Return $CsvOnlineTest
}

Function CsvsAlignedTest
{
    param($CsvData)

    Write-host -ForegroundColor Cyan "`nRunning CSV Aligned Check"
	################################
	# Check CSV owners are aligned #
	################################
	try
	{
		$CsvAlignedTest = New-TestObj -test_name "CSV Owners Aligned"

		#variable to hold the unhealthy physicaldisks found
		$misAlignedCsvs=@()

		#if digit 1 and 2 of name are not equal to the last two of ownernode they are misalinged
		$CsvData | % {if ($_.name.substring(1,2) -ne $_.ownernode.name.substring($_.ownernode.name.length-2,2)) 
		    {
		        $CsvAlignedTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $misAlignedCsvs += $_
		    }
		}
		if ($CsvAlignedTest.result -ne "pass")
		{
			$CsvAlignedTest.comment =  "The below misaligned disks were found. These are disks that are not owned by the proper HSA node. The disk should be owned by the HSA node specified by the N## part of the CSV name below.
Misalignment may happen as part of a failure of a component of an HSA node or could be the remnants of a previous failover or maintenance window. If a single node owns more disks than another, it could cause performance issues. To realign these disks you can run ADU Disk Alignemnt, or align them manually in failover cluster manager<br>"
			$CsvAlignedTest.properties = "Name","State","OwnerNode"
            $CsvAlignedTest.outputObject = $misAlignedCsvs
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'CSV`'s aligned`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'CSV`'s aligned`'`n$_"
		
		$CsvAlignedTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    Return $CsvAlignedTest
}

Function UnhealthyStoragePoolsTest
{
    param($spdata)

    Write-host -ForegroundColor Cyan "`nRunning unhealthy storage pool check"
	#####################################
	# Check for unhealthy Storage Pools #
	#####################################
	try
	{
		$SpHealthyTest = New-TestObj -test_name "Healthy Storage Pools"

		#variable to hold the unhealthy storage pools found
		$unhealthySps=@()

		$spdata | % {if ($_.healthStatus -ne "Healthy" -or $_.OperationalStatus -ne "OK") 
		    {
		        $SpHealthyTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $unhealthySps += $_
		    }
		}
		if ($SpHealthyTest.result -ne "Pass")
		{
			$SpHealthyTest.comment = "The storage pools listed below are marked unhealthy. Usually storage pools are marked unhealhty because a physical disk or virtual disk in the storage pool is unhealhty.<br>"
			$SpHealthyTest.properties = "Friendlyname","OperationalStatus","HealthStatus"
            $SpHealthyTest.outputObject = $unhealthySps
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'unhealthy SP`'s`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'unhealthy SP`'s`'`n$_"
		
		$SpHealthyTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    return $SpHealthyTest
}

Function NumPdsInVdTest
{
    param($VDiskData)

    Write-host -ForegroundColor Cyan "`nRunning # PDs in VDs check"
	#######################
	# Check num PDs in VD #
	#######################
	try
	{
		$NumPdsInVdTest = New-TestObj -test_name "2 Disks in all Virtual disks"

		#variable to hold the unhealthy storage pools found
		$VdsWrongNumPds=@()

		$VDiskData | % {if ($_.PD_Count -ne 2) 
		    {
		        $NumPdsInVdTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $VdsWrongNumPds += $_
		    }
		}
		if ($VdsWrongNumPds.result -ne "Pass")
		{
			$NumPdsInVdTest.comment = "Each Virtual disk should have two and only two physical disks in it. The Virtual disks below do not have exactly two physical disks in them.<br>This will need to be addressed by a support engineer<br>"
			$NumPdsInVdTest.properties = "FriendlyName","OperationalStatus","Healthstatus","PD_Count"
            $NumPdsInVdTest.outputObject = $VdsWrongNumPds
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'Num PD`'s in VD'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'Num PD`'s in VD`'`n$_"
		
		$NumPdsInVdTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    return $NumPdsInVdTest
}

Function PdReliabilityCountersTest
{
    param($PDiskData)

    Write-host -ForegroundColor Cyan "`nRunning PD Reliability Counters Check"
	#################################
	# Check PD Reliability Counters #
	#################################
	try
	{
		$PdRelCountersTest = New-TestObj -test_name "PD Reliabilty Counters"

		#variable to hold the unhealthy physicaldisks found
		$BadPdCounters=@()

		#warning if first because the second test will supercede it and mark failed if they both fail
		$PDiskData | % {if (($_.ReadLatencyMax -gt 50000) -or ($_.writeLatencyMax -gt 50000)) 
		    {
		        $PdRelCountersTest.result = "Warning"
		        if ($OverallTest.result -ne "FAILED")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $BadPdCounters += $_
			}
		}
		$PDiskData | % {if (($_.ReadErrorsUncorrected -gt 100) -or ($_.writeErrorsUncorrected -gt 100)) 
		    {
		        $PdRelCountersTest.result = "Warning"
				if ($OverallTest.result -ne "FAILED")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $BadPdCounters += $_
		    }
		}
		
		if($PdRelCountersTest.result -ne "Pass")
		{
			$PdRelCountersTest.comment = "<pre>This test checks the values of the counters below and confirms they are within accepted limits. <br>A failure indicates a problem was found and a warning indicates that there could be an issue. A warning is not definitive as read and write latency vary depending on workload. <br>High latency or uncorrected errors could indicate a hardware issue. 

Sometimes these counters may be increased by transient errors. This is not a concern as long as the counters are not continuously increasing. 

COUNTER			ACCEPTED VALUE		RESULT
ReadErrorsUncorrected	100			Warn on greater than 100
WriteErrorsUncorrected	100			Warn on greater than 100
ReadLatencyMax		< 5000			Warn for greater than 50000
WriteLatencyMax		< 5000			Warn for greater than 50000</pre>"

			$PdRelCountersTest.properties = @{Expression={(($_.PSComputerName).split("."))[0]};Label="Reporting Node"},"friendlyname","uniqueID","Vdisk","usage","canpool","operationalStatus","healthstatus","Size (TB)","SerialNumber","PhysicalLocation","ReadErrorsUncorrected","ReadlatencyMax","WriteErrorsUncorrected","WriteLatencyMax"
            $PdRelCountersTest.outputObject = $BadPdCounters
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'PD Reliability Counters'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'PD Reliability Counters`'`n$_"
		
		$PdRelCountersTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    Return $PdRelCountersTest
}

Function PdwPasswordTest
{
    Write-host -ForegroundColor Cyan "`nRunning PDW Password Expiry Check"
	############################################################
	# Check for expired or near expiry passwords in PDW region #
	############################################################
	try
	{
		$PdwPasswordTest = New-TestObj -test_name "PDW user passwords near Expiry"

		$nearExpiryUsers=@() #variable to hold the bad users found
        $accountList=@() #hold all the accounts

        $nodelist = GetNodeList -Full -fqdn
        $AD01Node = $nodelist | select-string "AD01"


        $command = {Get-ADUser -filter {Enabled -eq $True} –Properties “SamAccountName”,"PasswordExpired","PasswordNeverExpires", “msDS-UserPasswordExpiryTimeComputed” | `
Select-Object -Property “SamAccountName”,"PasswordExpired","PasswordNeverExpires", @{Name=“ExpiryDate”;Expression={[datetime]::FromFileTime($_.“msDS-UserPasswordExpiryTimeComputed”)}}}
        
        $accountList = Invoke-Command -ComputerName $AD01Node -ScriptBlock $command

        
        Foreach ($account in $accountList)
        {
            #check if account is expired
            if ($account.PasswordExpired -eq "true")
            {
                $PdwPasswordTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $nearExpiryUsers += $account
            }

            #check if account expires in the next 7 days
            if ($account.ExpiryDate -gt ((get-date).addDays(-7)) -lt (get-date) -and $_.expiryDate)
            {
                if ($PdwPasswordTest.result -ne "FAILED")
                {
                    $PdwPasswordTest.result = "Warning"
                }
				if ($OverallTest.result -ne "FAILED")
		        {
				    $OverallTest.result = "Warning"
		        }
		        $nearExpiryUsers += $account
            }

            #check if account never expires
            if ($account.PasswordNeverExpires -eq "true")
            {
                $PdwPasswordTest.result = "FAILED"
				$OverallTest.result = "FAILED"
		        $nearExpiryUsers += $account
            }

        }
		
		if($PdwPasswordTest.result -ne "Pass")
		{
			$PdwPasswordTest.comment = "The following list contains PDW users whose password is expired or near expiry. This test fails if accounts are expired or if user accounts are set to never expire. It will warn if accounts expire in the next 7 days.
It is important for security reasons that passwords are changed regularly."

			$PdwPasswordTest.properties ="SamAccountName","PasswordExpired","ExpiryDate","PasswordNeverExpires"
            $PdwPasswordTest.outputObject = $nearExpiryUsers
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'Check for near expiry PDW users`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'Check for near expiry PDW users`'`n$_"
		
		$PdwPasswordTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    Return $PdwPasswordTest
}

Function RunPAV
{
    param($username=$null,$password=$null)
        Write-host -Foregroundcolor Cyan "Running PAV - this will probably take about 15 minutes"
        $aduPs1Path = Split-path $rootPath -Parent

        if ($username -and $password)
        {
            PowerShell $aduPs1Path\Adu.ps1 -run_pav -username $username -password $password
        }
        else
        {
            PowerShell $aduPs1Path\Adu.ps1 -run_pav 
        }
        #PowerShell c:\adu\adu.ps1 -run_pav
        #start WINRM
        $PDWDomainName = GetPdwRegionName;Get-Service -Name winrm  -ComputerName "$PDWDomainName-CTL01" | Start-service

}

Function PAVTest
{
    Write-host -ForegroundColor Cyan "`nRunning PAV Results Check"
	############################
	# Check latest PAV results #
	############################
	try
	{
		$PAVTest = New-TestObj -test_name "PDW Appliance Validator"

		$FailedTestList=@() 
#testlist
#Sanity
#Ping
#nodeReachable
#DiskSpd
#General Verification

        $PDWDomainName = GetPdwRegionName
        #Find the most recent PAV log
        $PavLogLocation = (gci "\\$PDWDomainName-CTL01\C`$\ProgramData\Microsoft\Microsoft SQL Server PDW Appliance Validator\Logs\" -Directory| Sort-Object CreationTime -Descending)[0].FullName

        #check each log file
        if (Test-Path $PavLogLocation\VerificationResult.log)
        {
            #build the failure string
            $content = Get-Content $PavLogLocation\VerificationResult.log | select-string "Failed" #| select-string -NotMatch "_______","Run","Mode","Date_Time"
            foreach ($line in $content)
            {
                #$line.tostring().Substring(0,100)
                $NodeName = $line.tostring().Substring(25,17)
                $Test = $line.tostring().Substring(42,49)
                $SubTest = $line.tostring().Substring(104,299)
                $Error = $line.tostring().Substring(403)

                $TestFailure = New-Object -TypeName PSOBJECT
                $TestFailure | Add-Member -MemberType NoteProperty -name "Server" -value $NodeName
                $TestFailure | Add-Member -MemberType NoteProperty -name "Test Name" -value $Test
                $TestFailure | Add-Member -MemberType NoteProperty -name "Sub-Test Name" -value $SubTest
                $TestFailure | Add-Member -MemberType NoteProperty -name "Error" -value $Error
                $FailedTestList += $TestFailure
            } 


            $PAVTest.result = "FAILED"
            $OverallTest.result = "FAILED"
            
        }
        else
        {
                $TestFailure = New-Object -TypeName PSOBJECT
                $TestFailure | Add-Member -MemberType NoteProperty -name "Server" -value "CTL01"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Test Name" -value "VerificationResult"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Sub-Test Name" -value "Error Running Test"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Error" -value "FILE NOT FOUND: $PavLogLocation\VerificationResult.log"
                $FailedTestList += $TestFailure
                if($PAVTest.result -ne "FAILED")
                {
		            $PAVTest.result = "WARNING"
                }	
                if($OverallTest.result -ne "FAILED")
                {
		            $OverallTest.result = "WARNING"
                }	
        }

        if (Test-Path $PavLogLocation\SanityResult.log)
        {
        #Check Sanity Test results
        $SanityResult = Get-Content "$PavLogLocation\SanityResult.log"
        if (!($SanityResult | select-string "Sanity Test Status: Passed"))
        {
            Foreach ($line in $sanityResult[4..11] | select-string "failed") # select-string -NotMatch "---------------","_________","Run Number:")
            {
                $Test = $line.tostring().Substring(0,50)
                $Error = $line.tostring().Substring(50)

                $TestFailure = New-Object -TypeName PSOBJECT
                $TestFailure | Add-Member -MemberType NoteProperty -name "Server" -value "CTL01,17001 (PDW)"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Test Name" -value $Test
                $TestFailure | Add-Member -MemberType NoteProperty -name "Error" -value $Error
                $FailedTestList += $TestFailure
            }

                $PAVTest.result = "FAILED"
                $OverallTest.result = "FAILED"
            }
        }
        else
        {
                $TestFailure = New-Object -TypeName PSOBJECT
                $TestFailure | Add-Member -MemberType NoteProperty -name "Server" -value "CTL01"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Test Name" -value "SanityResult"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Sub-Test Name" -value "Error Running Test"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Error" -value "FILE NOT FOUND: $PavLogLocation\SanityResult.log"
                $FailedTestList += $TestFailure
                if($PAVTest.result -ne "FAILED")
                {
		            $PAVTest.result = "WARNING"
                }	
                if($OverallTest.result -ne "FAILED")
                {
		            $OverallTest.result = "WARNING"
                }	
        }

        if (Test-Path $PavLogLocation\PingResult.log)
        {
            #Check Ping Results
            $PingResult = Get-Content "$PavLogLocation\PingResult.log"
            $pingResultNoHeader = $PingResult[5..$($PingResult.Length)]

        Foreach ($line in $pingResultNoHeader)
        {
            If($line | select-string "No")
            {
                $FromIP = $line.tostring().Substring(78,20)
                $ToIP = $line.tostring().Substring(98,20)
                $Server = $line.tostring().Substring(38,40)
                $Network = $line.tostring().Substring(25,13)
                
                $TestFailure = New-Object -TypeName PSOBJECT
                $TestFailure | Add-Member -MemberType NoteProperty -name "Server" -value $Server
                $TestFailure | Add-Member -MemberType NoteProperty -name "Test Name" -value "Ping"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Error" -value "Network: $Network Ping failure from $FromIP to $ToIp"
                $FailedTestList += $TestFailure

                $PAVTest.result = "FAILED"
                $OverallTest.result = "FAILED"
            }


            }
        }
        else
        {
                $TestFailure = New-Object -TypeName PSOBJECT
                $TestFailure | Add-Member -MemberType NoteProperty -name "Server" -value "CTL01"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Test Name" -value "PingResult"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Sub-Test Name" -value "Error Running Test"
                $TestFailure | Add-Member -MemberType NoteProperty -name "Error" -value "FILE NOT FOUND: $PavLogLocation\PingResult.log"
                if($PAVTest.result -ne "FAILED")
                {
		            $PAVTest.result = "WARNING"
                }	
                if($OverallTest.result -ne "FAILED")
                {
		            $OverallTest.result = "WARNING"
                }	
        }
		
		if($PAVTest.result -ne "Pass")
		{
			$PAVTest.comment = "The PDW Appliance Validator (PAV) validates various properties in the appliance are as expected and that the applinace is able to process simple queries. This results below are based off of the most recent run found of PAV.
You can view the more detailed PAV results in the PAV output folder to investigate these issues."
			$PAVTest.properties ="Server","Test Name","Sub-Test Name","Error"
            $PAVTest.outputObject = $FailedTestList
		}
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error running test `'PAVTest`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'PAVTest`'`n$_"
		
		$PAVTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}
    Return $PAVTest
}

Function WmiTest
{
    Try
    {
        Write-host -ForegroundColor Cyan "`nRunning WMI Health Check"
        $WmiTest = New-TestObj -test_name "WMI Process Test"
    
        $outputNodeList=@()
    
        #get list of physical nodes
        try
        {
            $nodelist = getNodeList -phys -fqdn
            #$FabDom = $nodelist.split("-")[0]
        }
        catch
        {
            write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Failed to Generate Nodelist `n`n $_.fullyqualifiedErrorID `n`n $_.exception"
            Write-Error "Failed to retrieve a node list using the get NodeList function"
        }

      
        $CheckWmi = {Get-Process -Name wmiprvse | Where-Object {($_.PrivateMemorySize -gt 350000000) -or ($_.handleCount -gt 4000)} }#| ft Name,@{label="Private Mem(MB)";Expression={[math]::truncate($_.privatememorysize / 1mb)}},Handlecount -AutoSize}    

        Write-Host "`nChecking physical nodes for WMI processes near 500mb or 4096 handles..."
        foreach ($node in $nodelist)
        {
            Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Running CheckWmi command on $node"
	
	        Write-Host -Nonewline $node
            try
            {
                #run the command on the remote node
	            $output = Invoke-Command -ComputerName "$node" -ScriptBlock $CheckWmi
            }
            catch
            {
                write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Failed to run CheckWMI on $node `n`n $_.fullyqualifiedErrorID `n`n $_.exception"
                Write-Warning "`nCheck WMI on $node failed with following message: $_"
            }

	        if($output)
	        {
                $problemNode = New-Object -TypeName PSOBJECT
                $problemNode | Add-Member -MemberType NoteProperty -name "Server Name" -value $node
                $outputNodeList += $problemNode
	            
                write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Warning -Message "Offending process found on $node `n`n $output"
		        Write-Host -ForegroundColor Red -BackgroundColor Black " Offending process found! "
	        }
	        Else{Write-Host -ForegroundColor Green " OK"}
        }
        
        if ($outputNodeList)
        {               
            $WmiTest.result = "FAILED"
		    $OverallTest.result = "FAILED"
        }

        if($WmiTest.result -ne "Pass")
		{
			$WmiTest.comment = "The servers below were found to have offending WMI processes that could cause problems and should be restarted. The restart can be peformed automatically with ADU."
			$WmiTest.properties ="Server Name"
            $WmiTest.outputObject = $outputNodeList
		}
    }
    catch
	{
		Write-EventLog -EntryType Error -message "Error running test `WMI Test`'`n$_" -Source $source -logname "ADU" -EventID 9999
		Write-Error -ErrorAction Continue "Error running test: `'WMI Test`'`n$_"
		
		$WmiTest.result = "Failed_Execution"
		$OverallTest.result = "FAILED"
	}

    Return $WmiTest
}

Function ReplicatedTableSizeTest
{
 ####################################################################
    <#
    Name: Replicated Table Size Test
    Purpose: Fails for tables over 5gb, warns for tables near 5gb
    #>
    ####################################################################
    #param($username=$null,$password=$null)
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning Replicated Table Size Check"

	    $ReplicatedTableSizeTest = New-TestObj -test_name "Replicated Table Sizes"

	    #variable to hold the big tables found
	    $BigRepTables=@()
        $repOver10gb=@()
        
        #get the PDW Domain Name for querying PDW
        $pdwDomainName = GetPdwRegionName

        #Set username and password if they weren't passed in
        if(!$username){$username = GetPdwUsername}
        if(!$password){$password = GetPdwPassword}

        #Check the PDW creds
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

        #get dblist
        $dbQuery = "select name from sys.databases where name not in ('master','tempdb','stagedb','model','msdb','dwqueue','dwdiagnostics','dwconfiguration') order by name asc;"
        $DbList = Invoke-Sqlcmd -queryTimeout 0 -ServerInstance "$pdwDomainName-ctl01,17001" -query $dbQuery
        
        $counter = 1
        $numDatabases = $dbList.count
#DEBUG
#$dblist = $dblist | select -first 3
##########
        foreach ($db in $DbList)
        {
            $dbname = "$($db.name)"
            #write-host "Database: $dbname"
            [int]$percentComplete = $counter/$numDatabases *100
            Write-Progress -Activity "Querying replicated table sizes on all databases, currently on database $counter of $numDatabases : $dbname" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
            $counter++

				$tbls = Invoke-Sqlcmd -QueryTimeout 0 -Query "use $dbname; SELECT '''' + '[' + sc.name + '].[' + ta.name + ']' + '''' as TableName FROM sys.tables ta INNER JOIN sys.partitions pa ON pa.OBJECT_ID = ta.OBJECT_ID INNER JOIN sys.schemas sc ON ta.schema_id = sc.schema_id, sys.pdw_table_mappings b, sys.pdw_table_distribution_properties c WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1,0) and ta.object_id = b.object_id AND b.object_id = c.object_id AND c.distribution_policy = `'3`' GROUP BY sc.name,ta.name ORDER BY SUM(pa.rows) DESC;" -ServerInstance "$pdwDomainName-CTL01,17001" -Username $username -Password $password
						
				foreach($tbl in $tbls) 
					{
						# Varaibles
						$totalDataSpace=0
                        $tableName = $tbl.tableName
                        #write-host $tableName

						# Capture DBCC PDW_SHOWSPACED output
						$results = Invoke-Sqlcmd -QueryTimeout 0 -Query "use $dbname; DBCC PDW_SHOWSPACEUSED ($tableName);" -ServerInstance "$pdwDomainName-CTL01,17001" -Username $username -Password $password 

						#Grab one of the results - it's a replicated table so all nodes should be the same
                        $dataSpace = $results.data_space[0]
						$totalDataGb = ([System.Math]::Round($dataSpace / 1024 /1024,1))

						if($totalDataGb -gt 5)
							{
                                $tbl | Add-Member -NotePropertyName "TableSizeGb" -NotePropertyValue "$totalDataGB GB"
                                $tbl | Add-Member -NotePropertyName "DB Name" -NotePropertyValue "$dbname"
								$BigRepTables += $tbl
							}
                        elseif ($totalDataGb -gt 10)
                            {
                                $tbl | Add-Member -NotePropertyName "TableSizeGb" -NotePropertyValue "$totalDataGB GB"
                                $tbl | Add-Member -NotePropertyName "DB Name" -NotePropertyValue "$dbname"
                                $repOver10gb +=$tbl
                            }
					}
        }

        #work with results
	    if ($repOver10gb) 
		    {
		        #fail  because there's a table over 5gb
                $ReplicatedTableSizeTest.result = "FAILED"
			    $OverallTest.result = "FAILED"
		    }
	    if ($BigRepTables) 
		    {
                #warn if it's 1-5gb
                if($ReplicatedTableSizeTest.result -ne "FAILED")
                {
		            $ReplicatedTableSizeTest.result = "WARNING"
                }	
                if($OverallTest.result -ne "FAILED")
                {
		            $OverallTest.result = "WARNING"
                }		    
		    }

        $BigRepTables += $repOver10gb

        #If the test didn't pass, populate some data for output
	    if ($ReplicatedTableSizeTest.result -ne "Pass")
	    {
		    $ReplicatedTableSizeTest.comment = "Tables listed below are replicated tables that are considered large. The rule of thumb is a table over 5gb should usually be a distributed table, but there are exceptions to this based on your workload. The space shown below is the space used for a single node. In reality the disk space used up is this number multiplied by the number of compute nodes since a replicated table has a full copy of the table on every node.
Tables close to 5gb are also listed below. These tables should be considered, but don't necessarily need to be changed."
		    $ReplicatedTableSizeTest.properties = "DB Name","TableName","TableSizeGB"
            $ReplicatedTableSizeTest.outputObject = $BigRepTables
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Large Replicated Tables`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Large Replicated Tables`'`n$_"
		
	    $ReplicatedTableSizeTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $ReplicatedTableSizeTest
}

Function NullableDistColTest
{
    ####################################################################
    <#
    Name: Nullable Distribution Columns test
    Purpose: Fails if nullable distribution columns are found
    #>
    ####################################################################
    #param($username=$null,$password=$null)
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning Nullable Distribution Column Check"

	    $NullableDistColTest = New-TestObj -test_name "Nullable Distribution Columns"
        
        #get the PDW Domain Name for querying PDW
        $pdwDomainName = GetPdwRegionName

        #Set username and password if they weren't passed in
        if(!$username){$username = GetPdwUsername}
        if(!$password){$password = GetPdwPassword}

        #Check the PDW creds
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

        #variable to hold results
        $NullableDistCols=@()

        #get dblist
        $dbQuery = "select name from sys.databases where name not in ('master','tempdb','stagedb','model','msdb','dwqueue','dwdiagnostics','dwconfiguration') order by name asc;"
        $DbList = Invoke-Sqlcmd -QueryTimeout 0 -ServerInstance "$pdwDomainName-ctl01,17001" -query $dbQuery
        
        $counter = 1
        $numDatabases = $dbList.count
#DEBUG
#$dblist = $dblist | select -first 6
##########
        foreach ($db in $DbList)
        {
            $dbname = "$($db.name)"
            
            [int]$percentComplete = $counter/$numDatabases *100
            Write-Progress -Activity "Querying for nullable distribution columns on all databases, currently on database $counter of $numDatabases : $dbname" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
            $counter++



            #Set the query to retrieve stats accuracy
            $NullableDistColQuery = "use $dbname;
            --This query returns data if nullable distriubtion columns are found in the current database
SELECT  
	s.name AS 'Schema Name',
	t.name AS 'Table Name',
	c.name AS 'Distribution Column',
	c.is_nullable,
	c.object_id
FROM sys.pdw_column_distribution_properties pcdp
JOIN sys.columns c
ON pcdp.[object_id] = c.[object_id]
AND pcdp.column_id = c.column_id
AND pcdp.distribution_ordinal = 1
JOIN sys.tables t
ON c.object_id = t.object_id
JOIN sys.schemas s
ON t.schema_id = s.schema_id
WHERE c.is_nullable = 1
; "

            #Run the query 
            ##LoadSqlPowerShell
            $NullableDistColResults = Invoke-Sqlcmd -ServerInstance "$PdwDomainName-ctl01,17001" -query $NullableDistColQuery -queryTimeout 0

            FOREACH ($result in $NullableDistColResults)
            {
                $result | add-member -NotePropertyName "Database Name" -NotePropertyValue $dbname
                $NullableDistCols += $result
            }
            
        }

        #work with results
	    if ($NullableDistCols) 
		    {
		        $NullableDistColTest.result = "FAILED"
			    $OverallTest.result = "FAILED"
		    }
	    

        #If the test didn't pass, populate some data for output
	    if ($NullableDistColTest.result -ne "Pass")
	    {
		    $NullableDistColTest.comment = "Columns listed below are a distribution column that is set to nullable. As a best practice, distribution columns should always be NOT NULL. If you have NULL values in the distribution column, then they will all be placed in the same distribution creating the possibility of data skew and slow queries. All Tables below should be set to NOT NULL if possible, or you may want to consider a distribution column that can be set to NOT NULL"
		    $NullableDistColTest.properties = "Database Name","Schema Name","Table Name","Distribution Column","is_nullable","object_id" 
            $NullableDistColTest.outputObject = $NullableDistCols
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Nullable Distribution Columns`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Nullable Distribution Columns`'`n$_"
		
	    $NullableDistColTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $NullableDistColTest
}

Function StatsAccuracyTest
{
    ####################################################################
    <#
    Name: Statistics accuracy test
    Purpose: Fails if statistics are off by more than 10%
    #>
    ####################################################################
    #param($username=$null,$password=$null)
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning statistics Accuracy Check"

	    $StatsAccuracyTest = New-TestObj -test_name "Statistics Accuracy"

	    #variable to hold the bad stats found
	    $BadStats=@()
        
        #get the PDW Domain Name for querying PDW
        $pdwDomainName = GetPdwRegionName

        #Set username and password if they weren't passed in
        if(!$username){$username = GetPdwUsername}
        if(!$password){$password = GetPdwPassword}

        #Check the PDW creds
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

        #get dblist
        $dbQuery = "select name from sys.databases where name not in ('master','tempdb','stagedb','model','msdb','dwqueue','dwdiagnostics','dwconfiguration') order by name asc;"
        $DbList = Invoke-Sqlcmd -QueryTimeout 0 -ServerInstance "$pdwDomainName-ctl01,17001" -query $dbQuery
        
        $counter = 1
        $numDatabases = $dbList.count
#DEBUG
#$dblist = $dblist | select -first 5
##########
        foreach ($db in $DbList)
        {
            $dbname = "$($db.name)"
            
            [int]$percentComplete = $counter/$numDatabases *100
            Write-Progress -Activity "Querying stats on all databases, currently on database $counter of $numDatabases : $dbname" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
            $counter++



            #Set the query to retrieve stats accuracy
            $StatsAccuracyQuery = "use $dbname;
            SELECT pdwtbl.name , 
          Sum(part.rows)/ max(pdwpart.partition_number)/8 AS CMP_ROW_COUNT, 
           sum(pdwpart.rows)/max(size.distribution_id)/max(pdwpart.partition_number)/8 AS CTL_ROW_COUNT        
    FROM   sys.pdw_nodes_partitions part 
           JOIN sys.pdw_nodes_tables tbl 
             ON part.object_id = tbl.object_id 
            AND part.pdw_node_id = tbl.pdw_node_id 
                  JOIN sys.pdw_distributions size 
                  on size.pdw_node_id = tbl.pdw_node_id 
           JOIN sys.pdw_table_mappings map 
             ON map.physical_name = tbl.name 
           JOIN sys.tables pdwtbl 
             ON pdwtbl.object_id = map.object_id 
           JOIN sys.partitions pdwpart 
             ON pdwpart.object_id = pdwtbl.object_id 
           join sys.pdw_table_distribution_properties dist 
                  on pdwtbl.object_id = dist.object_id 
    WHERE  dist.distribution_policy <> 3 
    -- uncomment the below if you are looking for row counts for s specific table
    -- this table will also need to be added below
    -- and pdwtbl.name = 'table_name'
    GROUP  BY pdwtbl.name 
	having Sum(part.rows)/ max(pdwpart.partition_number)/8 != sum(pdwpart.rows)/max(size.distribution_id)/max(pdwpart.partition_number)/8
    UNION ALL 
    SELECT pdwtbl.name , 
           Sum(part.rows)/ max(pdwpart.partition_number)/(select count(type) from sys.dm_pdw_nodes where type = 'COMPUTE') AS CMP_ROW_COUNT, 
           sum(pdwpart.rows) /max(pdwpart.partition_number) /(select count(type) from sys.dm_pdw_nodes where type = 'COMPUTE')
              AS CTL_ROW_COUNT 
    FROM   sys.pdw_nodes_partitions part 
           JOIN sys.pdw_nodes_tables tbl 
             ON part.object_id = tbl.object_id 
                AND part.pdw_node_id = tbl.pdw_node_id 
           JOIN sys.pdw_table_mappings map 
             ON map.physical_name = tbl.name 
           JOIN sys.tables pdwtbl 
             ON pdwtbl.object_id = map.object_id 
           JOIN sys.partitions pdwpart 
             ON pdwpart.object_id = pdwtbl.object_id 
                   join sys.pdw_table_distribution_properties dist 
       on pdwtbl.object_id = dist.object_id 
    where dist.distribution_policy = 3 
    -- uncomment the next line if you want row counts for a specific table
    -- and pdwtbl.name = 'table_name'
    GROUP  BY pdwtbl.name 
	HAVING Sum(part.rows)/ max(pdwpart.partition_number)/(select count(type) from sys.dm_pdw_nodes where type = 'COMPUTE') != 
           sum(pdwpart.rows) /max(pdwpart.partition_number) /(select count(type) from sys.dm_pdw_nodes where type = 'COMPUTE')
    order by pdwtbl.name "

            #Run the query 
            ##LoadSqlPowerShell
            $statsResults = Invoke-Sqlcmd -ServerInstance "$PdwDomainName-ctl01,17001" -query $StatsAccuracyQuery -queryTimeout 0

            foreach ($result in $statsResults)
            {
		$diff = [math]::abs($result.CTL_ROW_COUNT - $result.CMP_ROW_COUNT)
		#Write-host $result.name
		#Write-host $result.CTL_ROW_COUNT  $result.CMP_ROW_COUNT
               	if ($result.CTL_ROW_COUNT -eq 0)
                {
                    $result.CTL_ROW_COUNT = $result.CMP_ROW_COUNT
                }
                $percentDiff = ($diff / $result.CTL_ROW_COUNT * 100)
                if ($percentDiff -gt 10)
                {
                    $result | add-member -NotePropertyName "Difference" -NotePropertyValue "$diff"
		            $result | add-member -NotePropertyName "Percent incorrect" -NotePropertyValue "$percentDiff%"
                    $result | add-member -NotePropertyName "Database Name" -NotePropertyValue $dbname
                    $BadStats += $result                   
		}


            }
        }

        #work with results
	    if ($BadStats) 
		    {
		        $StatsAccuracyTest.result = "FAILED"
			$OverallTest.result = "FAILED"
		    }
	    

        #If the test didn't pass, populate some data for output
	    if ($StatsAccuracyTest.result -ne "Pass")
	    {
		    $StatsAccuracyTest.comment = "Stats below are inaacurate by more than 10%. The default statistics value on the control node is 1000, so tables that have that value do not have PDW statistics created."
		    $StatsAccuracyTest.properties = "Database Name","Name","CMP_ROW_COUNT","CTL_ROW_COUNT","Difference","Percent incorrect" 
            	    $StatsAccuracyTest.outputObject = $BadStats
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Statistics Accuracy`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Statistics Accuracy`'`n$_"
		
	    $StatsAccuracyTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $StatsAccuracyTest
}

Function CCIHealthTest
{
    ####################################################################
    <#
    Name: CCI Health test
    Purpose: Fails if statistics are off by more than 10%
    #>
    ####################################################################
    #param($username=$null,$password=$null)
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning CCI HealthCheck"

	    $CciHealthTest = New-TestObj -test_name "CCI Health"

	    #variable to hold the bad CCIs found
	    $BadCCI=@()
        
        #get the PDW Domain Name for querying PDW
        $pdwDomainName = GetPdwRegionName

        #Set username and password if they weren't passed in
        if(!$username){$username = GetPdwUsername}
        if(!$password){$password = GetPdwPassword}

        #Check the PDW creds
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

        #get dblist
        $dbQuery = "select name from sys.databases where name not in ('master','tempdb','stagedb','model','msdb','dwqueue','dwdiagnostics','dwconfiguration') order by name asc;"
        $DbList = Invoke-Sqlcmd -QueryTimeout 0 -ServerInstance "$pdwDomainName-ctl01,17001" -query $dbQuery
        
        $counter = 1
        $numDatabases = $dbList.count
#DEBUG
#$dblist = $dblist | select -first 3
##########
        foreach ($db in $DbList)
        {
            $dbname = "$($db.name)"
            
            [int]$percentComplete = $counter/$numDatabases *100
            Write-Progress -Activity "Querying CCI data for all databases, currently on database $counter of $numDatabases : $dbname" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
            $counter++


            #Set the query to retrieve stats accuracy
            $CCIHealthQuery = "use $dbname;
--CCI Health by table
SELECT               SYSDATETIME()                                                    as 'Collection_Date',
                     DB_Name()                                                        as 'Database_Name',
                     t.name                                                           as 'Table_Name',
tdp.distribution_policy_desc                as 'Distribution_type',
                     SUM(CASE WHEN rg.State = 1 THEN 1 else 0 end)                    as 'OPEN_Row_Groups',
                     SUM(CASE WHEN rg.State = 1 THEN rg.Total_rows else 0 end)        as 'OPEN_rows',
                     MIN(CASE WHEN rg.State = 1 THEN rg.Total_rows else NULL end)     as 'MIN OPEN Row Group Rows',
                     MAX(CASE WHEN rg.State = 1 THEN rg.Total_rows else NULL end)     as 'MAX OPEN_Row Group Rows',
                     AVG(CASE WHEN rg.State = 1 THEN rg.Total_rows else NULL end)     as 'AVG OPEN_Row Group Rows',
 
                     SUM(CASE WHEN rg.State = 3 THEN 1 else 0 end)                    as 'COMPRESSED_Row_Groups',
                     SUM(CASE WHEN rg.State = 3 THEN rg.Total_rows else 0 end)        as 'COMPRESSED_Rows',
               SUM(CASE WHEN rg.State = 3 THEN rg.deleted_rows else 0 end)        as 'Deleted_COMPRESSED_Rows',
               MIN(CASE WHEN rg.State = 3 THEN rg.Total_rows else NULL end)       as 'MIN COMPRESSED Row Group Rows',
                     MAX(CASE WHEN rg.State = 3 THEN rg.Total_rows else NULL end)     as 'MAX COMPRESSED Row Group Rows',
                     AVG(CASE WHEN rg.State = 3 THEN rg.Total_rows else NULL end)     as 'AVG_COMPRESSED_Rows',
 
                     SUM(CASE WHEN rg.State = 2 THEN 1 else 0 end)                    as 'CLOSED_Row_Groups',
                     SUM(CASE WHEN rg.State = 2 THEN rg.Total_rows else 0 end)        as 'CLOSED_Rows',
               MIN(CASE WHEN rg.State = 2 THEN rg.Total_rows else NULL end)       as 'MIN CLOSED Row Group Rows',
                     MAX(CASE WHEN rg.State = 2 THEN rg.Total_rows else NULL end)     as 'MAX CLOSED Row Group Rows',
                     AVG(CASE WHEN rg.State = 2 THEN rg.Total_rows else NULL end)     as 'AVG CLOSED Row Group Rows'
 
FROM          sys.pdw_nodes_column_store_row_groups rg
INNER JOIN    sys.pdw_nodes_tables pt
              ON     rg.object_id = pt.object_id
          AND  rg.pdw_node_id = pt.pdw_node_id
INNER JOIN     sys.pdw_table_mappings mp
              ON     pt.name = mp.physical_name
INNER JOIN    sys.tables t
              ON     mp.object_id = t.object_id
INNER JOIN sys.pdw_table_distribution_properties as tdp
  ON        tdp.object_id = t.object_id
GROUP BY             t.name,tdp.distribution_policy_desc
 

"

            #Run the query 
            #LoadSqlPowerShell
            $CciResults = Invoke-Sqlcmd -QueryTimeout 0 -ServerInstance "$PdwDomainName-ctl01,17001" -query $CCIHealthQuery
	    
            foreach ($result in $CciResults)
            {
		$flagBadCCI = $false
                if ($result.Deleted_COMPRESSED_Rows)
                {
                    $percentDeleted = "{0:P0}" -f ($result.Deleted_compressed_rows/$result.Compressed_rows )
                    $flagBadCCI = $true
                    $result | add-member -NotePropertyName "Percent Deleted" -NotePropertyValue "$percentDeleted"
                    $result | add-member -NotePropertyName "Reason1" -NotePropertyValue "Deleted Rows"
                }
                if ([string]$result.AVG_COMPRESSED_Rows)
                {
                    if ([int]$result.AVG_COMPRESSED_Rows -lt 200000)
                    {
                        $flagBadCCI = $true
                        $result | add-member -NotePropertyName "Reason2" -NotePropertyValue "Small avg Rowgroups"
                    }
                }
                else
                {
                        $flagBadCCI = $true
                        $result | add-member -NotePropertyName "Reason3" -NotePropertyValue "No Compressed rows"
                }
                if ([string]$result.OPEN_Rows)
                {
                    if ([int]$result.OPEN_Rows -gt 0)
                    {
                        $flagBadCCI = $true
                        $result | add-member -NotePropertyName "Reason4" -NotePropertyValue "Rows in OPEN Rowgroups"
                    }
                }
		if($flagBadCCI)
		{
			$BadCCI += $result
		}
               
            }


            #if ($counter -gt 15){break}
        }

        #work with results
	    if ($BadCCI) 
		    {
		        $CciHealthTest.result = "FAILED"
			    $OverallTest.result = "FAILED"
		    }
	    

        #If the test didn't pass, populate some data for output
	    if ($CciHealthTest.result -ne "Pass")
	    {
		    $CciHealthTest.comment = "Below is an analysis of the rowgroup health of clustered columnstore indexes (CCI). You want your average compressed rowgroup size to be as close as possible to 1 million to get optimal compression. If the table is large and the avg rowgroup size is less than 100,000 than that table may not be ideal for Columnstore. 
You do not want any deleted rows in compressed rowgroups. When an DELETE or an UPDATE (which is a delete/insert in CCI), the rows are only logically delete in the compressed rowgroups. They are not physically dropped until the index is rebuilt with ALTER INDEX REBUILD"
		    $CciHealthTest.properties = "Database_Name","Table_Name","Distribution_Type","OPEN_ROWS","AVG_COMPRESSED_Rows","COMPRESSED_Rows","Deleted_COMPRESSED_Rows","Percent Deleted","Reason1","Reason2","Reason3","Reason4"
            $CciHealthTest.outputObject = $BadCCI
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'CCI Health`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'CCI Health`'`n$_"
		
	    $StatsAccuracyTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $CciHealthTest
}

Function OrphanedTableTest
{
 ####################################################################
    <#
    Name: Orphaned Table Test
    Purpose: Fails if it finds tables that exist on nodes with no 
    mapping in PDW
    #>
    ####################################################################
    #param($username=$null,$password=$null)
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning Orphaned Table Check"

	    $OrphanedTableTest = New-TestObj -test_name "Orphaned Tables"

	    #variable to hold the big tables found
        $AllOrphanedTables =@()
        $orphanedTablesToReport=@()	    
        
        #get the PDW Domain Name for querying PDW
        $pdwDomainName = GetPdwRegionName

        #Set username and password if they weren't passed in
        if(!$username){$username = GetPdwUsername}
        if(!$password){$password = GetPdwPassword}

        #Check the PDW creds
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


        #get dblist
        $dbQuery = "select name from sys.databases where name not in ('master','tempdb','stagedb','model','msdb','dwqueue','dwdiagnostics','dwconfiguration') order by name asc;"
        $DbList = Invoke-Sqlcmd -queryTimeout 0 -ServerInstance "$pdwDomainName-ctl01,17001" -query $dbQuery
        
        $counter = 1
        $numDatabases = $dbList.count
#DEBUG
#$dblist = $dblist | select -first 3
##########
        foreach ($db in $DbList)
        {
            $dbname = "$($db.name)"
            
            [int]$percentComplete = $counter/$numDatabases *100
            Write-Progress -Activity "Querying for orphaned tables in all databases, currently on database $counter of $numDatabases : $dbname" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
            $counter++

            $orphanedQuery = "use $dbname;
select ptm.object_id as PDW_OBJECT_ID, ptm.physical_name as PDW_PHYSICAL_NAME, pnt.name as Node_table_name,pnt.object_id as node_object_id,pnt.pdw_node_id,pnt.create_date  from sys.pdw_table_mappings ptm
RIGHT JOIN sys.pdw_nodes_tables pnt
ON ptm.physical_name = pnt.name
WHERE ptm.physical_name IS NULL
order by Node_table_name"

				$AllOrphanedTables = Invoke-Sqlcmd -QueryTimeout 0 -Query $orphanedQuery -ServerInstance "$pdwDomainName-CTL01,17001" -Username $username -Password $password
						
				foreach($tbl in $AllOrphanedTables) 
					{
                        $tbl | Add-Member -NotePropertyName "DB Name" -NotePropertyValue "$dbname"
                        $orphanedTablesToReport += $tbl
					}
        }

        #work with results
	    if ($orphanedTablesToReport) 
		    {
                $OrphanedTableTest.result = "FAILED"
			    $OverallTest.result = "FAILED"
		    }
	  

        #If the test didn't pass, populate some data for output
	    if ($OrphanedTableTest.result -ne "Pass")
	    {
		    $OrphanedTableTest.comment = "Tables in the list below exist on the compute nodes, but have no mapping in PDW. This can happen from a failed drop operation or simliar. These tables shoudl be removed from the compute nodes to free up space. The PDW_OBJECT_ID and PDW_PHYSICAL_ID for orphaned tables should always be blank because these tables are no longer found in PDW metadata."
		    $OrphanedTableTest.properties = "DB Name","PDW_OBJECT_ID","PDW_PHYSICAL_NAME","Node_table_name","Node_object_id","Pdw_node_id","Create_date"
            $OrphanedTableTest.outputObject = $orphanedTablesToReport
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Orphaned Tables`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Orphaned Tables`'`n$_"
		
	    $OrphanedTableTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $OrphanedTableTest
}

Function DataSkewTest
{
    TRY
    {
    try
	{
        Write-host -foregroundcolor Cyan "`nRunning Data Skew Check"

	    $DataSkewTest = New-TestObj -test_name "Data Skew"
        $tableskew = @()

        #get the PDW Domain Name for querying PDW
        $pdwDomainName = GetPdwRegionName
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss


		# Get username and credentials
		
		if(!$username)
		{   $PDWUID = GetPdwUsername; $PDWPWD = GetPdwPassword }
		else
		{   $PDWUID = $username; $PDWPWD = $password }	
	}
    Catch
	{
	    write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
	    Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}


    if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD))
    {
        write-error "failed to validate credentials"
    }

    Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
    LoadSqlPowerShell

    #get dblist
    $dbQuery = "select name from sys.databases where name not in ('master','tempdb','stagedb','model','msdb','dwqueue','dwdiagnostics','dwconfiguration') order by name asc;"
    $DbList = Invoke-Sqlcmd -queryTimeout 0 -ServerInstance "$pdwDomainName-CTL01,17001" -query $dbQuery 
        
    $counter = 1
    $numDatabases = $dbList.count

#DEBUG
#$dblist = $dblist | select -first 3
##########

    foreach ($db in $dblist)
    {
        $dbname = "$($db.name)"
        write-Debug $dbname
            
        [int]$percentComplete = $counter/$numDatabases *100
        Write-Progress -Activity "Querying for Data Skew in all databases, currently on database $counter of $numDatabases : $dbname" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
        $counter++

		try
		{
            $tblsQuery = "use $dbname;
SELECT '[' + sc.name + '].[' + ta.name + ']' as TableName 
FROM sys.tables ta 
join sys.schemas sc 
    on ta.schema_id = sc.schema_id
LEFT OUTER JOIN sys.external_tables et
on ta.object_id = et.object_id
where et.object_id IS NULL;"
                           
			# Collect table details
			$tbls = Invoke-Sqlcmd -QueryTimeout 0 -Query $tblsQuery -ServerInstance "$pdwDomainName-CTL01,17001" -Username $username -Password $password
		}
		catch
		{
			Write-Eventlog -entrytype Error -Message "Failed to collect table details `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
			Write-error "Failed to collect table details... Exiting" -ErrorAction Stop #Writing an error and exit
		}       		
			
		try
			{
				# Create a DataSkewTable
				$tableDataSkew = New-Object system.Data.DataTable "DataSkewTable"
				#$tableDataSkew=@()
                $colDatabaseName = New-Object system.Data.DataColumn databaseName,([string])
				$colTableName = New-Object system.Data.DataColumn tableName,([string])
				$colskewPct = New-Object system.Data.DataColumn skewPct,([decimal])
				$colminValue = New-Object system.Data.DataColumn minValue,([string])
				$colmaxValue = New-Object system.Data.DataColumn maxValue,([string])
				$coltotalRows = New-Object system.Data.DataColumn totalRows,([long])
				$coltotalSpace = New-Object system.Data.DataColumn totalSpace,([decimal])
				$tableDataSkew.columns.add($colDatabaseName)
				$tableDataSkew.columns.add($colTableName)
				$tableDataSkew.columns.add($colskewPct)
				$tableDataSkew.columns.add($colminValue)
				$tableDataSkew.columns.add($colmaxValue)
				$tableDataSkew.columns.add($coltotalRows)
				$tableDataSkew.columns.add($coltotalSpace)
			}
		catch
			{
				Write-Eventlog -entrytype Error -Message "Failed on creating the data skew table `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
				Write-error "Failed on creating the data skew table... Exiting" -ErrorAction Stop #Writing an error and exit
			}			
			
			
		#* Loop through tables
		foreach($tbl in $tbls.TableName) 
		{
			# Varaibles
			[long]$totalDataSpace=0
			[long]$totalRows=0 
			$MaxSize=$null
			$MinSize=$null
			$SkewPct=0
						
			# Add databaseName and tableName to the DataSkewTable
			$row = $tableDataSkew.NewRow()
			$row.databaseName = $dbname
			$row.tableName = $tbl
						
            try
            {
                $results = Invoke-Sqlcmd -querytimeout 0 -Query "use $dbname; DBCC PDW_SHOWSPACEUSED (`"$tbl`");" -ServerInstance "$pdwDomainName-CTL01,17001" -Username $username -Password $password
            }
            catch
            {
                Write-Host "Failed to run DBCC PDW_SHOWSPACEUSED on $tbl" -ForegroundColor Yellow
                Write-Eventlog -entrytype Error -Message "Failed to run DBCC query `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
                Write-error "Failed to run DBCC query... Exiting" -ErrorAction Continue #Writing an error and exit
            }
				

			# Sum totalDataSpace
			$results.data_space |foreach { $totalDataSpace += $_ }
			# Sum totalRows
			$results.rows |foreach { $totalRows += $_ }
			# Find min value
			$results.rows |foreach { if (($_ -lt $MinSize) -or ($MinSize -eq $null)) {$MinSize = $_} }
			# Find max value
			$results.rows |foreach { if (($_ -gt $MaxSize) -or ($MaxSize -eq $null)) {$MaxSize = $_} }
					  
			# Calc skew pct
			# Test for 0 values
			if (($MaxSize -gt 0) -and ($MinSize -ge 0))
			{
				$SkewPct = (($MaxSize - $MinSize) / $totalRows) * 100
			}
				   
					
			# Red if skew pct is greater than 15%
			if ($SkewPct -ge 15)
			{
				$row.skewPct = [System.Math]::Round($SkewPct,2)
				$row.minValue = $MinSize
				$row.maxValue = $MaxSize
				$row.totalRows = $totalRows
				$row.totalSpace = [System.Math]::Round($totalDataSpace / 1024,2)
                
                #$tableDataSkew+=$row        
                $tableDataSkew.Rows.Add($row)
			}

		}         
        $tableskew += $tableDataSkew
	} 
    

        #work with results
	    if ($tableskew) 
	    {
            $DataSkewTest.result = "FAILED"
		    $OverallTest.result = "FAILED"
	    }
	  

        #If the test didn't pass, populate some data for output
	    if ($DataSkewTest.result -ne "Pass")
	    {
		    $DataSkewTest.comment = "Data Skew should be kept under 20%. The larger the table is, the more performance will be impacted."
		    $DataSkewTest.properties = "databasename","tablename","skewPct","minValue","maxValue","totalRows","totalSpace"
            $DataSkewTest.outputObject = $tableskew
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Data Skew`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Data Skew`'`n$_"
		
	    $DataSkewTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $DataSkewTest
}

Function NetworkAdapterProfileTest
{
    ####################################################################
    <#
    Name: Network Adapter profile test
    Purpose: Fails if any network adapters are not on the domain profile

    #>
    ####################################################################
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning Network Adapter Profile Check"

	    $NetworkAdapterProfileTest = New-TestObj -test_name "Network Adapter Profile"

	    #variable to hold the bad free space Nodes
	    $NetworkAdapterProfileProblemNodes=@()


        
        $nodelist = getNodeList -phys -fqdn

        #will return the adapter name if it found one
        $CheckAdaptersFirewallProfiles =  
        {
	        $VmsAdaptersList = get-netadapter | ? {$_.name -like "*VMS*" }#-or (($_ | get-NetConnectionProfile -erroraction SilentlyContinue) -and ($_ | get-NetConnectionProfile).networkcategory -like "Public")}
	        Foreach ($adapter in $VmsAdaptersList)
	        {
		        $profile = $adapter | Get-NetConnectionProfile
		        if (($profile.networkcategory) -ne "DomainAuthenticated")
		        {
                    $adapter.Name
		        }
	        }
        }

        Foreach ($node in $nodelist)
        {
            Write-host "$node"
            $badAdapters = invoke-command -ComputerName $node -ScriptBlock $CheckAdaptersFirewallProfiles
            
            if ($badAdapters)
            {
                $NetworkAdapterProfileTest.result = "FAILED"
			    $OverallTest.result = "FAILED"
            

                $problemNode = New-Object -TypeName PSOBJECT
                $problemNode | Add-Member -MemberType NoteProperty -name "Node" -value $node
                $problemNode | Add-Member -MemberType NoteProperty -name "Count of Problem Adapters" -value $($badAdapters.count)
                
                $NetworkAdapterProfileProblemNodes += $problemNode
            }
        }
	    

        #If the test didn't pass, populate some data for output
	    if ($NetworkAdapterProfileTest.result -ne "Pass")
	    {
		    $NetworkAdapterProfileTest.comment = "<pre>This test checks that all adapters are on the domainAuthenticated Profile. If a node is in the list below, then that 
means it has at least 1 adapter that is not on the DomainAuthenticated profile. This can cause connectivity and 
authentication problems. You can use the online fix in ADU to address this in most instances. <br></pre>"
		    $NetworkAdapterProfileTest.properties = "Node","Count of Problem Adapters"
            $NetworkAdapterProfileTest.outputObject = $NetworkAdapterProfileProblemNodes
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Network Adapter Profile Check`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Network Adapter Profile Check`'`nMake sure all nodes are online`n$_"
		
	    $NetworkAdapterProfileTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $NetworkAdapterProfileTest
}

Function TimeSyncConfigTest
{
    ####################################################################
    <#
    Name: Time sync Configuration test
    Purpose: Fails if appliance is not set to sync to an NTP server

    #>
    ####################################################################
    try
    {
        Write-host -foregroundcolor Cyan "`nRunning Time Sync Configuration Check"

	    $TimeSyncConfigTest = New-TestObj -test_name "Time Sync Config"

	    #variable to hold the bad time sync config Nodes
	    $TimeSyncConfigProblemNodes=@()


        
        $nodelist = getNodeList -full -fqdn

        $queryTimeSourceCmd = {w32tm /query /source}

        Foreach ($node in $nodelist)
        {
            Write-host "$node"
            $timeSource = invoke-command -ComputerName $node -ScriptBlock $queryTimeSourceCmd
            
            #logic to determine if it's set to the right server
            #all servers should point to AD01 or AD02
            #AD01 and AD02 should poitn ot the same NTP server
            
            #check non-AD nodes
            If ($node -notlike "*-AD0*")
            {
                if ($timeSource -notlike "*-AD0*") 
                {
                    $TimeSyncConfigTest.result = "FAILED"
			        $OverallTest.result = "FAILED"

                    $problemNode = New-Object -TypeName PSOBJECT
                    $problemNode | Add-Member -MemberType NoteProperty -name "Node" -value $node
                    $problemNode | Add-Member -MemberType NoteProperty -name "Current Source" -value $timeSource
                    $problemNode | Add-Member -MemberType NoteProperty -name "Expected Source" -value "AD01 or AD02 server"
                
                    $TimeSyncConfigProblemNodes += $problemNode
                }
            }
            Else #Check AD nodes
            {
                if ($timeSource -notlike "*.*.*.*") #for now just setting to the format of an IP address
                {
                    $TimeSyncConfigTest.result = "FAILED"
			        $OverallTest.result = "FAILED"

                    $problemNode = New-Object -TypeName PSOBJECT
                    $problemNode | Add-Member -MemberType NoteProperty -name "Node" -value $node
                    $problemNode | Add-Member -MemberType NoteProperty -name "Current Source" -value $timeSource
                    $problemNode | Add-Member -MemberType NoteProperty -name "Expected Source" -value "IP address of external NTP server"
                
                    $TimeSyncConfigProblemNodes += $problemNode
                }
            }

        }
	    

        #If the test didn't pass, populate some data for output
	    if ($TimeSyncConfigTest.result -ne "Pass")
	    {
		    $TimeSyncConfigTest.comment = "<pre>This test checks that all servers are syncing to the proper time source. Any servers in the list below
are not set to the expected source. AD servers should be set to sync to an external NTP server. All other servers within the appliance should be 
pointing to either of the AD servers. If this configuration is not set, then there is a possibility of accelerated time drift over time due to
circular logic in nodes sycning to each other. You can use ADU to set up a connection to an external NTP server.<br></pre>"
		    $TimeSyncConfigTest.properties = "Node","Current Source","Expected Source"
            $TimeSyncConfigTest.outputObject = $TimeSyncConfigProblemNodes
	    }
    }
    catch
    {
        #Fail the whole test if we were not able to run
	    Write-EventLog -EntryType Error -message "Error running test `'Time Sync Config Check`'`n$_" -Source $source -logname "ADU" -EventID 9999
	    Write-Error -ErrorAction Continue "Error running test: `'Time Sync Config Check`'`nMake sure all nodes are online`n$_"
		
	    $TimeSyncConfigTest.result = "Failed_Execution"
	    $OverallTest.result = "FAILED"
    }

    Return $TimeSyncConfigTest
}


Function OutputReport
{
    ############################
    # Start the XML formatting #
    ############################
    Write-host "`nFormatting Output..."
	
    #Get the Region name for the main heading in the output
    Try{$fabDomain = GetFabRegionName}
    catch
    {
	    Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Error -message "Error retrieving the fabric domain name from the applainceFabric.xml - continuing anyway" 
	    Write-Error -ErrorAction Continue "Error retrieving the fabric domain name from the applainceFabric.xml - continuing anyway" 
    }

    #Build the summary table
    $TestSummary=@()

    $i=0
    while ($args[$i])
    {
        $TestSummary += $args[$i]
        $i++
    }


    #Empty body to hold the html fragments
    $body=@()

#Defining the style
#(this needs to not be indented)
$head = @"
	<style>
	BODY{background-color:White;}
	TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
	TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:DarkCyan}
	TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:Lavender}
	</style>
"@

    #build the body of the HTML
    $body += "<h2>______________________________________________________</h2>"
    if($OverallTest.result -eq "Pass")
    {
    $body += "<h2>Overall Wellness Check result: <font color=Green>Pass</font></h2>"
    }
    elseif ($OverallTest.result -eq "Warning")
    {
    $body += "<h2>Overall Wellness Check result: <font color=FF6600>Warning</font></h2>"
    }
    else
    {
    $body += "<h2>Overall Wellness Check result: <font color=red>FAILED</font></h2>"
    }
    

    $body += $TestSummary | select-object Test_name,Result | ConvertTo-Html -Fragment 
    $body = $body -replace "<td>FAILED</td>","<td style=`"background-color:#ff0000`">FAILED</td>"
        $body = $body -replace "<td>FAILED_EXECUTION</td>","<td style=`"background-color:#ED7014`">FAILED_EXECUTION</td>"
    $body = $body -replace "<td>WARNING</td>","<td style=`"background-color:#ffff00`">WARNING</td>"
    $body = $body -replace "<td>PASS</td>","<td style=`"background-color:GREEN`">PASS</td>"
    $body += "<h2>______________________________________________________</h2>"
    $body += "Below is details for each test that did not pass"
    $body += "<br>"


    #Check each test for each of the 3 failure states possible
    foreach($test in $TestSummary)
    {
	    if ($test.result -eq "Warning")
	    {
                    $body += "<h3>$($test.Test_Name): <font color=#FF6600>WARNING</font></h3>"
		    $body += "$($test.comment)"
		    $body += "<br>"
		    $body += $test.outputObject | select-object $test.properties | ConvertTo-Html -Fragment
            $body += "<h2>______________________________________________________</h2>"
	    }
	    elseif ($test.result -eq "FAILED")
	    {
		    $body += "<h3>$($test.Test_Name): <font color=Red>FAILED</font></h3>"
		    $body += "$($test.comment)"
		    $body += "<br>"
            $body += $test.outputObject | select-object $test.properties | ConvertTo-Html -Fragment 
            $body += "<h2>______________________________________________________</h2>"
	    }
	    elseif ($test.result -eq "Failed_execution")
	    {
		    $body += "<h3>$($test.Test_Name): <font color=Red>Failed_Execution</font></h3>"
		    $body += "This test failed to execute. Errors can be found in the PowerShell window and in the ADU event log in Event Viewer. NOTE: Tests may fail if not all nodes are online."
		    $body += "<br>"
            $body += "<h2>______________________________________________________</h2>"
	    }

        
    }
    
    #Add the Microsoft Services Logo to the bottom of the page 
    #$aduPs1Path = Split-path $rootPath -Parent
    #$body += "<p align=`"left`"><img src=`"$rootPath\images\Microsoft-Services_logo.png`"></p>"
    #insert Microsoft services logo as base64 image
    $body += "<p align=`"left`"><img src=`"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAJgAAAAUCAIAAAD+0mPVAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAA4BpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuNi1jMDE0IDc5LjE1Njc5NywgMjAxNC8wOC8yMC0wOTo1MzowMiAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0UmVmPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VSZWYjIiB4bWxuczp4bXA9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDpCQjhBN0Y4QUZEMUYxMUUxOTY1MEFGMkYxNkY2NTQzQiIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDpBREQ4MDBFNjgxNUMxMUU0OTk1MDk4RTI4MDg3OEJGNyIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDpBREQ4MDBFNTgxNUMxMUU0OTk1MDk4RTI4MDg3OEJGNyIgeG1wOkNyZWF0b3JUb29sPSJBZG9iZSBQaG90b3Nob3AgQ0MgMjAxNCAoV2luZG93cykiPiA8eG1wTU06RGVyaXZlZEZyb20gc3RSZWY6aW5zdGFuY2VJRD0ieG1wLmlpZDpjMTcxNmViMi1mYTE1LTI2NGMtYTBlOC0wZjZhYTY2MzAxYzQiIHN0UmVmOmRvY3VtZW50SUQ9ImFkb2JlOmRvY2lkOnBob3Rvc2hvcDo3MTUxMGVjMy04MTVjLTExZTQtYTZmMy1lYzYzNzNlMTFmZmUiLz4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz4+GqmcAAAFT0lEQVR42uyYPyxlTxTH7YuKmpqamppeoiNaQUVQEVRPUBG0aNGipkXradGiRfv2k/dNzu/8ZubOtbvexibvFDdz5545///N/VGv119eXm5ubkZGRtqKAZzLy8vx8XG9np+fDw4Odnd3t30nODw8RBGkQra8Oh7Qq1aroWBvby9nh4eHOzs7myEeskG5v7+/GcQrctLR0RHKZPDw3Onpqdbv7+/go/+38iJmQqSdnZ319XV5ETlRrdT3+/v7j4+P2Bdk1GTdvDg7OTlpEvF2W8EDEySRsIh3G2G1vb393dIRB5BSPpnwCk+rIskyc3FxUa1Wm5QlARSZ98syEujq6rq/vy8KRizy8fHhdwKT/aOAXn19fX/Hi0B3A5qbka+vr6iEYnNzc0mFh4aGrq6ufF9Bfy/WTQPUafhEl1KW03IsOSYnJ4O2RDSAKRyfKJACAVJ85Rn3M1jDRQfVv7Wv2sWnWgMkA08wYyO+N6C0gyIMaIhBxTYiIs6mRIU+TKVvwEiCsa8jPm7IHOjzlDooa+lRxNfbp78Bsk/FPlOCcFXcVFRUA1uzaZgw29zc3NvbUydnn7U+0VZhOTMzg6wyGc+FhQW6hVyIECjPjhkU+XiVFzkLpnGxgzJWcPA3AAGenp6K6pA40kHlMFTm1ZAVKKurqxJJ1kBghWzQGnXKYsv2FxcX4SLXoo7Q8nxhoVd9Mvu0MbXe3d2Njo6yWFlZ2d3drf8fpqamjo+PDUcAJjtaHxwczM/Pv7291SPgyMTExPX1te1AP0BmzY7x3djYiGXQfv4gQiKVP3LcgHoWOI6QSTTp9fz8bOyQwVhwBMtw3It0dnbGpifCceiLiJcHm2CZh4eHX+XLIiltxccOka509pnHa2aU17xAzSxqmYMNMGSSPkBmrWIgvoq1mMvt7W3RwT9pLbSSsbEx0mh6etqnC8KgF/StpsEOAZgkzD70o0AkDMgmNgzacFzVySSsGmsqvpD1fBHD+KoOFw47JgfHfHHAkfDLzDUoz6CUmReCltDR0REjy9OqHshAkfG20KckFx3MX5xKATNxacGma2trVqkkDIrXHKh+WpXDQ4FleGWY8MJjwKArKS7xd7zviXu+5kKpjH1ildtjrRQs0oFASI4/Xqb8JOa/JrMtFgDWdFkwWct5RWH4hfPk8vIyRqcz2aRGzMXXvth5AeAeAkKZKo8mHRlYxkOeL+7gKyzYMfskHKmEUCJqWP1CC0LqM7MJrDEl8YS4s7OzqhN/MtR8EmCEylhfjuTGlb/5JesQmxQPiEAtmY6lgLJ5vvgPssQ69llaWpK0lSJ91JYyt2m7UNpEWgogMyXGyHGEKkXoXnadSB5UtfnCUNPUbTRLfwxlAkIGTI4XKkvJaRkvUnVL+SIezibNrA9WkgmhG8XAwECpjRSV8cxd5Eii9b+J2XX+5EQAcTmv6CBuTh70Lfw3fofKUkmOn3EtjiTsisYceYtPMXHTNLZnki+MbL+SZIMvEeUz/501y3FfxKYiiu3sHhkDeYaxiBLFI0/WHLF/BUyPmpx1uzcZSg8mwxY0+1MRI0ABa2qa4MkrCytCdCNSCgSvV0Y1z5ccYPjM1FXElgqmjt0j+cRZ4yutjS+XSNkHZHBM2nYLkCApoeJ7QIDjf9Hpeg5R/VWnV9t9Ix4NOEhNQGjuwtpBZ4ZGi1w1acKINaXDHFl6kEUwSSEGXWpra6unpyc5sqmN0WmMICyMCOpXq1X0wqyml9HJ1yooY+vAkf5IUh3hw8Xz1bhufDW1mn3M1D+4S7a14N+HSssELUe2oOXIFrQc2YIk/BRgAJPqmiY68GapAAAAAElFTkSuQmCC`"></p>"
    #create the XML
    $timestamp = get-date -Format yyyyMMdd-hhmmss
    $outputFile = "D:\PDWDiagnostics\WellnessCheck\$($fabdomain)_WellnessCheck_$($Timestamp).htm"
    
    #ConvertTo-Html -head $head -PostContent $body -body "<img src=`"$rootPath\images\Ms_logo.png`"><H1>Microsoft Analytics Platform System</H1><H2>Appliance: $fabdomain<br>Date: $timestamp</H2>" | out-file $outputFile
    #insert Microsoft Logo as base64 image
    ConvertTo-Html -head $head -PostContent $body -body "<img src=`"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIwAAAAjCAYAAABGiuIFAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAAEnQAABJ0Ad5mH3gAAAeGSURBVHhe7ZpnbxU5FIb3y672j+yn3X+z/4GWhN576EUUUSKQQICAEJpoESUKVSEU0UtCb6JDIBAgBEK8PGbeke/cmUm8K63uJX6lo8w9to/H9utzjj35xQQEeCAQJsALgTABXgiECfBCEWE6/v7DW3o62k19a4WpbvzNS2qa/zTfvnVGPQeUAwJhArwQCBPghUCYAC/0S8J8/frVfPnyJfrVf/D+/Xtz9OhRs3r1arNq1Spz8uTJqKTvKGnCPH782NTV1Zlt27ZZ2blzp/n48WNUmo22tjazdevWuN3+/fujEmMePnxoJk2aZCZMmGCuXbsWaX9+3L9/3wwfPtwMHDjQDBgwwAqk8UVJE+b8+fPx4JBBgwaZixcvRqXp6OnpMevXry9oN2XKlKjUmLVr18b6+fPnR9qfG11dXWbmzJkF81FTU2M3k8Amg1S9oaQJc+HChXiQkoULF35v8y2qUYzOzk4zbty4gjZTp06NSo2pr6+P9ZCnP+D27dvxmCdOnGg6Ojqsns319OlTs3TpUlNZWWn/9oayIwzCBGThzJkzRfVdwjBJN2/eNNevX88l3s8Edx63bNkSaX/g8uXLcdmKFSsibTbKhjBjxoyJn8lP0vD582e7g6gzcuTIuL5LGABpkCxApDdv3pgnT56YZ8+eFeVNai8bqv/hwwf72wXh4NWrV9bW69evbcKdh+7ubvPy5Utbn3Z5yTnjVV36T9sAvCNhXHNBTui+fxphNK40lA1hyEuGDh1qnydPnpw6OSSxqs9O0rNLmNOnT5tp06ZZOXz4cKT9ARbn+PHjZs6cOdZF05YkEbJu2rTJTiQLSlik/fTp082dO3fMggULbH0SaZGLRaQNCfbgwYOtrSFDhth2e/bsicOCALGOHDlibao+f6kPGQTe4dGjR3Y+xo8fb/M66lZUVNi2Bw8eNJ8+fbJ1r1y5Ytu7IXrEiBG2HnoEGypjflWWhbIhzL59++zu0G9CTxJKaKuqquxCqq5LGBZFemwK5D4kwSpDWAwtCAsPWfAQ8nYskrsYw4YNs0S4e/eufZYe0smOhHbt7e1R76ZgbNSFXOofLycwLsanumm2GS/e7uzZswV6H8lC2RBm9+7d1kVrsqqrqwvcNe5eZbW1tXaS1bYvhOHILj2LtWPHDtPa2mpu3Lhhj+X0lySMZNmyZdZrLFmyxHqWUaNGxWVz5861pz3yrsbGxoJQuWbNGts3xBHBIAAL/fz5c+sxOc2QmAJsy8siEPzSpUvm1q1b1rZbBgGZrxMnTpjNmzfH+sWLF1udhLlSGWOUPgtFhCkluITZtWuXXax58+bZ34QATSTgiIiexb53754XYVgchSB2a5r3evv2rQ2DScK4pCNcHDhwIC6DLMkcBBLKI9AnRMcjqQ3hwA23CoNg+/btcT1ImsyHyFUYP+V4PwgDIJXaYcPF1atX47KVK1dG2mwUEebX2nZvaev6niS1VBrT8LuXdDf91WcPA2EAOYh0eB1AOCF/QEfoIB/wIQxxXzpuQfOQJAwL7gKSqOzcuXORthB4ItUhZ+IOxPUOGzZssMlskhCzZs2K65CspmHRokVxnVOnTlmdO4/JA8N/PiWlEaI3+T8Jw+7j4gkdbpwkkyOydq2uu30I4170UZ4HlzD06XoQnhWOSFjd3MPF3r174/5E+uRlIx6CZJowBPA0ypcIW3jFNJBoy4ZuuPs1YYB7+cYO1S0mXkYL+G8Jg7085BGG04lylL4ShtwH4CU5tY0dOzYuQyAg+Q/9jh492uroFw+Uho0bN8ZtCY+g3xOGb0zsMvQcC/VMcif4EMY9grND85BHGEBfskV+kAYWRnWampoi7Q9gjw+ECrEIx3z6lWdFSMbTwG2t6pBsg35PGOBOuoTkUfAhjHuxhWdwk2mBUEhY6I0wbmLKiSR5X4RtEZywwxdk7CIuyI2UiON18ECcqmSbK4RkGzYS70Q5yS+JOsgjjJv0kkj3hrIlzIMHD+yEq5zLNJ0mgA9hIAHtpScMEP8JBXxG4ARGMps8VqcRhks1vRfkW758uSUkeo6rJOXqhyMt4G6FIy3vxnuTBBNOtPizZ8+2/ba0tMRtsc2phss55oK2ei9EoQ7kEcb9zsTX7ObmZttPFsqWMJyEuJWkjImlrgsfwgCSSHcxETyBvAGfHPpCGHY9fbinHoQF1jM2Iei7d+9sG3fR8AzyLAiJvRYQ24cOHSrYKIiIhWAbT+F+zsgjDPWUG7k2slDShGFnstsRd8cIDQ0NtoxPBZp8AQKoLd5BOHbsWKwneXZB+Fi3bp1NXFkUFo+/XKejZ8EgDXclspEkjAAJyD1YcNniYpHwAlGT3hCyUpd6iK7puZRLggu9GTNmFNSXbfd/fwTuYfS+XFAmQZhkDiGqbGWhpAnDpHLyQNIWRuXE9yRYXLXlI52Ah5Ce5yQgDdfqXHq9ePHC5hL8dnMR+pONPGAfInOiwRbfhNLeFeAxufGlHsJzFhkBZdhWffIVd5wueptHwHsxVr1nFkqaMAGlh0CYAC8EwgR4IRAmwAtFhAkIyEMgTIAXAmECvBAIE+ABY/4B2HeFn7DqSXwAAAAASUVORK5CYII=`"><H1>Microsoft Analytics Platform System</H1><H2>Appliance: $fabdomain<br>Date: $timestamp</H2>" | out-file $outputFile

    #open the XML
    invoke-expression $outputFile
    Write-Host "Output file saved to $outputFile"
}

## Helper functions ##
Function CreateOutputDir
{
    param($outputDir)
    if (!(test-path $outputDir))
	{
		New-item $outputDir -ItemType Dir | Out-Null
	}
}


Function New-TestObj
{
    ####################################
    # function to create a test object #
    ####################################
	param ($test_name=$null,$result="Pass",$comment=$null,$properties=$null,$outputObject=$null)
	
	$testobj = New-Object PSObject
	
	$testobj | add-member -type NoteProperty -Name "Test_Name" -value "$test_name"
	$testobj | add-member -type NoteProperty -Name "Result" -Value "$result"
	$testobj | add-member -type NoteProperty -Name "Comment" -Value "$comment"
	$testobj | add-member -type NoteProperty -Name "properties" -Value $properties
	$testobj | add-member -type NoteProperty -Name "outputObject" -Value "$outputObject"
	
	return $testObj
}

function outputForm
{
	param([String[]]$FullTestList)
	
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

	 #This creates the form and sets its size and position
	 $objForm = New-Object System.Windows.Forms.Form 
	 $objForm.Text = "Microsoft Analytics Platform System Wellness Check"
	 $objForm.Size = New-Object System.Drawing.Size(615,415) 
	 $objForm.StartPosition = "CenterScreen"

	 $objForm.KeyPreview = $True
	 $objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
	     {$empID=$objTextBox1.Text;$sn=$objTextBox2.Text;$gn=$objTextBox3.Text;$email=$objTextBox4.Text;$title=$objDepartmentListbox.SelectedItem;
	      $office=$objOfficeListbox.SelectedItem;$objForm.Close()}})
	 $objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
	     {$objForm.Close()}})

	 #create a label above the node list
	 $objLabel1 = New-Object System.Windows.Forms.Label
	 $objLabel1.Location = New-Object System.Drawing.Size(10,15) 
	 $objLabel1.Size = New-Object System.Drawing.Size(500,20) 
	 $objLabel1.Text = "Select all tests you would like to include:"
	 $objForm.Controls.Add($objLabel1) 


       #Display the test list
	    $tabindex=1
	    $verticalLocation=70
	    $horizontalLocation=20


	     foreach ($test in $FullTestList)
	     {		
	 	    Invoke-Expression ('$' + "$test" + 'obj' + "= new-object system.windows.forms.checkbox")
		    Invoke-Expression ('$' + "$test" + 'obj' + ".Location = New-Object System.Drawing.Size($horizontalLocation,$verticalLocation)")
		    Invoke-Expression ('$' + "$test" + 'obj' + ".Size = New-Object System.Drawing.Size(200,20)")
		    Invoke-Expression ('$' + "$test" + 'obj' + ".Text = `"$test`"")
		    Invoke-Expression ('$' + "$test" + 'obj' + ".TabIndex = 4")
		    Invoke-Expression ('$objForm.Controls.add($' + "$test" + 'obj)')
		    Invoke-Expression ('$' + "$test" + 'obj' + ".checked = `$false")

	        $tabindex++
	        $verticalLocation+=25
		
		    #if it gets too long start a new column
		    if($verticalLocation -gt 290)
		    {
			    $verticalLocation=70
			    $horizontalLocation+=200
		    }
	     }
		

	#action for clicking the checkHSA's button
	$ToggleQuickCheck  = {
		foreach ($test in $FullTestList)
	 	{		
			if($test -in (
                "Run_PAV",
                "Analyze_PAV_Results",
                "Active_Alerts",
                "PDW_Password_Expiry",
                "C_Drive_Free_Space",
                "D_Drive_Free_Space",
                "WMI_Health",
                "Unhealthy_Physical_Disks",
                "Retired_Physical_Disks",
                "Disks_with_Canpool_True",
                "Unhealthy_Virtual_Disks",
                "CSVs_Online",
                "CSVs_Aligned",
                "Unhealthy_Storage_Pools",
                "Number_PDs_in_VD",
                "PD_Reliability_Counters",
                "Network_Adapter_Profile",
                "Time_Sync_Config"
        ))
			{
				#kind of complicated because of the variable-variable names, but will toggle each checkbox
				Invoke-Expression ("if (" + '$' + "$test" + 'obj' + ".checked -eq `$false){" + '$' + "$test" + 'obj' + ".checked = `$true" + "}")
			}# else {" + '$' + "$test" + 'obj' + ".checked = `$false" + "}"
            Else 
            {
                Invoke-Expression ('$' + "$test" + 'obj' + ".checked = `$false")
            }
		}

	}

	$SelectAll  = {
		foreach ($test in $FullTestList)
	 	{		
			#kind of complicated because of the variable-variable names, but will toggle each checkbox
			Invoke-Expression ('$' + $test + 'obj' + ".checked = `$true")
		}

    }
    $ClearAll  = {
		foreach ($test in $FullTestList)
	 	{		
			#kind of complicated because of the variable-variable names, but will toggle each checkbox
			Invoke-Expression ('$' + $test + 'obj' + ".checked = `$false")
		}
    }

	
	#create a Toggle button for quick check
	$QuickCheckButton = New-Object System.Windows.Forms.Button
	$QuickCheckButton.Location = New-Object System.Drawing.Size(20,40)
	$QuickCheckButton.Size = New-Object System.Drawing.Size(100,20)
	$QuickCheckButton.Text = "Quick Check" 
	$QuickCheckButton.add_click($ToggleQuickCheck)
	$QuickCheckButton.TabIndex = $tabindex++
	$objForm.Controls.Add($QuickCheckButton)

	#create a Select All Button
	$SelectAllButton = New-Object System.Windows.Forms.Button
	$SelectAllButton.Location = New-Object System.Drawing.Size(350,40)
	$SelectAllButton.Size = New-Object System.Drawing.Size(100,20)
	$SelectAllButton.Text = "Select All" 
	$SelectAllButton.add_click($SelectAll)
	$SelectAllButton.TabIndex = $tabindex++
	$objForm.Controls.Add($SelectAllButton)

	#create a clear All Button
	$ClearAllButton = New-Object System.Windows.Forms.Button
	$ClearAllButton.Location = New-Object System.Drawing.Size(470,40)
	$ClearAllButton.Size = New-Object System.Drawing.Size(100,20)
	$ClearAllButton.Text = "Clear All" 
	$ClearAllButton.add_click($ClearAll)
	$ClearAllButton.TabIndex = $tabindex++
	$objForm.Controls.Add($ClearAllButton)

	 #create a label for username box
	 $UsernameLabel1 = New-Object System.Windows.Forms.Label
	 $UsernameLabel1.Location = New-Object System.Drawing.Size(40,300) 
	 $UsernameLabel1.Size = New-Object System.Drawing.Size(60,20) 
	 $UsernameLabel1.Text = "Username:"
	 $objForm.Controls.Add($UsernameLabel1) 

    #Create a PDW Username Box
    $UsernameBox = New-Object System.Windows.Forms.TextBox
    $UsernameBox.Location = New-Object System.Drawing.Size(100,300)
	$UsernameBox.Size = New-Object System.Drawing.Size(80,20)
	$UsernameBox.Text = "APSMonitor" 
	$UsernameBox.TabIndex = $tabindex++
	$objForm.Controls.Add($UsernameBox)
	
    #create a label for PASSWORD box
	 $PasswordLabel1 = New-Object System.Windows.Forms.Label
	 $PasswordLabel1.Location = New-Object System.Drawing.Size(200,300) 
	 $PasswordLabel1.Size = New-Object System.Drawing.Size(60,20) 
	 $PasswordLabel1.Text = "Password:"
	 $objForm.Controls.Add($PasswordLabel1) 
    
    #Create a PDW Password Box
    $MaskedPWBox = New-Object System.Windows.Forms.MaskedTextBox
    $MaskedPWBox.Location = New-Object System.Drawing.Size(260,300)
	$MaskedPWBox.Size = New-Object System.Drawing.Size(140,20)
	$MaskedPWBox.PasswordChar = '*'
	$MaskedPWBox.TabIndex = $tabindex++
	$objForm.Controls.Add($MaskedPWBox)
	
     #This creates the Ok button and sets the event
	 $OKButton = New-Object System.Windows.Forms.Button
	 $OKButton.Location = New-Object System.Drawing.Size(240,340)
	 $OKButton.Size = New-Object System.Drawing.Size(75,23)
	 $OKButton.Text = "Execute"
	 $OKButton.dialogResult=[System.Windows.Forms.DialogResult]::OK
	 $objform.AcceptButton = $OKButton 
	 
	 $OKButton.TabIndex = $tabindex++ 
	 $objForm.Controls.Add($OKButton)

	 #This creates the Cancel button and sets the event
	 $CancelButton = New-Object System.Windows.Forms.Button
	 $CancelButton.Location = New-Object System.Drawing.Size(320,340)
	 $CancelButton.Size = New-Object System.Drawing.Size(75,23)
	 $CancelButton.Text = "Cancel"
	 $CancelButton.dialogResult=[System.Windows.Forms.DialogResult]::Cancel
	 $objform.CancelButton=$CancelButton
	 $CancelButton.TabIndex = $tabindex++
	 $objForm.Controls.Add($CancelButton)

	 $objForm.Add_Shown({$objForm.Activate()})

	$checkedTestList=@()
	
	$dialogResult=$objform.ShowDialog()
	
	foreach ($test in $FullTestList)
	{
	
		Invoke-Expression ('if($' + "$test" + 'obj' + '.checked -eq $true){' + '$checkedTestList +=' + "`"$test`"" + '}')	
	}
	
	#Return test list when OK button is hit
	if($dialogResult -eq [System.Windows.Forms.DialogResult]::OK)
	{
        #Return $checkedTestList

        [hashtable]$returnVar=@{}
		$returnVar.username=$UsernameBox.Text
		$returnVar.password=$MaskedPWBox.Text
		$returnVar.checkedTestList=$checkedTestList

        RETURN $returnVar
	}
}
#End the main function
. WellnessCheck 