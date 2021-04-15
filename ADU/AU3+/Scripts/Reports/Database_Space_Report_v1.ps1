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
#* Modified: 05/09/2017 sfacer
#* Changes:
#* 1. Added '[' and ']' delimiters to schema and table names
#* Modified: 05/31/2017 sfacer
#* Changes:
#* 1. Changed all [int] typed variables to [int64]
#* 2. Added prompt for capture of Repl & Dist space - this functionality will run a very long time in a large DB
#* Modified: 08/14/2017 sfacer
#* changes:
#* 1. Added [int64] strong typing to:
#*  [int64]$totalDS = DatabaseAllocatedSpace $database
#*  [int64]$totalRS = ReservedSpace $database
#* Modified: 11/22/2017 sfacer
#* Changes:
#* 1. Modified initial db name query, to limit to only Online databases
#* Modified: 10/04/2018 sfacer
#* Changes
#* 1. Changed login failure error handling
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
		$PDWHOST = GetNodeList -ctl	
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "D:\PDWDiagnostics\TableHealth\DatabaseSpaceReport$CurrTime.txt"
		if (!(test-path "D:\PDWDiagnostics\TableHealth"))
			{
				New-item "D:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
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
if ($PDWUID -eq $null -or $PDWUID -eq "")
  {
    Write-Host  "UserName not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }
	
if ($PDWPWD -eq $null -or $PDWPWD -eq "")
  {
   Write-Host  "Password not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }

if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD))
  {
    Write-Host  "UserName / Password authentication failed - script is exiting" -ForegroundColor Red
    pause
    return
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

		[int64]$totalDS=0
        If ($resultsDASQ -ne $null) {
  		  $resultsDASQ.DataSizeMB | foreach { [int64]$totalDS += $_ }
		  #write-host	"Total Database Allocated Space: " ($totalDS / 1024)"GBs"
        }

		return $totalDS
	}

function ReservedSpace ()
	{
		$RSQuery = "use $database; DBCC PDW_SHOWSPACEUSED"

		$resultsRSQ = Invoke-Sqlcmd -Query $RSQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction stop

		[int64]$totalRS = 0
		$resultsRSQ.reserved_space | foreach { [int64]$totalRS += $_ }
		return $totalRS
	}	

Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

## Get list of database names
$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb') and state = 0 order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD


$userinput1 = Read-host "`nCapture Distributed and Replicated space usage (can be long running on large databases)? (Y/N)"
If ($userinput1 -eq "Y")
  {
    $CaptureDetail = $true
  }
Else
  {
    $CaptureDetail = $false
  }


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
	for ($i=1;$i -le @($dbs).count; $i++) {$TableMenuOptions+=($($dbs[$i-1].name))}

	[string]$ans = OutputMenu -header "Database Space Report" -options $TableMenuOptions
	if($ans -eq "q"){break}
		
	if ($ans -eq "All DBs")
	{
		$db=@()
		$db = $dbs.name
	}
	else{$db=$ans}
	
	#trying to put totals here
	$totalVS, $totalFS = volumeSpaceTotals
	$tvs = [Math]::Round($totalVS,2)
	$tfs = [Math]::Round($totalFS,2)
	
	Write-Host -ForegroundColor Cyan "`nAPPLIANCE TOTAL"
	Write-Host "Total Appliance Volume Space (Used and Unused): $tvs GB, $([System.Math]::Round(($tvs/1024),1)) TB"		
	Write-Host "Total Appliance Free Space (Unused): `t`t$tfs GB, $([System.Math]::Round(($tfs/1024),1)) TB"
	
	"APPLIANCE TOTAL" |out-file -append $OutputFile
	"Total Appliance Volume Space (Used and Unused): $tvs GB, $([System.Math]::Round(($tvs/1024),1)) TB"	|out-file -append $OutputFile	
	"Total Appliance Free Space (Unused): `t`t$tfs GB, $([System.Math]::Round(($tfs/1024),1)) TB"  |out-file -append $OutputFile

    $outerLCV = 0					
	foreach ($database in $db)
		{
            ##########################
            #outer progress bar code
            #must set $outerLCV to 0 outside outer loop
            $innerLCV = 0
            [int64]$percentComplete = ($outerLCV/$($db.count))*100
            Write-Progress -Activity "Looping through databases" -Status "$percentComplete Percent Complete" -PercentComplete $percentComplete
            $outerLCV++
            ##########################

			"`n" |out-file -append $OutputFile
			Write-Host -ForegroundColor Cyan "`nDatabase: $database"
			"Database: $database" |out-file -append $OutputFile
			
			try
				{
					[int64]$totalDS = DatabaseAllocatedSpace $database
					[int64]$totalRS = ReservedSpace $database
					
					[decimal]$tds = [Math]::Round(($totalDS / 1024),2)
					[decimal]$trs = [Math]::Round((($totalRS / 1024 ) / 1024),2)
					[decimal]$tus = $tds - $trs
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
					
					Write-Host "Allocated Space (Reserved): `t`t`t$tds GB" 
					Write-Host "Data space (Used): `t`t`t`t$trs GB" 
					Write-Host "Allocated Unused Space(Unused data space):" -NoNewline; Write-Host -ForegroundColor Yellow " `t$tus GB" 
					
					"`nAllocated Space (Reserved): `t`t`t$tds GB" |out-file -append $OutputFile
					"Data space (Used): `t`t`t`t$trs GB" |out-file -append $OutputFile
					"Allocated Unused Space(Unused data space): `t$tus GB" |out-file -append $OutputFile
				
				}
			catch
				{
					Write-Eventlog -entrytype Error -Message "Failed on printing the tableDatabaseSpaceReport table `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed on printing the tableDatabaseSpaceReport table... Exiting" -ErrorAction Stop #Writing an error and exit
				}
			
			If ($CaptureDetail -eq $true) 
                          {
 
			#collect replicated vs distributed space
			try
				{
					$tbls = Invoke-Sqlcmd -QueryTimeout 0 -Query "use $database; SELECT '[' + sc.name + '].[' + ta.name + ']' as TableName, c.distribution_policy as distribution_policy  FROM sys.tables ta INNER JOIN sys.partitions pa ON pa.OBJECT_ID = ta.OBJECT_ID INNER JOIN sys.schemas sc ON ta.schema_id = sc.schema_id, sys.pdw_table_mappings b, sys.pdw_table_distribution_properties c WHERE ta.is_ms_shipped = 0 AND pa.index_id IN (1,0) and ta.object_id = b.object_id AND b.object_id = c.object_id GROUP BY sc.name,ta.name, c.distribution_policy ORDER BY c.distribution_policy, SUM(pa.rows) DESC;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
					$sumRep = 0 
					$sumDst = 0
					
					foreach($tbl in $tbls.tablename) 
					{
                        ########################
                        #Inner progress bar code
                        #must set $innerLCV to 0 outside inner loop, but inside outer loop.
                        if ($($tbls.count) -eq 0)
                        {
                            "Found 0 tables"
                        }
                        else
                        {
					        [int64]$innerPercentComplete = ($innerLCV/$($tbls.tablename.count))*100
                        }

                         Write-Progress -id 1 -Activity "Looping through tables in $database" -Status "$innerPercentComplete Percent Complete" -PercentComplete $innerPercentComplete
                         $innerLCV++
                        ########################

						# Capture DBCC PDW_SHOWSPACED output
						try
						{
                            $results = Invoke-Sqlcmd -Query "use $database; DBCC PDW_SHOWSPACEUSED (`"$tbl`");" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
						}
						catch
						{
							Write-Host "Failed to run DBCC query on $tbl" -ForegroundColor Yellow
                            Write-Eventlog -entrytype Error -Message "Failed to run DBCC query `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
                            Write-error "Failed to run DBCC query... Exiting" -ErrorAction Continue #Writing an error and exit
						}
						$totalDataSpace = ([System.Math]::Round(($results | measure data_space -sum | select Sum).sum/1024,2))
						 
						if($results[0].DISTRIBUTION_ID -eq -1) #Replicated
						{
							$sumRep += $totalDataSpace
						}
						else #distributed
						{        
							$sumDst += $totalDataSpace
						}

					}
					$results = Invoke-Sqlcmd -Query "use $database; DBCC PDW_SHOWSPACEUSED;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
					$results = ([System.Math]::Round(($results | measure data_space -sum | select Sum).sum/1024/1024,2))
					
					Write-Host "`nReplicated data space:`t`t`t`t$([System.Math]::Round(($sumRep/1024),2)) GB"
					Write-Host "Distributed data space:`t`t`t`t$([System.Math]::Round(($sumDst/1024),2)) GB"
					
					"Replicated data space:`t`t`t`t$([System.Math]::Round(($sumRep/1024),2)) GB" |out-file -append $OutputFile
					"Distributed data space:`t`t`t`t$([System.Math]::Round(($sumDst/1024),2)) GB" |out-file -append $OutputFile
				}
			catch	
				{
					Write-Eventlog -entrytype Error -Message "Failed on printing the tableDatabaseSpaceReport table `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed on collecting rep vs dist space... Exiting $_.exception" -ErrorAction Continue #Writing an error and exit
				}

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
