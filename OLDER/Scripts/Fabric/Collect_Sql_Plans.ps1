#* FileName: CollectSqlPlans.ps1
#*=============================================
#* Script Name: CollectSqlPlans.ps1
#* Created: [7/24/2014]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#*=============================================
<# Purpose:  
Collects SQL Plans from all of the CMP SQL Servers
for a given query for troubleshooting purposes
#>
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
<# 
 Date: 
	1. 7/31/14
	2. 7/31/14
 Issue:
 	1. Queries would timeout if they took longer than 30 seconds
	2. SQL plan was cut off if it was long
 Solution:
	1. Added -querytimeout 65536 (max value) to the invoke-sqlcmd
	2. Added -maxCharLength to max value to invoke-sqlcmd for collecting plans
#>
#*=============================================
#future improvements:
# 2. Turn it on and it will collect all SQL plans it sees until you turn it off - arranged by folder

param([string]$QID=$NULL,[string]$username=$null,[string]$password=$null)

#include the functions we need:
. $rootPath\Functions\PdwFunctions.ps1

##Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Check for properly formatted request ID
if ($QID -and ($QID -notlike "QID*"))
{
	#add QID text to beginning of number
	$QID="QID$QID"
	Read-Host "Please confirm the QID is correct: `'$QID`'"
}

try
{
#Get Pdw Domain name (for queries)
$PdwDomain = GetPdwDomainName
}
catch
{	
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error Getting PdwDomain Name from cluster"
	Write-Error "Error Getting PdwDomain Name from cluster `n $_"
}

try
{
	#check for username and password
	if (!$username){$username = GetPdwUsername}
	if (!$password){$password = GetPdwPassword}
	if (!(CheckPdwCredentials -u $username -p $password -pdwDomain $PdwDomain)){Write-Error "Invalid Credentials"}
}
catch
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error setting pdw credentials "
	Write-Error "Error setting pdw credentials `n $_"
}

function CollectSqlPlans
{
	#get the date to name the output folder
	$date = get-date -format MMddyyyy-hhmmss
	$outputDir1 = "c:\PDWDiagnostics\QueryPlans\$date"
	Write-Verbose "Creating Output dir $outputDir1"
	mkdir $outputDir1 -Force | Out-Null
	
	if(!$QID)
	{
		do
		{
			Write-Host -ForegroundColor Cyan "`nWould you like to provide a (R)equest_ID or a (Q)uery file path? (Enter 'R' or 'Q')"
			$IDorPath = read-host
			
			if($IDorPath -notlike "R" -and $IDorPath -notlike "Q")
			{
				Write-Host -ForegroundColor Yellow -BackgroundColor Black "Input not recognized"
				$IDorPath=$null
			}
			
			if($IDorPath -eq "R")
			{
				Write-Host -ForegroundColor Cyan "Please enter the request ID (QIDxxxxxx)"
				$QID = read-host
			}
		}while(!$IDorPath)
	}
	
	if(!$QID)
	{
		#Example queries (for CSSC8A)
		#$testQuery="select count(*) from [nicksalc_sandbox].[dbo].[cciTable]"
		#$testQuery="select a.c_1,b.c_2 from [Nicksalc_Sandbox].[dbo].[distributedTest] as a
		#join [Nicksalc_Sandbox].[dbo].[distributedTest] as b
		#on a.c_2 = b.c_2"
		
		do
		{
			#get the query from the path provided
			try
			{
				$queryPath = Read-Host "`nPlease enter the full path to the .sql file containing the query"
				$testQuery = Get-Content $queryPath
			}
			catch
			{
				Write-Host -ForegroundColor Red "Not able to get query at `'$querypath`', please fix path"
			}
			
		}while (!$testQuery)
		
		try
		{
			#Get the explain plan
			write-host -foregroundcolor cyan "Running PDW Explain..." -NoNewline
			$explain = RunPdwQuery -username $username -password $password -query "Explain $testQuery" 
			$explain.explain > $outputDir1\Explain.xml
		}
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error running Pdw Explain `n $_ "
			Write-Error "Error running Pdw Explain `n $_ "
		}
		#done message for running explain
		Write-Host -ForegroundColor Green " Done"
		
		try
		{
		#create a simple explain file (just for readability)
		[xml]$xml = Get-Content $outputDir1\Explain.xml
		$i=0
		foreach ($DmsStep in $xml.dsql_query.dsql_operations.dsql_operation.operation_type)
		{
		 	"$i $DmsStep" >> $outputDir1\SimpleDmsPlan.txt
			$i++
		}
		}
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error creating simple DMS plan from $outputDir1\Explain.xml `n $_ "
			Write-Error "Error creating simple DMS plan from $outputDir1\Explain.xml `n $_ "			
		}
		
		#run the test query
		Write-Host ""
		$testQuery
		Write-Host -ForegroundColor Cyan "`nThe query above will now be executed, continue? (Y/N)"
		$answer = Read-Host
		if ($answer -notlike "Y")
		{
			return
		}
		else
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "User chose to continue and execute query against PDW: $testQuery"
		}
		try
		{
			Write-Host  -ForegroundColor Cyan "`nRunning query..." -NoNewline
			RunPdwQuery -username $username -password $password -query $testQuery | out-null
		}
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error encountered executing the query: $testQuery `n $_ "
			Write-Error "Error encountered executing the query `n $_ "		
		}
		
		#done message for "running query"
		Write-Host -ForegroundColor Green " Done"
		
		#Find the Request ID of the query we just ran
		$RequestIdQuery = "
		select top 1 request_id from sys.dm_pdw_exec_requests
		where command = `'$testQuery;`'
		order by 'request_id' desc"
		
		try
		{
		#write-host -ForegroundColor Cyan "running request ID Query"
		$requestId = (RunPdwQuery -username $username -password $password -query $RequestIdQuery).request_id
		write-host -nonewline -ForegroundColor Cyan "Request ID: " 
		Write-host "`n$requestID"
		}
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error encountered executing the request ID query: $RequestIdQuery `n $_ "
			Write-Error "Error encountered executing the request ID query: $RequestIdQuery `n $_ "			
		}
	}
	else
	{
		Write-Host -nonewline -ForegroundColor Cyan "Executing tool for request_ID: "
		Write-host "$QID"
		$requestID = $QID
	}
	
	try
	{
		#Find the Node ID's for the nodes in the appliance 
		$cmpNodeQuery="select * from sys.dm_pdw_nodes where [type] = 'COMPUTE' and is_passive = 0;"
		write-verbose "running Cmp Node Query"
		$cmpNodes=RunPdwQuery -username $username -password $password -query $cmpNodeQuery
	}
	catch
	{
		Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error encountered executing the Node ID query: $cmpNodeQuery`n $_ "
		Write-Error "Error encountered executing the Node ID query: $cmpNodeQuery`n $_ "	
	}
	
	foreach ($node in $cmpNodes)
	{
		try
		{
			$CmpTextQuery= "
				select
			  *
			from
			  sys.dm_pdw_dms_workers
			where
			  request_id = '$requestId'
			  and [type] in ('PARALLEL_COPY_READER', 'DIRECT_READER', 'HASH_READER')
			  and pdw_node_id = $($node.pdw_node_id)"

			#Run query to get the CMP text
			$CmpSteps = RunPdwQuery -username $username -password $password -query $CmpTextQuery
			
			if(!$CmpSteps)
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "No CMP Steps found for request ID $requestID, exiting"
				Write-Error "NO CMP STEPS FOUND FOR REQUEST ID: $requestID"
			}
        }
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error encountered executing the cmp text query: $CmpTextQuery`n $_ "
			Write-Error "Error encountered executing the cmp text query: $CmpTextQuery`n $_ "		
		}
		
		Write-Host -nonewline -ForegroundColor Cyan "Finding query steps for: " 
		Write-host "$($node.name)"
		
		Write-Verbose "Outputting CMPSteps to $outputDir1\$($node.name)_ExecutionInfo.csv"
		$CmpSteps | Export-Csv -NoTypeInformation $outputDir1\$($node.name)_ExecutionInfo.csv
		
		foreach ($step in $cmpSteps)
		{
			
			$outputDir2 = "$outputDir1\$requestID\Step$($step.Step_Index)_$($step.type)"
			mkdir $outputDir2 -Force | Out-Null
			
			Write-Verbose "Collecting plan for step:$($node.name)_dist_$($step.distribution_id)"
			
			$CmpQueryText = $step.Source_info
			
			try
			{
				$planQuery = "
				 select p.*, t.[text], qp.query_plan
				from sys.dm_exec_cached_plans p
				cross apply sys.dm_exec_sql_text(p.plan_handle) t
				cross apply sys.dm_exec_query_plan(p.plan_handle) qp
				where
				  t.[text] = `'$CmpQueryText`'
				"
				#write-host "running Plan query against $($node.name) Step $i"		
				$planInfo = ExecuteCmpQuery -query $planQuery -nodeName $node.name
		        $planInfo.query_plan > "$outputDir2\$($node.name)_dist_$($step.distribution_id).sqlplan"
			}
			catch
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error encountered executing the cmp plan query: $planQuery`n $_ "
				Write-Error "Error encountered executing the cmp plan query: $planQuery`n $_ "
			}
		}
	}
	Write-Host -NoNewline -ForegroundColor Cyan "`nOutput Located at: "
	Write-Host "$OutputDir1"
}

function RunPdwQuery
{
	param([string]$query=$null,$username=$null,$password=$null)
	return Invoke-Sqlcmd -ServerInstance "$PdwDomain-CTL01,17001" -Username $username -Password $password -Query $query -QueryTimeout 65534
}

function ExecuteCmpQuery
{
	param([string]$query=$null,[string]$nodeName)
	return Invoke-Sqlcmd -ServerInstance $nodeName -Query $query -MaxCharLength 65536
}

. CollectSqlPlans