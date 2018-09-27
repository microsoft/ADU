#* FileName: FixWmiLeak.ps1
#*=============================================
#* Script Name: FixWmiLeak.ps1
#* Created: [1/3/2014]
#* Author: Kristine Lange, Nick Salch
#* Company: Microsoft
#* Email: Krlange@microsoft.com
#* Reqrmnts:
#*	Must be Pdw domain admin
#* Keywords:
#*=============================================
#* Purpose: Will check all physical nodes for too much  
#*	memory use on WMIPRVSE and ask if you want to restart it
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Date: [1/21/2014]
#* Time: [TIME]
#* Issue: No logging	
#* Solution: Implemented logging in the event log
#*
#*=============================================
. $rootpath\Functions\PdwFunctions.ps1

$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire"
$source = $MyInvocation.MyCommand.Name #Set Source to scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Starting $source" 

#get list of physical nodes
try
{
    $nodelist = getNodeList -phys
    $FabDom = $nodelist.split("-")[0]
}
catch
{
    write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Failed to Generate Nodelist `n`n $_.fullyqualifiedErrorID `n`n $_.exception"
    Write-Error "Failed to retrieve a node list using the get NodeList function"
}

$CheckWmi = {Get-Process -Name wmiprvse | Where-Object {($_.PrivateMemorySize -gt 350000000) -or ($_.handleCount -gt 4000)} | ft Name,@{label="Private Mem(MB)";Expression={[math]::truncate($_.privatememorysize / 1mb)}},Handlecount -AutoSize}

#create a list for nodes that have an issue
$BadNodeList=@()

Write-Host "`nChecking physical nodes for WMI processes near 500mb or 4096 handles..."
foreach ($node in $nodelist)
{
    Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Running CheckWmi command on $node"
	
	Write-Host -Nonewline $node
    try
    {
	    $output = Invoke-Command -ComputerName "$node.$FabDom.fab.local" -ScriptBlock $CheckWmi
    }
    catch
    {
        write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Failed to run CheckWMI on $node `n`n $_.fullyqualifiedErrorID `n`n $_.exception"
        Write-Warning "`nCheck WMI on $node failed with following message: $_"
    }

	if($output)
	{
	    $BadNodeList +=$node
        write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Warning -Message "Offending process found on $node `n`n $output"
		Write-Host -ForegroundColor Red -BackgroundColor Black " Offending process found! "
		$output
	}
	Else{Write-Host -ForegroundColor Green " OK"}
}

if ($BadNodeList)
{
	Write-Host -ForegroundColor Cyan "`nWMI processes near 500mb or 4096 handles on the following nodes: $badNodeList"
	$userInput = Read-Host "Would you like to auto-repair for these servers (recommended)? (Y/N)"
	
	if($userInput -eq "Y")
	{
		$RestartWMI = {Get-Process -Name wmiprvse | Where-Object {($_.PrivateMemorySize -gt 350000000) -or ($_.handleCount -gt 4000)} | Stop-Process -Force}
		foreach( $node in $BadNodeList)
		{
            Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Killing WMIPRVSE process on $node"
			
            try
            {
			    Invoke-Command -ComputerName "$node.$FabDom.fab.local" -ScriptBlock $RestartWMI
            }
            catch
            {
                write-eventlog -Source $source -LogName ADU -EventId 9999 -entrytype Error -Message "Failed to kill WMI process on $node `n`n $_.fullyqualifiedErrorID `n`n $_.exception"
                Write-error "Failed to kill WMI on $node... Exiting"
            }
		}
	}
}
else
{
    Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "***No WmiPrvSE Processes near 500mb working set found***"
	Write-Host -ForegroundColor Green "`n`n***No WmiPrvSE Processes near 500mb or 4096 handles found***"
}