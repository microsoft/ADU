#* FileName: TempDB_Space_Report.ps1
#*=============================================
#* Script Name: TempDB_Space_Report.ps1
#* Created: [06/13/2019]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: TempDB Space Report
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
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

try {
    $DBA_DBName = get-content -Path ".\AU3+\Config\DBA_db.txt"
  }
catch {
    Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Running TempDB_Space_Report.ps1, no target DB found, unable to continue - nowhere to write data"
    Write-Host "No target DB found, unable to continue - nowhere to write data" -ForegroundColor DarkRed -BackgroundColor Yellow
    return
  }

#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
	{
		# Domain name and CTL host name
		$CTLNode = GetNodeList -ctl
        $CMPNodes = GetNodeList -cmp
		<# 
        $counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "D:\PDWDiagnostics\Misc\TempDB_Space_Report$CurrTime.txt"
		if (!(test-path "D:\PDWDiagnostics\Misc"))
			{
				New-item "D:\PDWDiagnostics\Misc" -ItemType Dir | Out-Null
			}
		if (!(test-path $OutputFile))
			{
				New-Item $OutputFile -ItemType File|out-null
			} 
        #>

	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}	

## Functions
function TempDBSpace ()
	{
		$SQLQuery = "
IF EXISTS (SELECT * FROM Tempdb..sysobjects where name like '#DBSpaceStats%') 
	DROP TABLE #DBSpaceStats

CREATE TABLE #DBSpaceStats (
			HostName			VARCHAR(32)		NULL,
			DBName				VARCHAR(32)		NULL,
			Data_Size_MB		BIGINT			NULL,
			Data_Used_Pct		DECIMAL(9,4)	NULL,
			Log_Size_MB			BIGINT			NULL,
			Log_Used_Pct		DECIMAL(9,4)	NULL )


USE TempDB

IF EXISTS (SELECT * FROM Tempdb..sysobjects where name like '#ShowFileStats%') 
	DROP TABLE #ShowFileStats

CREATE TABLE [#ShowFileStats] (
            [FileID]            INT NULL, 
            [FileGroup]         INT NULL, 
            [TotalExtents]      BIGINT NULL, 
            [UsedExtents]       BIGINT NULL, 
            [LogicalFileName]   [nvarchar](64) NULL,
            [PhysicalFileName]  [nvarchar](256) NULL)
INSERT #ShowFileStats EXEC ('DBCC SHOWFILESTATS WITH NO_INFOMSGS')

INSERT #DBSpaceStats (HostName, DBName, Data_Size_MB, Data_Used_Pct)
	SELECT  @@ServerName,
			'TempDB',
			(SUM([TotalExtents]) / 16),
			(SUM([UsedExtents]) / SUM([TotalExtents]))
		FROM  #ShowFileStats


USE pdwtempdb1

TRUNCATE TABLE #ShowFileStats

INSERT #ShowFileStats EXEC ('DBCC SHOWFILESTATS WITH NO_INFOMSGS')

INSERT #DBSpaceStats (HostName, DBName, Data_Size_MB, Data_Used_Pct)
	SELECT  @@ServerName,
			'pdwtempdb1',
			(SUM([TotalExtents]) / 16) AS [Data_Size_MB],
			(SUM([UsedExtents]) / SUM([TotalExtents])) AS [Data_Used_Pct]
		FROM  #ShowFileStats


IF EXISTS (SELECT * FROM Tempdb..sysobjects where name like '#LogSpace%') 
	DROP TABLE #LogSpace

CREATE TABLE #LogSpace (
            [DBName]            VARCHAR(255) NULL, 
            [Log_Size_MB]       DECIMAL(9,2) NULL, 
            [Log_Used_Pct]      DECIMAL(9,2) NULL, 
            [Status]            BIT NULL)
INSERT #LogSpace EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS')

UPDATE  #DBSpaceStats
	SET Log_Size_MB = l.Log_Size_MB,
		Log_Used_Pct = l.Log_Used_Pct
FROM #DBSpaceStats s
	INNER JOIN #LogSpace l
		ON s.DBName = l.DBName

SELECT *
 FROM #DBSpaceStats


DROP TABLE #ShowFileStats
DROP TABLE #LogSpace
DROP TABLE #DBSpaceStats
"
		$rset_DBSize = $null
        ForEach ($CMPNode in $CMPNodes) {
		    $rset_DBSize += Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CMPNode" -Database "TempDB"            
		  }

		$SQLQuery = "
IF NOT EXISTS (SELECT * FROM sysobjects where name = 'TempDB_SpaceStats') 
    CREATE TABLE TempDB_SpaceStats (
        CollectionDateTime    DATETIME     NOT NULL,
        NodeName              VARCHAR(16)  NOT NULL,
        DBName                VARCHAR(16)  NOT NULL,
        Data_Size_MB          BIGINT       NOT NULL,
        Data_Used_Pct         DECIMAL(9,4) NOT NULL,
        Log_Size_MB           BIGINT       NOT NULL,
        Log_Used_Pct          DECIMAL(9,4) NOT NULL)"

        Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Database $DBA_DBName -Username $username -Password $password

        $SQLQuery = "INSERT INTO TempDB_SpaceStats`n"

        $CurrDateTime = get-date -Format "MM/dd/yyyy HH:mm:ss"
        
        $Union = ""
        ForEach ($row_DBSize in $rset_DBSize) { 
            $HostName = $row_DBSize.HostName
            $DBName = $row_DBSize.DBName
            $Data_Size_MB = [string]$row_DBSize.Data_Size_MB
            $Data_Used_Pct = [string]$row_DBSize.Data_Used_Pct
            $Log_Size_MB = [string]$row_DBSize.Log_Size_MB
            $Log_Used_Pct = [string]$row_DBSize.Log_Used_Pct
            $SQLQuery += "$Union SELECT '$CurrDateTime', '$HostName', '$DBName', $Data_Size_MB, $Data_Used_Pct, $Log_Size_MB, $Log_Used_Pct "
            $Union = "`nUNION`n"
          }

         Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$CTLNode,17001" -Database $DBA_DBName -Username $username -Password $password

	}

LoadSqlPowerShell

TempDBSpace

