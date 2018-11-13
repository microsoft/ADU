#* FileName: DatabaseSpaceReport.ps1
#*=============================================
#* Script Name: DatabaseSpaceReport.ps1
#* Created: [2/7/2014]
#* Author: Vic Hermosillo, Nick Salch
#* Company: Microsoft
#* Email: vihermos@microsoft.com, Nicksalc@microsoft.com
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
#*
#* MOdified 9/13/18 nicksalc
#* Changes:
#* 1. Reworked script to output to a CSV so we can view results in Excel
#* 2. Combined functionality from "database settings report"
#* 3. Outputs to a SpaceReports folder instead of TableHealth
#*=============================================

param([string]$username,[string]$password,[string]$database)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors $WarningPreference = "inquire" #we want to pause on warnings $source = $MyInvocation.MyCommand.Name #Set Source to current scriptname New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged


#* Assign variables, test for and create if necessary the output folder, test and assign database credentials try
try
       {
             # Domain name and CTL host name
             $PDWHOST = GetNodeList -ctl      
             $counter = 1
             $CurrTime = get-date -Format yyyyMMddHHmmss
             $OutputFile = "D:\PDWDiagnostics\SpaceReports\DatabaseSpaceReport$CurrTime.csv"
             if (!(test-path "D:\PDWDiagnostics\SpaceReports"))
                    {
                           New-item "D:\PDWDiagnostics\SpaceReports" -ItemType Dir | Out-Null
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
if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD)) {

    write-error "failed to validate credentials"
}

## Functions
function DatabaseSettings ($database)
       {
             $VSQuery = " Use $database
        Select db_name() DatabaseName, Name SettingName, value
        from sys.extended_properties 
        where class_desc = 'Database' and name in ('pdw_replicated_size',
            'pdw_log_size',
            'pdw_is_autogrow',
            'pdw_distributed_size')
        ;"
             
             
             $resultsVSQ = Invoke-Sqlcmd -Query $VSQuery -ServerInstance "$PDWHOST"  #-ErrorAction stop
             #write-host  "Test 2"


             return $resultsVSQ
       }

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
             
             
             $resultsVSQ = Invoke-Sqlcmd -Query $VSQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD -queryTimeout 0 #-ErrorAction stop
             

             $totalVS=$null
             $totalFS=$null

             $resultsVSQ.VOLUME_SIZE_GB | foreach { $totalVS += $_ }
             #write-host  "Total Volume Space: $totalVS GBs"

             $resultsVSQ.FREE_SPACE_GB | foreach { $totalFS += $_ }
             #Write-Host  "Total Free Space: $totalFS GBs"

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

             $resultsDASQ = Invoke-Sqlcmd -Query $DASQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD -queryTimeout 0 #-ErrorAction stop

             $totalDS=0
             $resultsDASQ.DataSizeMB | foreach { [int64]$totalDS += $_ }
             #write-host  "Total Database Allocated Space: " ($totalDS / 1024)"GBs"

             return $totalDS
       }

function ReservedSpace ()
       {
             $RSQuery = "use $database; DBCC PDW_SHOWSPACEUSED"

             $resultsRSQ = Invoke-Sqlcmd -Query $RSQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD -queryTimeout 0 #-ErrorAction stop

             $totalRS = 0
             $resultsRSQ.reserved_space | foreach { [int64]$totalRS += $_ }
             return $totalRS
       }      

Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

## Get list of database names
$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb') order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD -queryTimeout 0


$userinput1 = Read-host "`nCapture Dsitributed and Replicated space usage (can be long running on large databases)? (Y/N)"
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

    # Create a DatabaseSpaceReport table to hold results
    $tableDatabaseSpaceReport = New-Object system.Data.DataTable "DatabaseSpaceReport"
    $colDatabaseName = New-Object system.Data.DataColumn Database_Name,([string])
    $SpecDistSize = New-Object system.Data.DataColumn Specified_Dist_Size,([decimal])
    $SpecRepSize = New-Object system.Data.DataColumn Specified_Rep_Size,([decimal])
    $SpecLogSize = New-Object system.Data.DataColumn Specified_Log_Size,([decimal])
    $Autogrow = New-Object system.Data.DataColumn Autogrow,([decimal])
    $TotalAllocSpace = New-Object system.Data.DataColumn Total_Allocated_Space,([decimal])
    $TotalDataSpace = New-Object system.Data.DataColumn Total_Data_Space,([decimal])
    $DistDataSpace = New-Object system.Data.DataColumn Dist_Data_Space,([decimal])
    $RepDataSpace = New-Object system.Data.DataColumn Rep_Data_Space,([decimal])
    $AllocUnusedSpace = New-Object system.Data.DataColumn Unused_Space,([decimal])

    $tableDatabaseSpaceReport.columns.add($colDatabaseName)
    $tableDatabaseSpaceReport.columns.add($SpecDistSize)
    $tableDatabaseSpaceReport.columns.add($SpecRepSize)
    $tableDatabaseSpaceReport.columns.add($SpecLogSize)
    $tableDatabaseSpaceReport.columns.add($Autogrow)
    $tableDatabaseSpaceReport.columns.add($TotalAllocSpace)
    $tableDatabaseSpaceReport.columns.add($TotalDataSpace)
    $tableDatabaseSpaceReport.columns.add($DistDataSpace)
    $tableDatabaseSpaceReport.columns.add($RepDataSpace)
    $tableDatabaseSpaceReport.columns.add($AllocUnusedSpace)


    #Collect total appliance numbers
    #trying to put totals here
    $totalVS,$totalFS = volumeSpaceTotals
    $tvs = [Math]::Round($totalVS,2)
    $tfs = [Math]::Round($totalFS,2)

    #Put the totals in a row
    $row = $tableDatabaseSpaceReport.NewRow()
    $row.Database_Name = "Appliance Total"
    $row.Specified_Dist_Size = 0
    $row.Specified_Rep_Size = 0
    $row.Specified_Log_Size = 0
    $row.Autogrow = 0
    $row.Total_Allocated_Space = $tvs
    $row.Total_Data_Space = 0
    $row.Dist_Data_Space = 0
    $row.Rep_Data_Space = 0
    $row.Unused_Space = $tfs
    $tableDatabaseSpaceReport.Rows.Add($row)
       
    $tableDatabaseSpaceReport | export-csv $OutputFile -NoTypeInformation


    $outerLCV = 0                              
       foreach ($database in $db)
             {
            ##########################
            #outer progress bar code
            #must set $outerLCV to 0 outside outer loop
            $innerLCV = 0
            [int64]$percentComplete = ($outerLCV/$($db.count))*100
            Write-Progress -Activity "Looping through databases, Current: $database" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
            $outerLCV++
            ##########################

            #Get Database settings details
                    Write-Host -ForegroundColor Cyan "`nGathering Settings data for DB: $database"
                    
                    try
                           {
                                 $totalVS = DatabaseSettings $database
                                 foreach ($Result in $totalVS)
                           {
                        switch ($Result.SettingName)
                               {
                                "pdw_distributed_size"  {$Dist=$Result.Value}
                                "pdw_is_autogrow" {if($Result.Value -eq $true){$AutoGrow="On"} Else {$AutoGrow="Off"}}
                                "pdw_log_size"  {$Log=$Result.Value}
                                "pdw_replicated_size" {$Repl=$Result.Value}
                            }
                        }

                           }
                    catch
                           {
                                 Write-Eventlog -entrytype Error -Message "Failed on calculating Database details `n`n $_.exception" -Source $source -LogName ADU -EventId 9999  
                                 Write-error "Failed on calculating Database details... `n`n $_.exception" -ErrorAction continue #Writing an error and exit
                           }

            #Add results to output table
            $row = $tableDatabaseSpaceReport.NewRow()
            $row.Database_Name = $database
            $row.Specified_Dist_Size = $Dist
            $row.Specified_Rep_Size = $Repl
            $row.Specified_Log_Size = $Log
            if ($autogrow -eq "On") {$row.Autogrow = 1}
            ELSE {$row.Autogrow =0}
            
            Write-Host "Total Distributed Size: `t$Dist GB's"            
                    Write-Host "Total Replicated Size: `t`t$Repl GB's" 
                    Write-Host   "Total Log Size: `t`t$Log GB's" 
                    Write-Host   "AutoGrow Setting: `t`t$AutoGrow " 
                    Write-Host "Original Create Database Command:"
            Write-Host -ForegroundColor Yellow " `tCreate Database $database with (Replicated_size=$Repl, Distributed_Size=$Dist, Log_Size=$Log, AutoGrow=$AutoGrow);" 
                           

            #Get Used Space Details
                    Write-Host -ForegroundColor Cyan "`nGathering Usage data for DB: $database"

                    try
                           {
                                 $totalDS = DatabaseAllocatedSpace $database
                                 $totalRS = ReservedSpace $database
                                 
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
                    #Put the totals in a row

                    $row.Total_Allocated_Space = $tds
                    $row.Total_Data_Space = $trs
                    $row.Dist_Data_Space = 0
                    $row.Rep_Data_Space = 0
                    $row.Unused_Space = $tus

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

                         Write-Progress -id 1 -Activity "Looping through tables in $database" -Status "$innerPercentComplete% Complete" -PercentComplete $innerPercentComplete
                         $innerLCV++
                        ########################

                                        # Capture DBCC PDW_SHOWSPACED output
                                        try
                                        {
                            $results = Invoke-Sqlcmd -Query "use $database; DBCC PDW_SHOWSPACEUSED (`"$tbl`");" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD -queryTimeout 0 #-ErrorAction SilentlyContinue
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
                    Write-Progress -id 1 -Activity " " -Status " " -PercentComplete 0

                                 $results = Invoke-Sqlcmd -Query "use $database; DBCC PDW_SHOWSPACEUSED;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD -queryTimeout 0 #-ErrorAction SilentlyContinue
                                 $results = ([System.Math]::Round(($results | measure data_space -sum | select Sum).sum/1024/1024,2))
                                 
                                 Write-Host "`nReplicated data space:`t`t`t`t$([System.Math]::Round(($sumRep/1024),2)) GB"
                                 Write-Host "Distributed data space:`t`t`t`t$([System.Math]::Round(($sumDst/1024),2)) GB"
                                 
                    #Put the totals in a row

                    $row.Dist_Data_Space = $([System.Math]::Round(($sumDst/1024),2))
                    $row.Rep_Data_Space = $([System.Math]::Round(($sumRep/1024),2))

                           }
                    catch  
                           {
                                 Write-Eventlog -entrytype Error -Message "Failed on printing the tableDatabaseSpaceReport table `n`n $_.exception" -Source $source -LogName ADU -EventId 9999      
                                 Write-error "Failed on collecting rep vs dist space... Exiting $_.exception" -ErrorAction Continue #Writing an error and exit
                           }

            }
        #Add newest row to output       
             $tableDatabaseSpaceReport.Rows.Add($row)

        #Append newest row to output file
        $tableDatabaseSpaceReport.Rows[1] | export-csv $OutputFile -NoTypeInformation -Append

        #remove row for output (for memory concerns)
        $tableDatabaseSpaceReport.Rows.Remove($row)
             }
             
             
             Write-Host -ForegroundColor Cyan "`nOutput also located at: $OutputFile"
}while($ans -ne "q")



