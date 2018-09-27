#* FileName: DatabaseSpaceReport.ps1
#*=============================================
#* Script Name: DatabaseSpaceReport.ps1
#* Created: [2/7/2014]
#* Author: Vic Hermosillo
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: Database Space Report
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 3/5/2014 
#* Changes:
#* 1. Integrated script for ADU
#* 2. Added error handling and logging
#* 3. Added logging to output file
#* Modified: 3/6/2014
#* Changes:
#* 1. Improved error handling
#*=============================================

param([string]$username,[string]$password,[string]$database)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged


#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
	{
		# Domain name and CTL host name
		$PdwDomainName = GetPdwDomainName
		$PDWHOST = $PdwDomainName + '-CTL01'
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "c:\PDWDiagnostics\TableHealth\DatabaseSpaceReport$CurrTime.txt"
		if (!(test-path "c:\PDWDiagnostics\TableHealth"))
			{
				New-item "c:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
			}
		if (!(test-path $OutputFile))
			{
				New-Item $OutputFile -ItemType File|out-null
			}

		# Get username and credentials
		
		if(!$username)
			{   $PDWUID = GetPdwUsername; $PDWPWD = GetPdwPassword }
		else
			{   $PDWUID = $username; $PDWPWD = $password }	
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}	


if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD -pdwDomain $PdwDomainName))
{

    write-error "failed to validate credentials"
}


## Functions
function volumeSpaceTotals ()
	{
		$VSQuery = "SELECT
		A.PDW_NODE_ID,
		A.VOLUME_NAME,
		A.VOLUME_SIZE_GB,
		A.FREE_SPACE_GB,
		A.SPACE_UTILIZED,
		A.VOLUME_TYPE
		FROM
		(
		SELECT 
		space.[pdw_node_id] ,
		MAX(space.[volume_name]) as 'volume_name' ,
		MAX(space.[volume_size_gb]) as 'volume_size_gb' ,
		MAX(space.[free_space_gb]) as 'free_space_gb' ,
		(MAX(space.[volume_size_gb]) - MAX(space.[free_space_gb])) / CAST(MAX(space.[volume_size_gb]) AS FLOAT) as 'space_utilized' ,
		CASE 
			  WHEN LEFT(MAX(space.[volume_name]), 1) = 'Z' THEN 'TEMP'
			  WHEN CHARINDEX('LOG', MAX(space.[volume_name])) > 0 THEN 'LOG' 
			  WHEN LEFT(MAX(space.[volume_name]), 1) = 'C' THEN 'OS'
			  ELSE 'DATA'
		END as 'volume_type'
		FROM (
		SELECT 
		s.[pdw_node_id],
		(CASE WHEN p.property_name = 'volume_name' THEN s.[property_value] ELSE NULL END) as 'volume_name' ,
		(CASE WHEN p.property_name = 'volume_size' THEN (CAST(ISNULL(s.[property_value], '0') AS BIGINT)/1024/1024/1024.0) ELSE 0 END) as 'volume_size_gb' ,
		(CASE WHEN p.property_name = 'volume_free_space' THEN (CAST(ISNULL(s.[property_value], '0') AS BIGINT)/1024/1024/1024.0) ELSE 0 END) as 'free_space_gb' ,
		s.[component_instance_id]
		FROM [sys].[dm_pdw_component_health_status] s
		JOIN [sys].[pdw_health_components] c 
		ON s.[component_id] = c.[component_id]
		JOIN [sys].[pdw_health_component_properties] p 
		ON s.[property_id] = p.[property_id] AND s.[component_id] = p.[component_id]
		WHERE
		c.[Component_name] = 'Volume'
		AND p.[property_name] IN ('volume_name', 'volume_free_space', 'volume_size')
		) space
		GROUP BY
		space.[pdw_node_id] ,
		space.[component_instance_id]
		--ORDER BY
		--space.[pdw_node_id],
		--MAX(space.[volume_name])
		) A
		WHERE 
			A.PDW_NODE_ID not like ('101%')
		AND        A.PDW_NODE_ID not like ('301%')
		AND  A.PDW_NODE_ID not like ('401%')        
		AND A.VOLUME_TYPE not in ('OS', 'LOG', 'TEMP')
		ORDER BY
		A.PDW_NODE_ID,
		A.VOLUME_NAME
		;"
		
		

		$resultsVSQ = Invoke-Sqlcmd -Query $VSQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction stop
		

		$totalVS=$null
		$totalFS=$null

		$resultsVSQ.VOLUME_SIZE_GB | foreach { $totalVS += $_ }
		#write-host	"Total Volume Space: $totalVS GBs"

		$resultsVSQ.FREE_SPACE_GB | foreach { $totalFS += $_ }
		#Write-Host	"Total Free Space: $totalFS GBs"

		return $totalVS,$totalFS
	}

function DatabaseAllocatedSpace ()
	{	
		$DASQuery = "SELECT 
		  [pdw_node_id], 
		  [db_name], 
		SUM(CASE WHEN [file_type] = 'DATA' THEN [value_MB] ELSE 0 END) AS [DataSizeMB],
		SUM(CASE WHEN [file_type] = 'LOG' THEN [value_MB] ELSE 0 END) AS [LogSizeMB]
		FROM (
			  SELECT 
					pc.[pdw_node_id], 
					RTRIM(pc.[counter_name]) AS [counter_name], 
		ISNULL(d.[name], pc.[instance_name]) AS [db_name], 
					pc.[cntr_value]/1024 AS [value_MB],
					CASE WHEN [counter_name] LIKE 'Data File(s) Size%' THEN 'DATA' ELSE 'LOG' END AS [file_type]
			  FROM sys.dm_pdw_nodes_os_performance_counters pc
					LEFT JOIN sys.pdw_database_mappings dm ON pc.instance_name = dm.physical_name
					INNER JOIN sys.databases d ON d.database_id = dm.database_id
			  WHERE 
					([counter_name] LIKE 'Log File(s) Size%'
						  OR [counter_name] LIKE 'Data File(s) Size%')
		 
					--AND (d.[name] <> dm.[physical_name] 
					  --    OR pc.[instance_name] LIKE '%tempdb%'
		---  )
		) db
		WHERE pdw_node_id not like ('101%')
		AND db_name = '" + $database + "'
		GROUP BY [pdw_node_id], [db_name]
		ORDER BY [db_name], [pdw_node_id]
		;"

		$resultsDASQ = Invoke-Sqlcmd -Query $DASQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction stop

		$totalDS=0
		$resultsDASQ.DataSizeMB | foreach { [int]$totalDS += $_ }
		#write-host	"Total Database Allocated Space: " ($totalDS / 1024)"GBs"

		return $totalDS
	}

function ReservedSpace ()
	{
		$RSQuery = "use $database; DBCC PDW_SHOWSPACEUSED"

		$resultsRSQ = Invoke-Sqlcmd -Query $RSQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction stop

		$totalRS = 0
		$resultsRSQ.reserved_space | foreach { [int]$totalRS += $_ }
		return $totalRS
	}	

Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

## Get list of database names
$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb') order by name desc;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD


do
{
	#create the initial menu array
	$TableMenuOptions=@()
	$TableMenuOptions = (
		#@{"header"="Select a database or all"},
		@{"header"="Run for All Databases"},
		"All DBs",
		@{"header"="Select a single database"}
	)
	
	# Add the DB names to the array
	for ($i=1;$i -le $dbs.count; $i++) {$TableMenuOptions+=($dbs[$i-1].name)}

	[string]$ans = OutputMenu -header "Check Replicated Table Size" -options $TableMenuOptions
	if($ans -eq "q"){break}
		
	if ($ans -eq "All DBs")
	{
		$db=@()
		$db = $dbs.name
	}
	else{$db=$ans}
		
	foreach ($database in $db)
		{
			"`n" |out-file -append $OutputFile
			Write-Host -ForegroundColor Cyan "`nGathering data for DB: $database"
			"Getting data space details for $database" |out-file -append $OutputFile
			
			try
				{
					$totalVS,$totalFS = volumeSpaceTotals
					$totalDS = DatabaseAllocatedSpace $database
					$totalRS = ReservedSpace $database
					
					$tvs = [Math]::Round($totalVS,2)
					$tfs = [Math]::Round($totalFS,2)
					$tds = [Math]::Round(($totalDS / 1024),2)
					$trs = [Math]::Round((($totalRS / 1024 ) / 1024),2)
					$tus = $tds - $trs
				}
			catch
				{
					Write-Eventlog -entrytype Error -Message "Failed on calculating table details `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed on calculating table details... Exiting" -ErrorAction Stop #Writing an error and exit
				}

			
			try
				{
					# Create a DatabaseSpaceReport
					$tableDatabaseSpaceReport = New-Object system.Data.DataTable "DatabaseSpaceReport"
					$colDatabaseName = New-Object system.Data.DataColumn databaseName,([string])
					$coltvs = New-Object system.Data.DataColumn totalApplianceVolumeSpace,([decimal])
					$coltfs = New-Object system.Data.DataColumn totalApplianceFreeSpace,([decimal])
					$coltds = New-Object system.Data.DataColumn totalDatabaseAllocatedSpace,([decimal])
					$coltrs = New-Object system.Data.DataColumn totalActualSpace,([decimal])
					$coltus = New-Object system.Data.DataColumn totalAllocatedUnusedSpace,([decimal])
					
					$tableDatabaseSpaceReport.columns.add($colDatabaseName)
					$tableDatabaseSpaceReport.columns.add($coltvs)
					$tableDatabaseSpaceReport.columns.add($coltfs)
					$tableDatabaseSpaceReport.columns.add($coltds)
					$tableDatabaseSpaceReport.columns.add($coltrs)
					$tableDatabaseSpaceReport.columns.add($coltus)
					
					$row = $tableDatabaseSpaceReport.NewRow()
					$row.databaseName = $database
					$row.totalApplianceVolumeSpace = $tvs
					$row.totalApplianceFreeSpace = $tfs
					$row.totalDatabaseAllocatedSpace = $tds
					$row.totalActualSpace = $trs
					$row.totalAllocatedUnusedSpace = $tus
					$tableDatabaseSpaceReport.Rows.Add($row)
				}
			catch 
				{
					Write-Eventlog -entrytype Error -Message "Failed on creating tableDatabaseSpaceReport `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed on creating tableDatabaseSpaceReport... Exiting" -ErrorAction Stop #Writing an error and exit
				}
			
			
			try
				{
					#$tableDatabaseSpaceReport |ft databasename, totalApplianceVolumeSpace, totalApplianceFreeSpace, totalDatabaseAllocatedSpace, totalActualSpace, totalAllocatedUnusedSpace -auto
					#$tableDatabaseSpaceReport |ft databasename, totalApplianceVolumeSpace, totalApplianceFreeSpace, totalDatabaseAllocatedSpace, totalActualSpace, totalAllocatedUnusedSpace -auto  |out-file -append $OutputFile
					#$tableDatabaseSpaceReport |ft databasename,  @{label = "Total Appliance Volume Space GBs" ; Expression = {$_.totalApplianceVolumeSpace}}, @{label = "Total Appliance Free Space GBs" ; Expression = {$_.totalApplianceFreeSpace}}, @{label = "Total Database Allocated Space GBs" ; Expression = {$_.totalDatabaseAllocatedSpace}}, @{label = "Total Actual Space GBs" ; Expression = {$_.totalActualSpace}}, @{label = "Total Allocated Unused Space GBs" ; Expression = {$_.totalAllocatedUnusedSpace}} -auto
					#$tableDatabaseSpaceReport |ft databasename,  @{label = "Total Appliance Volume Space GBs" ; Expression = {$_.totalApplianceVolumeSpace}}, @{label = "Total Appliance Free Space GBs" ; Expression = {$_.totalApplianceFreeSpace}}, @{label = "Total Database Allocated Space GBs" ; Expression = {$_.totalDatabaseAllocatedSpace}}, @{label = "Total Actual Space GBs" ; Expression = {$_.totalActualSpace}}, @{label = "Total Allocated Unused Space GBs" ; Expression = {$_.totalAllocatedUnusedSpace}} -auto |out-file -append $OutputFile
				
					Write-Host "Total Appliance Volume Space (Used and Unused): `t$tvs GB's"		
					Write-Host "Total Appliance Free Space (Unused): `t`t`t$tfs GB's" 
					Write-Host	"Total Database Allocated Space (Reserved): `t`t$tds GB's" 
					Write-Host	"Total Actual Space (Data space): `t`t`t$trs GB's" 
					Write-Host "Total Allocated Unused Space(Unused data space):" -NoNewline; Write-Host -ForegroundColor Yellow " `t$tus GB's" 
					
					"Total Appliance Volume Space (Used and Unused): `t$tvs GB's"	|out-file -append $OutputFile	
					"Total Appliance Free Space (Unused): `t`t`t$tfs GB's"  |out-file -append $OutputFile
					"Total Database Allocated Space (Reserved): `t`t$tds GB's" |out-file -append $OutputFile
					"Total Actual Space (Data space): `t`t`t$trs GB's" |out-file -append $OutputFile
					"Total Allocated Unused Space(Unused data space): `t$tus GB's" |out-file -append $OutputFile
				
				}
			catch
				{
					Write-Eventlog -entrytype Error -Message "Failed on printing the tableDatabaseSpaceReport table `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed on printing the tableDatabaseSpaceReport table... Exiting" -ErrorAction Stop #Writing an error and exit
				}
			
		}
		
		
		$VSQuery2 = "
		--Total Compute node volume space details
		SELECT
		A.PDW_NODE_ID,
		A.VOLUME_NAME,
		A.VOLUME_SIZE_GB,
		A.FREE_SPACE_GB,
		A.SPACE_UTILIZED,
		A.VOLUME_TYPE
		FROM
		(
		SELECT 
		space.[pdw_node_id] ,
		MAX(space.[volume_name]) as 'volume_name' ,
		MAX(space.[volume_size_gb]) as 'volume_size_gb' ,
		MAX(space.[free_space_gb]) as 'free_space_gb' ,
		(MAX(space.[volume_size_gb]) - MAX(space.[free_space_gb])) / CAST(MAX(space.[volume_size_gb]) AS FLOAT) as 'space_utilized' ,
		CASE 
			  WHEN LEFT(MAX(space.[volume_name]), 1) = 'Z' THEN 'TEMP'
			  WHEN CHARINDEX('LOG', MAX(space.[volume_name])) > 0 THEN 'LOG' 
			  WHEN LEFT(MAX(space.[volume_name]), 1) = 'C' THEN 'OS'
			  ELSE 'DATA'
		END as 'volume_type'
		FROM (
		SELECT 
		s.[pdw_node_id],
		(CASE WHEN p.property_name = 'volume_name' THEN s.[property_value] ELSE NULL END) as 'volume_name' ,
		(CASE WHEN p.property_name = 'volume_size' THEN (CAST(ISNULL(s.[property_value], '0') AS BIGINT)/1024/1024/1024.0) ELSE 0 END) as 'volume_size_gb' ,
		(CASE WHEN p.property_name = 'volume_free_space' THEN (CAST(ISNULL(s.[property_value], '0') AS BIGINT)/1024/1024/1024.0) ELSE 0 END) as 'free_space_gb' ,
		s.[component_instance_id]
		FROM [sys].[dm_pdw_component_health_status] s
		JOIN [sys].[pdw_health_components] c 
		ON s.[component_id] = c.[component_id]
		JOIN [sys].[pdw_health_component_properties] p 
		ON s.[property_id] = p.[property_id] AND s.[component_id] = p.[component_id]
		WHERE
		c.[Component_name] = 'Volume'
		AND p.[property_name] IN ('volume_name', 'volume_free_space', 'volume_size')
		) space
		GROUP BY
		space.[pdw_node_id] ,
		space.[component_instance_id]
		--ORDER BY
		--space.[pdw_node_id],
		--MAX(space.[volume_name])
		) A
		WHERE 
		A.PDW_NODE_ID not like ('101%')
		AND A.PDW_NODE_ID not like ('301%')
		AND  A.PDW_NODE_ID not like ('401%')        
		AND A.VOLUME_TYPE not in ('OS', 'LOG', 'TEMP')
		ORDER BY
		A.PDW_NODE_ID,
		A.VOLUME_NAME;
		"
		$resultsVSQ2 = Invoke-Sqlcmd -Query $VSQuery2 -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction stop
		
		$resultsVSQ2.volumne_size_gb
		
		Write-Host -ForegroundColor Cyan "`nOutput also located at: $OutputFile"
}while($ans -ne "q")
