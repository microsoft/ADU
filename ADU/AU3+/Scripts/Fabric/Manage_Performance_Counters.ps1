#* FileName: PDWPerfCounters.ps1
#*=============================================
#* Script Name: PDWPerfCounters.ps1
#* Created: [1/6/2013]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*
#* Keywords:
#*=============================================
#* Purpose: Manage default PDW perf counters
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Date: [DATE_MDY]
#* Time: [TIME]
#* Issue:
#* Solution:
#*
#*=============================================
. $rootPath\Functions\ADU_Utils.ps1
. $rootPath\Functions\PdwFunctions.ps1

function PdwPerfCounters
{
    $ErrorActionPreference = "stop" #So that we can trap errors
    $WarningPreference = "inquire"
    $source = $MyInvocation.MyCommand.Name #Set Source to scriptname
    New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
    Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Starting $source"

	#get a nodelist
    try
    {
	    $physNodeList = GetNodeList -fqdn -phys
	    $pdwNodeList = GetNodeList -fqdn -pdw
	    $fullNodeList = GetNodeList -fqdn -full 
	    $CtlNodeList = $pdwNodeList | Select-String "-CTL"
	    $cmpNodeList = $pdwNodeList | Select-String "-CMP"
    }
    catch
    {
        write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Error Creating Nodelists... Exiting `n`n $_.fullyqualifiedErrorID `n`n $_.exception"
        Write-Error "Failed to retrieve a node list using the get NodeList funtion"
    }

    do
	{
		$MenuOptions = @()
		$MenuOptions = (
			 "Check Performance Counter State",
			 "Create Default PDW Performance Counters Collector Set",
			 "Remove Default PDW Performance Counters Collector Set",
			 "Start Default PDW Performance Counters",
			 "Stop Default PDW Performance Counters",
			 "Collect Performance Counter Data"
			 )
		
		#get the user input and run the proper function
		[string]$userInput = OutputMenu -options $MenuOptions -header "Performance Counters"
		if ($userInput -eq "q"){return}

		Switch($userInput)
		{
			"Check Performance Counter State"
			{
                Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Checking Perf Counter State on all nodes"
				try
				{
					CheckPerfCounterState $fullNodeList
				}
				catch
				{
					write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Error checking perf counter set on nodes `n`n $_.exception"
                    write-Error -ErrorAction Continue "`nError encountered  while creating perf counters on nodes... see log for details"
				}
			}
			"Create Default PDW Performance Counters Collector Set"
			{
                Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Creating Perf Counter set on nodes"
                try
                {
				    CreatePerfCounterSet -nodeList $CtlNodeList -PdwCtlCounters
				    CreatePerfCounterSet -nodeList $cmpNodeList -PdwCmpCounters
				    CreatePerfCounterSet -nodeList $physNodeList -PdwHstCounters
                }
                catch
                {
                    write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Error creating perf counter set on nodes`n`n $_.exception"
                    write-Error -ErrorAction Continue "`nError encountered  while creating perf counters on nodes... see log for details"
                }
			}
			"Remove Default PDW Performance Counters Collector Set"
			{
                Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Removing Perf counter set from nodes"
                try
                {
				    RemovePerfCounterSet -nodeList $CtlNodeList -PdwCtlCounters
				    RemovePerfCounterSet -nodeList $cmpNodeList -PdwCmpCounters
				    RemovePerfCounterSet -nodeList $physNodeList -PdwHstCounters
                }
                catch
                {
                    write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Error removing perf counter set from nodes  `n`n $_.exception"
                    write-Error -ErrorAction Continue "`nError encountered removing perf counters from nodes... see log for details"
                }
			}
			"Start Default PDW Performance Counters"
			{
                Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Enabling perf counters on nodes"
                try
                {
				    StartPerfCounters -nodeList $CtlNodeList -PdwCtlCounters
				    StartPerfCounters -nodeList $cmpNodeList -PdwCmpCounters
				    StartPerfCounters -nodeList $physNodeList -PdwHstCounters
                }
                catch
                {
                 	write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Error encountered enabling perf counters on nodes `n`n $_.exception"
                    write-Error -ErrorAction Continue "`nError encountered enabling perf counters on nodes... see log for details"
                }
			}
			"Stop Default PDW Performance Counters"
			{
                Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Disabling perf counters on nodes"
                try
                {
				    StopPerfCounters -nodeList $CtlNodeList -PdwCtlCounters
				    StopPerfCounters -nodeList $cmpNodeList -PdwCmpCounters
				    StopPerfCounters -nodeList $physNodeList -PdwHstCounters
                }
                catch
                {
                    write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Error encountered disabling perf counters on nodes `n`n $_.exception"
                    write-Error -ErrorAction Continue "`nError encountered disabling perf counters on nodes... see log for details"
                }
			}
			"Collect Performance Counter Data"
			{
                Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Disabling perf counters on nodes"
                try
                {
				    CollectPerfCounters -nodeList $fullNodeList
                }
                catch
                {
                    write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Error encountered while collecting perf counter files `n`n $_.exception"
                    write-Error -ErrorAction Continue "Error encountered while collecting perf counter files... see log for details"
                }
			}
			default{Write-Error -ErrorAction Continue "Option Not Found"}
		}
	}while ($true)
}

#returns the Perf counters running on all of the nodes
function CheckPerfCounterState
{
	Param($nodeList=$null)
	#need to check all nodes
	
	foreach ($server in $nodeList)
	{
		Write-Host -ForegroundColor Cyan "`n$Server"
		Invoke-Command -ComputerName $server -ScriptBlock {Logman query}
	}
}

#creates perf counter sets for 
Function CreatePerfCounterSet
{
	Param([switch]$PdwCtlCounters,[switch]$PdwCmpCounters,[switch]$PdwHSTCounters,$nodelist=$null)
	
	if ($PdwCtlCounters)
	{
		$command = {logman create counter PdwCtlCounters -ow -f bincirc -max 200 -si 15 -c "\MppServer Event Listeners(loaderbackuppersistedtablelistener)\ListenerLocalQueueCounter" "\Process(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\ProcessorPerformance(*)\*" "\Memory(*)\*" "\System(*)\*" "\Server(*)\*" "\TCPv4(*)\*" "\.NET CLR Memory(sqldwdms)\*" "\Process(sqldwdms)\*" "\Process(sqlservr)\*" "\.NET CLR Memory(sqldweng)\*" "\Process(sqldweng)\*" "\Network Interface(*)\*"}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwCmpCounters)
	{
		$command = {logman create counter PdwCmpCounters -ow -f bincirc -max 200 -si 15 -c "\Process(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\ProcessorPerformance(*)\*" "\Memory(*)\*" "\System(*)\*" "\Server(*)\*" "\TCPv4(*)\*" "\.NET CLR Memory(sqldwdms)\*" "\Process(sqldwdms)\*" "\Process(sqlservr)\*" "\Network Interface(*)\*"}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwHSTCounters)
	{
		$command = {logman create counter PdwHstCounters -ow -f bincirc -max 200 -si 15 -c "\Process(*)\*" "\PhysicalDisk(*)\*" "\Processor(*)\*" "\ProcessorPerformance(*)\*" "\Memory(*)\*" "\System(*)\*" "\Server(*)\*" "\TCPv4(*)\*" "\Network Interface(*)\*" "\Hyper-V Virtual Switch Port(*)\*"}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
}

Function RemovePerfCounterSet
{
	Param([switch]$PdwCtlCounters,[switch]$PdwCmpCounters,[switch]$PdwHSTCounters,$nodelist=$null)
	
	if ($PdwCtlCounters)
	{
		$command = {logman delete PdwCtlCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwCmpCounters)
	{
		$command = {logman delete PdwCmpCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwHSTCounters)
	{
		$command = {logman delete PdwHstCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
}

Function StartPerfCounters
{
	Param([switch]$PdwCtlCounters,[switch]$PdwCmpCounters,[switch]$PdwHSTCounters,$nodelist=$null)
	
	if ($PdwCtlCounters)
	{
		$command = {logman start PdwCtlCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwCmpCounters)
	{
		$command = {logman start PdwCmpCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwHSTCounters)
	{
		$command = {logman start PdwHstCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
}

Function StopPerfCounters
{
	Param([switch]$PdwCtlCounters,[switch]$PdwCmpCounters,[switch]$PdwHSTCounters,$nodelist=$null)
	if ($PdwCtlCounters)
	{
		$command = {logman stop PdwCtlCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwCmpCounters)
	{
		$command = {logman stop PdwCmpCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
	
	if ($PdwHSTCounters)
	{
		$command = {logman stop PdwHstCounters}
		foreach ($node in $nodeList)
		{
			Write-Host -ForegroundColor Cyan "`n$node"
			Invoke-Command -ComputerName $node -ScriptBlock $command
		}
	}
}

Function CollectPerfCounters
{	
	param($nodeList=$null)
	#Still just a test, but this works
	$date = get-date -f yyyy-MM-dd_hhmmss
	
	CollectFiles -nodelist $nodeList -filepath "PerfLogs\*" -outputDir "D:\PdwDiagnostics\PDWPerflogs\Perflogs_$date" -days 3
	
	Write-Host -ForegroundColor Cyan "Perf Logs copied to D:\PdwDiagnostics\Perflogs_$date"
}
. PdwPerfCounters


