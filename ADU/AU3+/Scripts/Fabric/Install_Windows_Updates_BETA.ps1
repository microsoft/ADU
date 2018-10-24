#Run-OnlineWindowsUpdates
. $rootPath\Functions\PdwFunctions.ps1

Write-Host -ForegroundColor Cyan "
This tool will install Windows Updates on all servers in the appliance. You may run this while the appliance is online, but you will need to take downtime to reboot all of the servers to complete the updates. 

This process is meant to reduce the amount of downtime required to perform Windows Updates. 

Pre-Requisites:
    -WSUS should be configured on the VMM server per the standard CHM insructions
    -Updates should already be approved and downloaded on the WSUS server.
    -You should decline superseded updates in WSUS. Failure to do so will result in more reboot cycles required and longer install times. The Support team has a tool that can do this. It is not part of ADU as of now
"
Read-host "Press Enter to Continue (CTRL-C to exit)"

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

$logPath = "D:\PDWDiagnostics\WindowsUpdate"
If (!(Test-path $logpath)){Mkdir $logPath | out-null}
$date = Get-Date -Format MMddyy-hhmmss


#Set up variables
$fullNodeList = getNodeList -Full
$WsusPath = "C:\Wsus\" #path to store the WU scripts and logs for this tool
$DomainAdminUser = "$(([string]($fullNodeList | select-string "-HST01")).split("-")[0])\Administrator"
$DomainAdminPass = GetDomainPassword

#create c:\wsus on all nodes
Write-host "`nCreating c:\WSUS on all nodes..."
$CreateDirCommand = "if (!(Test-Path $WsusPath)){Mkdir $WsusPath}"
ExecuteDistributedPowerShell -Nodelist $fullNodeList -Command $CreateDirCommand


#copy Install-WindowsUpdates.ps1 to all nodes
Write-host "`nCopying Windows updates install file to all nodes..."
Foreach ($Node in $fullNodeList)
{
    #Copy the install-windowsupdate.ps1 file to all nodes
    Copy-item "$rootPath\Config\Install-WindowsUpdates.ps1" "\\$node\C`$\Wsus\"
}

#Create scheduled task on all nodes
$CheckForScheduledTask = {if (Get-ScheduledTask "InstallWindowsUpdates" -ErrorAction SilentlyContinue) {Unregister-ScheduledTask "InstallWindowsUpdates" -Confirm:$False}}
$CreateScheduleTask = {param($DomainAdminUser,$DomainAdminPass) $action = New-ScheduledTaskAction -Execute 'Powershell.exe'  -Argument '"C:\Wsus\Install-WindowsUpdates.ps1"'
Register-ScheduledTask -Action $action -TaskName "InstallWindowsUpdates" -User $DomainAdminUser -Password $DomainAdminPass}

Write-host "`nCreating scheduled task on all nodes..."
Invoke-Command -ComputerName $fullNodeList -ScriptBlock $CheckForScheduledTask | Out-Null
Invoke-Command -ComputerName $fullNodeList -ScriptBlock $CreateScheduleTask -ArgumentList $DomainAdminUser,$DomainAdminPass| Out-NULL

Write-Host "Installing Windows Updates...`nOverall progress will show after all jobs have been kicked off`nIf Desired, you can check the progress on each node by going to windows update -> View Update History"

#Run all Scheduled tasks
$StartTaskCommand = {Start-ScheduledTask "InstallWindowsUpdates"}
Invoke-Command -ComputerName $fullNodeList -ScriptBlock $StartTaskCommand


#Monitor progress
$CurrentlyRunningNodelist = $fullNodeList
$CompletedNodeList=@()
$checktaskState = {(Get-ScheduledTask InstallWindowsUpdates).state}

Write-Progress -Activity "Currently Installing Updates:" -status "$CurrentlyRunningNodelist " -PercentComplete 0 
Write-progress -Activity "Completed:" -status "$CompletedNodeList " -ID 1

do
{
    foreach ($node in $CurrentlyRunningNodelist)
    {
        TRY
        {
            $state = Invoke-Command $Node -ScriptBlock $checktaskState 
            if ($state.value -ne "Running")
            {
                $CurrentlyRunningNodelist = $CurrentlyRunningNodelist | Select-String -NotMatch "$node"
                $CompletedNodeList += $node
            
                [int]$percentComplete = $CompletedNodeList.count/$fullNodeList.count *100
                Write-Progress -Activity "Currently Installing Updates:" -status "$CurrentlyRunningNodelist " -PercentComplete $percentComplete 
                Write-progress -Activity "Completed:" -status "$CompletedNodeList " -ID 1
            }
        }
        Catch{$date = get-date -format "MM/dd/yy hh:mm:ss " Write-warning "$date Failed connection to $node, will retry"}
    }
    start-sleep 2
}
While ($CurrentlyRunningNodelist)

#copy all logs files to this server
foreach ($node in $fullNodeList)
{
    if (Test-Path "\\$node\C`$\WSUS\WindowsUpdatesInstallLog.log")
    {
        Copy-Item "\\$node\C`$\WSUS\WindowsUpdatesInstallLog.log" "$logPath\$($node)_WUInstallLog_$date.log"
    } else {Write-Host "No install log file found for $node : \\$node\c`$\Wsus\WindowsUpdatesInstallLog.log"}
}
#parse result out of log files
Write-host -ForegroundColor Cyan "`nAll Log Files copied to D:\PDWDiagnostics\, including a list of installed updates and the return codes from each node. Completion above indicates that the task to install the updates completed, it does not guarantee that the updates themselves were successful. "
Write-Host -ForegroundColor Cyan "`nYou will need to manually reboot the nodes, then you may need to run the installs again if there were updates that failed due to needing a restart first. Running the tool again after restart will tell you if there are more updates to install. "