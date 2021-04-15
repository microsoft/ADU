# FileName: CCI_Health.ps1
#*=============================================
#* Script Name: CCI_Health.ps1
#* Created: [06/13/2019]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: CCI Health Report
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: ??/??/????
#* Changes:
#* 1. ??
#*=============================================

param([string]$username,[string]$password,[string]$database)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$ErrorActionPreference = "inquire" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9900 -EntryType Information -message "Starting $source" #first event logged

#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
  {
    # Domain name and CTL host name
    $CTLNode = GetNodeList -ctl
    $CMPNodes = GetNodeList -cmp
    $CurrTime = get-date -Format yyyyMMddHHmmss
    $OutputFileCSV = "D:\PDWDiagnostics\TableHealth\CCI_Health_$database`_$CurrTime.csv"
    if (!(test-path $OutputFileCSV)) {
        New-Item $OutputFileCSV -ItemType File|out-null
      }
  }
catch
  {
	write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
	Write-error "Failed to assign variables... Exiting" #Writing an error and exit
  }	


try {
    $DBA_DBName = get-content -Path "$rootPath\Config\DBA_db.txt"
    if ($DBA_DBName -eq $null) {
        $DBA_DBName = ""
      }
    else {
        $SQLQuery = "
SELECT name
FROM sys.databases 
WHERE name = '" + $DBA_DBName + "';"
	    $rset_DBADBName = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Username $username -Password $password
        if ($rset_DBADBName.Count -eq 0) {
            Write-EventLog -Source $source -logname "ADU" -EventID 9901 -EntryType Warning -message "Running CCI_Health.ps1, target DB ($DBA_DBName) not found, data will be written to file only"
            $DBA_DBName = ""
          }
      }
  }
catch {
    Write-EventLog -Source $source -logname "ADU" -EventID 9902 -EntryType Warning -message "Running CCI_Health.ps1, no target DB found in .\AU3+\Config\DBA_db.txt, data will be written to file only"
    $DBA_DBName = ""
  }

if ($database -eq $null -or $database -eq "") {
    Write-EventLog -Source $source -logname "ADU" -EventID 9990 -EntryType Error -message "Running CCI_Health.ps1, no database name passed"
    return
  }
if ($username -eq $null -or $username -eq "") {
    Write-EventLog -Source $source -logname "ADU" -EventID 9991 -EntryType Error -message "Running CCI_Health.ps1, login information (username) not passed"
    return
  }
if ($password -eq $null -or $password -eq "") {
    Write-EventLog -Source $source -logname "ADU" -EventID 9992 -EntryType Error -message "Running CCI_Health.ps1, login information (password) not passed"
    return
  }


## Functions

function Get-CTL01MappedDatabaseName ($dbname)
  {	
	$SQLQuery = "
SELECT d.name as DBName, dm.physical_name as Mapped_DB
FROM sys.databases d INNER JOIN sys.pdw_database_mappings dm ON d.database_id = dm.database_id
WHERE d.name = '" + $dbname + "';"

	$rset_MappedDBName = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Username $username -Password $password
	$MappedDBName=$rset_MappedDBName.Mapped_DB
        
    return $MappedDBName
  }

  
function Get-CTL01MappedTableList($dbname)
  {
    $rset_MappedTableNames = @{}
    $SQLQuery = "
SELECT DISTINCT s.name + '.' + o.name as UserTable, tm.physical_name AS Mapped_Table
FROM [$dbname].[sys].[objects] o INNER JOIN [$dbname].[sys].[pdw_table_mappings] tm ON o.object_id = tm.object_id INNER JOIN [$dbname].[sys].[schemas] s ON o.schema_id = s.schema_id
ORDER BY 1, 2;"

    $rset_MappedTableNames = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Username $username -Password $password

    return $rset_MappedTableNames
  }


function Get-CMPCCIHealth ($dbname,$MappedDBName)
  {

    Remove-Job -State Completed

    # Define a table for the Job Stats
$tblJobstats = New-Object system.Data.DataTable "JobStats"
$colJobID = New-Object system.Data.DataColumn JobID,([Int])
$colNodeName = New-Object system.Data.DataColumn NodeName,([string])
$colStartDateTime = New-Object system.Data.DataColumn StartDateTime,([string])
$colEndDateTime = New-Object system.Data.DataColumn EndDateTime,([string])
$tblJobstats.Columns.Add($colJobID)
$tblJobstats.Columns.Add($colNodeName)
$tblJobstats.Columns.Add($colStartDateTime)
$tblJobstats.Columns.Add($colEndDateTime)

    $jobname = Get-Date -Format "yyyyMMddHHmmss"
    $jobname = "CCIHealth_" + $jobname

    foreach ($node in $CMPNodes) { 

        $JobStats = $tblJobstats.NewRow()
        $JobStats.NodeName = $node
        $JobStats.StartDateTime = (Get-Date)
        $JobStats.EndDateTime = "01/01/1900"
	
	    Start-Job -Name $jobname  -Argument $cciquery,$MappedDBName,$node -ScriptBlock {
		    $cciquery = "USE " + $using:MappedDBName + "; 
SELECT 
        @@ServerName as NodeName,
        db_name() as db_name,
        schema_name(schema_id) as schema_name,
        t.name AS TableName,   
        i.name AS IndexName,   
        i.index_id,    
        csrg.state_desc,
		csrg.state,
        csrg.trim_reason_desc,
		csrg.trim_reason,
	    SUM(csrg.total_rows) AS total_rows,
        CASE 
			WHEN csrg.state = 3 THEN MIN(csrg.total_rows) 
			ELSE NULL
	    END AS min_rows,
        CASE 
			WHEN csrg.state = 3 THEN MAX(csrg.total_rows) 
			ELSE NULL
	    END AS max_rows,
        CASE 
			WHEN csrg.state = 3 THEN SUM(csrg.total_rows) / count(1)
			ELSE NULL
	    END AS avg_rows,
        CASE 
			WHEN csrg.state = 3 THEN SUM(csrg.deleted_rows) 
			ELSE NULL
	    END AS deleted_rows, 
        SUM(csrg.size_in_bytes) as size_in_bytes,
        CASE 
			WHEN csrg.state = 3 THEN 100 * (SUM(CAST(COALESCE(csrg.deleted_rows, 0) AS DECIMAL(15,4))) / 
											SUM(CAST(COALESCE(csrg.total_rows, 0) AS DECIMAL(15,4))) ) 
			ELSE NULL
	    END AS 'Fragmentation',
        count(1) as RG_Count
    FROM sys.indexes AS i  
    JOIN sys.tables as t
        ON i.object_id = t.object_id
    JOIN sys.dm_db_column_store_row_group_physical_stats AS csrg  
        ON i.object_id = csrg.object_id AND i.index_id = csrg.index_id   
	WHERE i.type_desc = 'CLUSTERED COLUMNSTORE'
    GROUP BY 
        schema_name(schema_id),
        t.name,
        i.object_id,   
        object_name(i.object_id) ,
        i.name,
        i.index_id,   
        i.type_desc,   
        csrg.state,
        csrg.state_desc,
        csrg.trim_reason,
        csrg.trim_reason_desc;"
		$results = Invoke-Sqlcmd -Query "$cciquery" -ServerInstance $using:node	-QueryTimeout 10800
		$results 		
          }		

        $JobStats.JobId = ((Get-Job -Name $JobName | Sort-Object Id -Descending)[0]).Id
        $tblJobstats.Rows.Add($JobStats)

	  }

    write-host "Waiting for CMP Node jobs to complete." -NoNewline -ForegroundColor Cyan
    while (((get-job -Name $jobname).state | ? {$_ -eq 'Running'}) -gt 0) {
        start-sleep -seconds 10
        write-host "." -NoNewline -ForegroundColor Cyan    

        $CompletedJobs = Get-Job -State Completed
        foreach ($CompletedJob in $CompletedJobs) {
            $JobID = $CompletedJob.Id
            if (($tblJobstats.Select("JobId=$JobID")).EndDateTime -eq "01/01/1900") {
                $tblJobstats.Select("JobId=$JobID") | foreach {$_.EndDateTime = Get-Date}
              }
          }

      }
    Write-Host ""

    foreach ($JobStats in $tblJobstats) {
        $NodeName = $JobStats.NodeName
        $JobElapsed = (Get-Date $JobStats.EndDateTime) - (Get-Date $JobStats.StartDateTime)
        $Elapsed = $JobElapsed -f "#"
        Write-EventLog -Source $source -logname "ADU" -EventID 9906 -EntryType Information -message "CCI_Health.ps1 for database $database. Data extract job for node $NodeName completed in $Elapsed"
      }        

    $TaskElapsed = (Get-Date) - $TaskStartTime
    $Elapsed = $TaskElapsed -f "#"
    Write-EventLog -Source $source -logname "ADU" -EventID 9907 -EntryType Information -message "CCI_Health.ps1 for database $database. Data extract jobs completed, elapsed time $Elapsed"
    $TaskStartTime = Get-Date

    Write-Host "Retrieving data from CMP Node jobs." -ForegroundColor Cyan

    $rset_CCIData = Get-Job -Name $jobname | Receive-Job -Wait 

    $CMPNodeCCIHealth = @()
    foreach ($row in $rset_CCIData) 
      {
        $CMPNodeCCIHealth += @(New-Object -TypeName psobject -Property @{ `
        'Node'=$row.NodeName;'M_DBName'=$row.db_name;'M_TableName'=$row.TableName;'M_IndexName'=$row.IndexName;'State_Desc'=$row.state_desc;'State'=$row.state;'TrimReason_Desc'=$row.trim_reason_desc;'TrimReason'=$row.trim_reason;'TotRows'=$row.total_rows;'MinRows'=$row.min_rows;'MaxRows'=$row.max_rows;'AvgRows'=$row.avg_rows;'DelRows'=$row.deleted_rows;'SizeInBytes'=$row.size_in_bytes;'FragmentationPct'=$row.Fragmentation;'RGCount'=$row.RG_Count;})
      }	

   Get-Job -Name $jobname | Remove-Job

    return $CMPNodeCCIHealth

  }

function Write-ProcessStart ($RunDateTime, $database)
  {

    $SQLQuery = "
IF NOT EXISTS (SELECT * FROM sysobjects where name = 'CCI_Health') 
 CREATE TABLE CCI_Health (
        RunID		          INT     	   NOT NULL,
        RunDateTime	          DATETIME	   NOT NULL,
        NodeName              VARCHAR(16)  NULL,
        DBName                VARCHAR(256) NULL,
        TableName             VARCHAR(256) NULL,
        M_DBName              VARCHAR(256) NULL,
        M_TableName           VARCHAR(256) NULL,
        M_IndexName           VARCHAR(256) NULL,
        RG_State              INT          NULL,
        RG_State_Desc         VARCHAR(256) NULL,
        RG_Count	          INT          NULL,
        Trim_Reason           INT          NULL,
        Trim_Reason_Desc      VARCHAR(256) NULL,
        TotalRows             BIGINT       NULL,
        MinRows               BIGINT       NULL,
        MaxRows               BIGINT       NULL,
        AvgRows               BIGINT       NULL,
        DeletedRows           BIGINT       NULL,
        SizeinBytes           BIGINT       NULL,
        FragmentationPct      DECIMAL(9,4) NULL)
	WITH (HEAP, DISTRIBUTION=ROUND_ROBIN)"

    Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Database $DBA_DBName -Username $username -Password $password


    $SQLQuery = "
SELECT COALESCE(MAX(RunID), 0) AS MaxRunID FROM CCI_Health" 
    $rset_RunID = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Database $DBA_DBName -Username $username -Password $password
    $RunID = $rset_RunID.MaxRunID
    $RunID += 1

    $SQLQuery = "INSERT CCI_Health (RunID, RunDateTime, DBName) VALUES ($RunID, '$RunDateTime', '$database');" 
    Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Database $DBA_DBName -Username $username -Password $password

    return $RunID

  }
  
function Delete-ProcessStart ($RunDateTime, $RunID)
  {
 
    $SQLQuery = "
DELETE CCI_Health
WHERE RunID= $RunID
  AND RunDateTime = '$RunDateTime'
  AND NodeName IS NULL"

    Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Database $DBA_DBName -Username $username -Password $password

  }

function Write-CCIHealthSummaryToDB ($DBA_DBName, $dbname, $MappedTableHash, $CMPNodeCCIHealth, $RunDateTime, $RunID)
  {
# Writing the data row-by-row is slow, ata round 4.25 rows / sec.
# BCP would be used instead, with the CSV export file used as the source. BUT, inconsistencies have been identified with BCP
# based on the upgrade path (from AU5 or earlier bare-metal install or from AU6 bare-metal install).
# DWLoader is used to import the data, with the CSV export file used as the source,
    Write-Host "Writing data to $DBA_DBName." -ForegroundColor Cyan

    #DWLoader Command:
    #DWLoader.exe -i $OutputFileCSV -U $username -P $password -S $CTLNode -T $DBA_DBName.dbo.CCI_Health -fh 1 -t "," -s 0x22 -r 0x0d0x0a -R $RejectFile 
    $Inputfile = "-i"
    $User = "-U"
    $Pswd = "-P"
    $Server = "-S"
    $Table = "-T"
    $TableName = "$DBA_DBName.dbo.CCI_Health"
    $HdrLines = "-fh"
    $HdrLinesNum = "1"
    $DelimField = "-t"
    $DelimFieldVal = "`",`""
    $DelimString = "-s"
    $DelimStringVal = "0x22"
    $DelimRow = "-r"
    $DelimRowVal = "0x0d0x0a"
    $Reject = "-R"
    $RejectFile = $OutputFileCSV.Replace(".csv", "-DWLoader-Reject.log")
    $DWLParms = $Inputfile, $OutputFileCSV, $User, $username, $Pswd, $password, $Server, $CTLNode, $Table, $TableName, $HdrLines, $HdrLinesNum, $DelimField, $DelimFieldVal, $DelimString, $DelimStringVal, $DelimRow, $DelimRowVal, $Reject, $RejectFile
    & DWLoader.exe $DWLParms
    
  }

function Write-CCIHealthSummaryToFile ($dbname, $MappedTableList, $CMPNodeCCIHealth, $RunID, $RunDateTime)
  {

      Write-Host "Writing data to $OutputFileCSV." -ForegroundColor Cyan

    $tblCCIHealth = New-Object system.Data.DataTable "CCIHealth"
    $colRunID = New-Object system.Data.DataColumn RunID,([string])
    $colRunDateTime = New-Object system.Data.DataColumn RunDateTime,([string])
    $colNodeName = New-Object system.Data.DataColumn NodeName,([string])
    $colDBName = New-Object system.Data.DataColumn DBName,([string])
    $colTableName = New-Object system.Data.DataColumn TableName,([string]) 
    $colM_DBName = New-Object system.Data.DataColumn M_DBName,([string]) 
    $colM_TableName = New-Object system.Data.DataColumn M_TableName,([string]) 
    $colM_IndexName = New-Object system.Data.DataColumn M_IndexName,([string]) 
    $colRG_State = New-Object system.Data.DataColumn RG_State,([string])
    $colRG_State_Desc = New-Object system.Data.DataColumn RG_State_Desc,([string]) 
    $colRG_Count = New-Object system.Data.DataColumn RG_Count,([string])
    $colTrim_Reason = New-Object system.Data.DataColumn Trim_Reason,([string])
    $colTrim_Reason_Desc = New-Object system.Data.DataColumn Trim_Reason_Desc,([string]) 
    $colTotalRows = New-Object system.Data.DataColumn TotalRows,([string]) 
    $colMinRows = New-Object system.Data.DataColumn MinRows,([string]) 
    $colMaxRows = New-Object system.Data.DataColumn MaxRows,([string]) 
    $colAvgRows = New-Object system.Data.DataColumn AvgRows,([string]) 
    $colDeletedRows = New-Object system.Data.DataColumn DeletedRows,([string]) 
    $colSizeinBytes = New-Object system.Data.DataColumn SizeinBytes,([string]) 
    $colFragmentationPct = New-Object system.Data.DataColumn FragmentationPct,([string]) 
    $tblCCIHealth.columns.add($colRunID)
    $tblCCIHealth.columns.add($colRunDateTime)
    $tblCCIHealth.columns.add($colNodeName)
    $tblCCIHealth.columns.add($colDBName)
    $tblCCIHealth.columns.add($colTableName)
    $tblCCIHealth.columns.add($colM_DBName)
    $tblCCIHealth.columns.add($colM_TableName)
    $tblCCIHealth.columns.add($colM_IndexName)
    $tblCCIHealth.columns.add($colRG_State)
    $tblCCIHealth.columns.add($colRG_State_Desc)
    $tblCCIHealth.columns.add($colRG_Count)
    $tblCCIHealth.columns.add($colTrim_Reason)
    $tblCCIHealth.columns.add($colTrim_Reason_Desc)
    $tblCCIHealth.columns.add($colTotalRows)
    $tblCCIHealth.columns.add($colMinRows)
    $tblCCIHealth.columns.add($colMaxRows)
    $tblCCIHealth.columns.add($colAvgRows)
    $tblCCIHealth.columns.add($colDeletedRows)
    $tblCCIHealth.columns.add($colSizeinBytes)
    $tblCCIHealth.columns.add($colFragmentationPct)

    foreach ($row in $CMPNodeCCIHealth)
      {
        if ($row.State -match '^\d+$') {        
            $NodeName=[String]$row.Node        
            $MDBName=[String]$row.M_DBName
            $MTblName=[String]$row.M_TableName
            $MIDXName=[String]$row.M_IndexName
            $State=[int]$row.State
            $StateDesc=[String]$row.State_Desc
            $RGCount=[int]$row.RGCount
            try {
                $TrimReason=[int]$row.TrimReason
              }
            catch {
                $TrimReason=""
              }
            $TrimReasonDesc=[String]$row.TrimReason_Desc
            try {
                $TotRows=[int64]$row.TotRows 
              }
            catch {
                $TotRows=""
              }
            try {
                $MinRows=[int64]$row.MinRows
              }
            catch {
                $MinRows=""
              }
            try {
                $MaxRows=[int64]$row.MaxRows
              }
            catch {
                $MaxRows=""
              }
            try {
                $AvgRows=[int64]$row.AvgRows
              }
            catch {
                $AvgRows=""
              }
            try {
                $DelRows=[int64]$row.DelRows
              }
            catch {
                $DelRows=""
              }
            $SizeInBytes=[int64]$row.SizeInBytes
        
             try {
                $FragPct=[decimal]$row.FragmentationPct
              }
            catch {
                $FragPct=""
              }
            $TblName = [string]$MappedTableHash.item($MTblName)

            $NewRow = $tblCCIHealth.NewRow()
            $NewRow.RunID = $RunID
            $NewRow.RunDateTime = $RunDateTime
            $NewRow.NodeName = $NodeName
            $NewRow.DBName = $dbname
            $NewRow.TableName = $TblName
            $NewRow.M_DBName = $MDBName
            $NewRow.M_TableName = $MTblName
            $NewRow.M_IndexName = $MIDXName
            $NewRow.RG_State = $State
            $NewRow.RG_State_Desc = $StateDesc
            $NewRow.RG_Count = $RGCount
            $NewRow.Trim_Reason = $TrimReason
            $NewRow.Trim_Reason_Desc = $TrimReasonDesc
            $NewRow.TotalRows = $TotRows
            $NewRow.MinRows = $MinRows
            $NewRow.MaxRows = $MaxRows
            $NewRow.AvgRows = $AvgRows
            $NewRow.DeletedRows = $DelRows
            $NewRow.SizeinBytes = $SizeInBytes
            $NewRow.FragmentationPct = $FragPct 
            $tblCCIHealth.Rows.Add($NewRow)
          }
      }

    
    $tblCCIHealth | Export-Csv $OutputFileCSV -NoTypeInformation 

  }


function Main
  {

    LoadSqlPowerShell

    $RunDateTime = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    $ProcessStartTime = Get-Date
    $TaskStartTime = Get-Date

    if ($DBA_DBName -ne "") {
        $RunID = Write-ProcessStart $RunDateTime $database
      }
    
    $MappedDBName = Get-CTL01MappedDatabaseName $database

    if ($MappedDBName -eq $null) {
        Write-EventLog -Source $source -logname "ADU" -EventID 9911 -EntryType Error -message "Running CCI_Health.ps1, Database $database not found"
        return
      }

    Write-EventLog -Source $source -logname "ADU" -EventID 9904 -EntryType Information -message "Running CCI_Health.ps1 at $RunDateTime for database $database"

	$MappedTableList = @{}
	$MappedTableList = Get-CTL01MappedTableList $database 
    $MappedTableHash=@{}
    foreach ($MappedTable in $MappedTableList)
      {
        $MappedTableHash.Add($MappedTable.Mapped_Table, $MappedTable.UserTable)
      }

    $CMPNodeCCIHealth = Get-CMPCCIHealth $database $MappedDBName

    $TaskElapsed = (Get-Date) - $TaskStartTime
    $Elapsed = $TaskElapsed -f "#"
    Write-EventLog -Source $source -logname "ADU" -EventID 9905 -EntryType Information -message "CCI_Health.ps1 for database $database. Data retrieval completed, elapsed time $Elapsed"
    $TaskStartTime = Get-Date

    Write-CCIHealthSummaryToFile $database $MappedTableHash $CMPNodeCCIHealth $RunID $RunDateTime
    $TaskElapsed = (Get-Date) - $TaskStartTime
    $Elapsed = $TaskElapsed -f "#"
    Write-EventLog -Source $source -logname "ADU" -EventID 9908 -EntryType Information -message "CCI_Health.ps1 for database $database. Data written to CSV, elapsed time $Elapsed"
    $TaskStartTime = Get-Date

    if ($DBA_DBName -ne "") {
        Write-CCIHealthSummaryToDB $DBA_DBName $database $MappedTableHash $CMPNodeCCIHealth $RunDateTime $RunID

        Delete-ProcessStart $RunDateTime $RunID
        $TaskElapsed = (Get-Date) - $TaskStartTime
        $Elapsed = $TaskElapsed -f "#"
        Write-EventLog -Source $source -logname "ADU" -EventID 9909 -EntryType Information -message "CCI_Health.ps1 for database $database. Data written to DB $DBA_DBName, elapsed time $Elapsed"
        $TaskStartTime = Get-Date
      }


    $ProcessElapsed = (Get-Date) - $ProcessStartTime
    $Elapsed = $ProcessElapsed -f "#"
    Write-EventLog -Source $source -logname "ADU" -EventID 9910 -EntryType Information -message "CCI_Health.ps1 for database $database. Process completed elapsed time $Elapsed"

  }

  Main

