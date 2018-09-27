#* FileName: DatabaseSettingReport.ps1
#*=============================================
#* Script Name: DatabaseSettingReport.ps1
#* Created: [12/22/2014]
#* Author: Ryan Stucker
#* Company: Microsoft
#* Email: rystucke@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: Database Settings Report
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
		$PdwDomainName = GetPdwDomainName #For AU.5-AU2
		$PDWHOST = $PdwDomainName + '-CTL01' #For AU.5-AU2
		#$PDWHOST = GetNodeList -ctl #For AU3+
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "c:\PDWDiagnostics\TableHealth\DatabaseSettingReport$CurrTime.txt"
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
		#write-host	"Test 2"


		return $resultsVSQ
	}
	

Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

## Get list of database names
$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master', 'tempdb','stagedb') order by name desc;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD


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

	[string]$ans = OutputMenu -header "Check Database Settings" -options $TableMenuOptions
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
			"Getting Database Setting details for $database" |out-file -append $OutputFile
			
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
					Write-error "Failed on calculating Database details... Exiting" -ErrorAction Stop #Writing an error and exit
				}
<#
	    	try
				{
					# Create a DatabaseSpaceReport
					$tableDatabaseSettingReport = New-Object system.Data.DataTable "DatabaseSettingReport"
					$colReplicated = New-Object system.Data.DataColumn ReplicatedSize,([decimal])
					$colLog = New-Object system.Data.DataColumn LogSize,([decimal])
					$colDistributed = New-Object system.Data.DataColumn DistributedSize,([decimal])
					$colAutoGrow = New-Object system.Data.DataColumn AutoGrow,([string])
					
					$tableDatabaseSpaceReport.columns.add($colReplicated)
					$tableDatabaseSpaceReport.columns.add($colDistributed)
					$tableDatabaseSpaceReport.columns.add($colLog)
					$tableDatabaseSpaceReport.columns.add($colAutoGrow)
					
					$row = $tableDatabaseSpaceReport.NewRow()
					$row.ReplicatedSize = $Repl
					$row.LogSize = $Log
					$row.DistributedSize = $Dist
					$row.AutoGrow = $AutoGrow
					$tableDatabaseSpaceReport.Rows.Add($row)
				}
			catch 
				{
					Write-Eventlog -entrytype Error -Message "Failed on creating tableDatabaseSpaceReport `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed on creating tableDatabaseSpaceReport... Exiting" -ErrorAction Stop #Writing an error and exit
				}
#>			
			try
				{
					#$tableDatabaseSpaceReport |ft databasename, totalApplianceVolumeSpace, totalApplianceFreeSpace, totalDatabaseAllocatedSpace, totalActualSpace, totalAllocatedUnusedSpace -auto
					#$tableDatabaseSpaceReport |ft databasename, totalApplianceVolumeSpace, totalApplianceFreeSpace, totalDatabaseAllocatedSpace, totalActualSpace, totalAllocatedUnusedSpace -auto  |out-file -append $OutputFile
					#$tableDatabaseSpaceReport |ft databasename,  @{label = "Total Appliance Volume Space GBs" ; Expression = {$_.totalApplianceVolumeSpace}}, @{label = "Total Appliance Free Space GBs" ; Expression = {$_.totalApplianceFreeSpace}}, @{label = "Total Database Allocated Space GBs" ; Expression = {$_.totalDatabaseAllocatedSpace}}, @{label = "Total Actual Space GBs" ; Expression = {$_.totalActualSpace}}, @{label = "Total Allocated Unused Space GBs" ; Expression = {$_.totalAllocatedUnusedSpace}} -auto
					#$tableDatabaseSpaceReport |ft databasename,  @{label = "Total Appliance Volume Space GBs" ; Expression = {$_.totalApplianceVolumeSpace}}, @{label = "Total Appliance Free Space GBs" ; Expression = {$_.totalApplianceFreeSpace}}, @{label = "Total Database Allocated Space GBs" ; Expression = {$_.totalDatabaseAllocatedSpace}}, @{label = "Total Actual Space GBs" ; Expression = {$_.totalActualSpace}}, @{label = "Total Allocated Unused Space GBs" ; Expression = {$_.totalAllocatedUnusedSpace}} -auto |out-file -append $OutputFile
				
                   Write-Host "Total Distributed Size: `t$Dist GB's"		
					Write-Host "Total Replicated Size: `t`t$Repl GB's" 
					Write-Host	"Total Log Size: `t`t$Log GB's" 
					Write-Host	"AutoGrow Setting: `t`t$AutoGrow " 
					Write-Host "Original Create Database Command:"
                    Write-Host -ForegroundColor Yellow " `tCreate Database $database with (Replicated_size=$Repl, Distributed_Size=$Dist, Log_Size=$Log, AutoGrow=$AutoGrow);" 
					
					"Total Distributed Size: `t$Dist GB's"	 |out-file -append $OutputFile		
					"Total Replicated Size: `t`t$Repl GB's" |out-file -append $OutputFile	
					"Total Log Size: `t`t$Log GB's" |out-file -append $OutputFile	
					"AutoGrow Setting: `t`t$AutoGrow " |out-file -append $OutputFile	
					"Original Create Database Command: `tCreate Database $database with (Replicated_size=$Repl, Distributed_Size=$Dist, Log_Size=$Log, AutoGrow=$AutoGrow);" |out-file -append $OutputFile	
					
				
				}
			catch
				{
					Write-Eventlog -entrytype Error -Message "Failed on printing the tableDatabaseSpaceReport table `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
					Write-error "Failed on printing the tableDatabaseSpaceReport table... Exiting" -ErrorAction Stop #Writing an error and exit
				}
			
		}
		
		Write-Host -ForegroundColor Cyan "`nOutput also located at: $OutputFile"
		
}while($ans -ne "q")
