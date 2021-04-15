#* FileName: TableSkew.ps1
#*=============================================
#* Script Name: TableSkew.ps1
#* Created: [2/4/2014]
#* Author: Vic Hermosillo
#* Company: Microsoft
#* Email: vihermos@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: Table Skew 
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 3/5/2014
#* Changes:
#* 1. Event logging
#* 2. Error handling
#* 3. Column data table format for output
#* Modified: 3/6/2014
#* Changes:
#* 1. Improved error handling
#* Modified: 7/31/2015 timsalch
#* Changes:
#* 1. Added support for user schemas
#* Modified: 6/16/2016 sfacer
#* Changes:
#* 1. Added [] delimiters to the table name, and escaped "s to the command for the DBCC PDW_SHOWSPACEUSED command.
#	Allows for tables with special characters or spaces in the name
#* Modified: 05/31/2016 sfacer
#* Changes:
#* 1. Modified code to set '[]' delimiters properly, to correct handling '.'s in the Table Name
#* Modified: 12/18/2017 sfacer
#* Changes:
#* 1. Added 'IF EXISTS ...' conditional code to DBCC PDW_SHOWSPACEUSED call
#*    to handle scenario where the table dropped before the PDW_SHOWSPACEUSED query is run
#* Modified: 02/20/2018 sfacer
#* Changes:
#* 1. Exclude databases being restored.
#* Modified: 10/04/2018 sfacer
#* Changes
#* 1. Changed login failure error handling
#* Modified: 06/01/2020 sfacer
#* Changes
#* 1. Added Progress display 
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
		$PDWHOST = GetNodeList -ctl
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFile = "D:\PDWDiagnostics\TableHealth\TableSkewReport_$CurrTime.txt"
		$OutputFileCSV = "D:\PDWDiagnostics\TableHealth\TableSkewReport_$CurrTime.csv"
		$OutputFileHTML = "D:\PDWDiagnostics\TableHealth\TableSkewReport_$CurrTime.html"
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

Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

#* Functions
function GetTableSkew ()
	{
		$tableskew = @()
		#* Loop through DB's
		foreach ($db in $databases) 
			{
                ##########################
                #outer progress bar code
                #must set $outerLCV to 0 outside outer loop
                $innerLCV = 0
                [int64]$percentComplete = ($outerLCV/$($databases.count))*100
                Write-Progress -Activity "Looping through databases (Table Skew)" -Status "$percentComplete Percent Complete" -PercentComplete $percentComplete
                $outerLCV++
                ##########################
				Write-Host -ForegroundColor Cyan "Gathering data for DB: $db"
				try
					{                           
						#* Collect table details
						$tbls = Invoke-Sqlcmd -QueryTimeout 0 -Query "use $db; SELECT '[' + sc.name + '].[' + ta.name + ']' as TableName FROM sys.tables ta join sys.schemas sc on ta.schema_id = sc.schema_id;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
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

                        ########################
                        #Inner progress bar code
                        #must set $innerLCV to 0 outside inner loop, but inside outer loop.
                        if ($($tbls.tablename.count) -eq 0)
                        {
                            "Found 0 tables"
							[int64]$innerPercentComplete=100
                        }
                        else
                        {
					        [int64]$innerPercentComplete = ($innerLCV/$($tbls.tablename.count))*100
                        }

                         Write-Progress -id 1 -Activity "Looping through tables in $db" -Status "$innerPercentComplete Percent Complete" -PercentComplete $innerPercentComplete
                         $innerLCV++
                        ########################

						# Variables
						[long]$totalDataSpace=0
						[long]$totalRows=0 
						$MaxSize=$null
						$MinSize=$null
						$SkewPct=0
				
									
						# Add databaseName and tableName to the DataSkewTable
						$row = $tableDataSkew.NewRow()
						$row.databaseName = $db
						$row.tableName = $tbl
						
                        try
                          {
                            ##$results = Invoke-Sqlcmd -querytimeout 0 -Query "use $db; DBCC PDW_SHOWSPACEUSED (`"$tbl`");" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
			    $Cmd = "use $db; IF EXISTS (SELECT x.* FROM (SELECT '[' + s.[name] + '].[' + o.[name] + ']' AS fqtn FROM SYS.Objects o INNER JOIN sys.schemas s ON o.[schema_id] = s.[schema_id]) AS x WHERE x.fqtn = '$tbl' ) DBCC PDW_SHOWSPACEUSED (`"$tbl`")"
			    ##Write-Host $Cmd -ForegroundColor Cyan
                            $results = Invoke-Sqlcmd -Query $Cmd -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD #-ErrorAction SilentlyContinue
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
				   
					
						# Red if skew pct is greater than 20
						if ($SkewPct -ge 20)
							{
								#Write-Host -ForegroundColor Red "Skew Percentage:" $SkewPct "% -Failed"
								#Write-Host "$db `t$tbl `t$SkewPct `t$MinSize `t$MaxSize `t$totalRows `t$totalDataSpace" |ft
								#"Skew Percentage: $SkewPct % -Failed" |out-file -append $OutputFile							
							}
						else
							{
								#Write-Host "$db `t$tbl `t$SkewPct `t$MinSize `t$MaxSize `t$totalRows `t$totalDataSpace" |ft
								#"Skew Percentage: $SkewPct %" |out-file -append $OutputFile							
							}


						$row.skewPct = [System.Math]::Round($SkewPct,2)
						$row.minValue = $MinSize
						$row.maxValue = $MaxSize
						$row.totalRows = $totalRows
						$row.totalSpace = [System.Math]::Round($totalDataSpace / 1024,2)
						

						#write-host "`t$db `t$tbl `t$MinSize `t$MaxSize `t$totalRows `t$totalDataSpace"
						#"Minimum Value: $MinSize" |out-file -append $OutputFile
						#Write-Host "Maximum Value:" $MaxSize
						#"Maximum Value: $MaxSize" |out-file -append $OutputFile
						#Write-Host "Total Rows:" $totalRows
						#"Total Rows: $totalRows" |out-file -append $OutputFile
						#Write-Host "Total Data Space:" $totalDataSpace
						#"Total Data Space: $totalDataSpace" |out-file -append $OutputFile
						#" " |out-file -append $OutputFile
						
						$tableDataSkew.Rows.Add($row)
				}     
                Write-Progress -id 1 -Activity "Looping through tables in $db" -Completed   
						
				#$tableDataSkew |ft databaseName, tableName, skewPct, minValue, maxValue, totalRows, totalSpace -auto
				#$tableDataSkew | ft -Property databaseName, @{label = "Table Name" ; Expression = { if ($_.tableName -eq "customer") { $Host.ui.rawui.ForegroundColor = "red" ; $_.tableName; $Host.ui.rawui.ForegroundColor = "white" } ELSE { $Host.ui.rawui.foregroundcolor = "white" ; $_.tableName }}}, skewPct, minValue, maxValue, totalRows, totalSpace -auto
				try
					{
						#$tableDataSkew |sort-object skewPct -descending | ft -auto
						$tableDataSkew |sort-object skewPct -descending | ft -auto `
							@{label = "DatabaseName" ; Expression = {$_.databasename}},`
							@{label = "TableName" ; Expression = {$_.tablename}},`
							@{label = "SkewPct" ; Expression = {$_.skewPct}},`
							@{label = "MinNumberRows" ; Expression = {$_.minValue}},`
							@{label = "MaxNumberRows" ; Expression = {$_.maxValue}},`
							@{label = "TotalNumRows" ; Expression = {$_.totalRows}},`
							@{label = "DataSpaceGBs" ; Expression = {$_.totalSpace}}
						$tableDataSkew |sort-object skewPct -descending | ft -auto |out-file -append $OutputFile
						$tableskew += $tableDataSkew 
						
						
							
					}
				catch
					{
						Write-Eventlog -entrytype Error -Message "Failed printing tableDataSkew data table `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
						Write-error "Failed printing tableDataSkew data table... Exiting" -ErrorAction Continue #Writing an error and exit
					}
	
			} 
        Write-Progress -Activity "Looping through databases (Table Skew)" -Completed
	
		$date=Get-Date
		$Appliance = (Get-Cluster).name.split("-")[0]

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

		write-host "Building report..."
		#build the body of the HTML
		$body += "<h2>______________________________________________________</h2>"
		if ($tableskew.count -gt 0)
		{
			$body += $tableskew |sort-object skewPct -descending |select databasename,tablename,skewPct,minValue,maxValue,totalRows,totalSpace | ConvertTo-Html -Fragment 
		}
		else
		{
			$body += "No table skew details found."  
		}
		$body += "<h2>______________________________________________________</h2>"
		$body += "<br>"

		# Create HTML using head and body values
		ConvertTo-Html -head $head -PostContent $body -body "<H1> Table Skew Report</H1><H2>Appliance: $Appliance<br>Date: $date</H2>" | out-file $OutputFileHTML
		$tableskew | Export-Csv $OutputFileCSV -NoTypeInformation
		#start $OutputFileHTML

	}

#* Functions End

try
	{
		# Get list of database names
		$dbs = Invoke-Sqlcmd -querytimeout 0 -Query "select name from sys.databases where name not in ('master','tempdb','stagedb', 'mavtdb') AND name NOT IN (select database_name from sys.pdw_loader_backup_runs where operation_type = 'RESTORE' AND end_time IS NULL ) order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to collect details from sys.databases `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to collect details from sys.databases... Exiting" #Writing an error and exit
	}
if (!$database) 
{ 
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

		[string]$ans = OutputMenu -header "Check Table Skew" -options $TableMenuOptions
		if($ans -eq "q"){break}
		

		# if option is All, run table skew script
		if($ans -eq "All DBs") 
			{
				$databases = $dbs.name
				GetTableSkew ($databases)
			}

		else
			{
				$databases = $ans
				GetTableSkew ($databases)
				#$stuff = GetTableSkew ($databases) 
				#$stuff
				
			}
		Write-Host -ForegroundColor Cyan "Output also located at: $OutputFile"
		}while($ans -ne "q")

} 
else 
{ 
			if($database -eq "all") 
			{
				$databases = $dbs.name
				GetTableSkew ($databases)
			}

		else
			{
				$databases = $database
				GetTableSkew ($databases)	
				
			}	
}



