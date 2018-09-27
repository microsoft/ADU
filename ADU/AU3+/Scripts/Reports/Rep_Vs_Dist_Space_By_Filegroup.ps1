#* FileName: ReplicatedTableSize.ps1
#*=============================================
#* Script Name: ReplicatedTableSize.ps1
#* Created: [1/31/2014]
#* Author: Vic Hermosillo
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	Cluster must be up
#* 
#* Keywords:
#*=============================================
#* Purpose: Test replicated table size details
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================

#*=============================================

param([string]$username,[string]$password)

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
        $PdwCmpNodeList = GetNodeList -cmp
		$PDWHOST = GetNodeList -ctl
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFileCsv = "D:\PDWDiagnostics\TableHealth\SpaceReportByFilegroup_$CurrTime.csv"

		if (!(test-path "D:\PDWDiagnostics\TableHealth"))
			{
				New-item "D:\PDWDiagnostics\TableHealth" -ItemType Dir | Out-Null
			}

	    if(!$username)
			{   $username = GetPdwUsername; $password = GetPdwPassword }

	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}

if (!(CheckPdwCredentials -U $username -P $password))
{

    write-error "failed to validate credentials"
}


Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell


try
	{
        $DbMappingsQuery = "select a.database_id, a.name, b.physical_name from sys.databases as a, sys.pdw_database_mappings as b
where a.database_id = b.database_id"
    
        $DbMappings = ExecutePdwQuery -U $username -P $password -port 17001 -PdwQuery $DbMappingsQuery

#variable to store the full results of the query
$SpaceQueryResults=@()
$i=0
$mapCount = $dbmappings.count

Write-Host "`nGathering information from compute node SQL Instances...`n"


foreach ($dblisting in $DbMappings)
{
     #for the progress bar
     $i++   

		$SpaceQuery = "USE $($dblisting.physical_name);SELECT f.name AS [File Name] , f.physical_name AS [Physical Name], 
CAST((f.size/128.0) AS DECIMAL(15,2)) AS [Total Size in MB],
CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS DECIMAL(15,2)) 
AS [Available Space In MB], [file_id], fg.name AS [Filegroup Name]
FROM sys.database_files AS f WITH (NOLOCK) 
LEFT OUTER JOIN sys.data_spaces AS fg WITH (NOLOCK) 
ON f.data_space_id = fg.data_space_id OPTION (RECOMPILE);"


    foreach ($node in $PdwCmpNodeList)
    {
        #put in a progress bar
        [int]$percentComplete = ($i/$mapCount)*100
        Write-Progress -Activity "Looping through databases on all compute nodes" -Status "$percentComplete Percent Complete" -PercentComplete $percentComplete

        try
        {
        
        $SingleResult = ExecuteSqlQuery -node $node -query $SpaceQuery

        $SingleResult | Add-Member NoteProperty -Name DatabaseName -value $dblisting.name
        $SingleResult | Add-Member NoteProperty -Name Node -value $node

        $SpaceQueryResults += $SingleResult
        
        }
        catch
        {
            write-host -ForegroundColor red -BackgroundColor Black "$node $($dblisting.physical_name) $($dblisting.name) Failed $_"
        }
    }
}
$SpaceQueryResults | export-csv -Path $OutputFileCsv -NoTypeInformation

	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed on function `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed on GetSpaceReport function... Exiting" #Writing an error and exit
	}

Write-host "`nOutput saved to $OutputFileCsv`n"
