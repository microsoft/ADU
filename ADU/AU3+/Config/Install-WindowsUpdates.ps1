#Install Windows Updates
Function Main
{
    #Set up necessary variables
    $script:ScriptName = $MyInvocation.MyCommand.ToString() 
    $script:ScriptPath = $MyInvocation.MyCommand.Path
    $script:UpdateSession = New-Object -ComObject 'Microsoft.Update.Session'
    $script:UpdateSession.ClientApplicationID = 'Packer Windows Update Installer'
    $script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
    $script:SearchResult = New-Object -ComObject 'Microsoft.Update.UpdateColl'

    SendToLog "Initializing function $ScriptName"

    #Check if there are windows updates available to Install
    Check-WindowsUpdates
    if ($global:MoreUpdates -eq 1)
    {
        SendToLog "Updates found for install, running install process"
        Install-WindowsUpdates
    }
    else
    {
        Write-Host "No updates found to install, exiting";"No more updates found to install, exiting" | SendToLog
    }
    Write-host "Script completed";"Script Completed" | SendToLog
}



function Check-WindowsUpdates() {
    Write-Host "Checking For Windows Updates";"Checking For Windows Updates" | SendToLog


    $script:UpdateSearcher = $script:UpdateSession.CreateUpdateSearcher()
    $script:SearchResult = $script:UpdateSearcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")  
        
    if ($SearchResult.Updates.Count -ne 0) {
        $script:SearchResult.Updates |Select-Object -Property Title, Description, SupportUrl, UninstallationNotes, RebootRequired, EulaAccepted |Format-List
        $global:MoreUpdates=1

        #Log all of the updates to be installed
        $UpdatesToInstall = $script:SearchResult.Updates
        Foreach ($Update in $UpdatesToInstall) {"Update To Install: $($Update.title)" | SendToLog}

    } 
    else {
        "Did not find any applicable updates" | SendToLog
        Write-Host 'There are no applicable updates'

        $global:RestartRequired=0
        $global:MoreUpdates=0
    }
}

function Install-WindowsUpdates() {
    SendToLog "Initializing function: Install-WindowsUpdates"
    
    Write-Host "Evaluating Available Updates for user input requirements or EULA acceptance";"Evaluating Available Updates for user input requirements or EULA acceptance" | SendToLog
    
    
    $UpdatesToDownload = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    foreach ($Update in $SearchResult.Updates) 
    {
        if (($Update -ne $null) -and (!$Update.IsDownloaded)) 
        {
            [bool]$addThisUpdate = $false
            #Check if it requires user input - if so then skip it
            if ($Update.InstallationBehavior.CanRequestUserInput) 
            {
                "> Skipping: $($Update.Title) because it requires user input" | SendToLog
                Write-Host "> Skipping: $($Update.Title) because it requires user input"
            } else 
            {
                #Accept License if required
                if (!($Update.EulaAccepted)) 
                {
                    "> Note: $($Update.Title) has a license agreement that must be accepted. Accepting the license." | SendToLog
                    Write-Host "> Note: $($Update.Title) has a license agreement that must be accepted. Accepting the license."
                    $Update.AcceptEula()
                    [bool]$addThisUpdate = $true
                } 
                else 
                {
                    [bool]$addThisUpdate = $true
                }
            }
        
            if ([bool]$addThisUpdate) {
                Write-Host "Adding: $($Update.Title)"
                $UpdatesToDownload.Add($Update) |Out-Null
            }
		}
    }
    "Done evaluating available updates" | SendToLog

    if ($UpdatesToDownload.Count -eq 0) 
    {
        "No Updates To Download..." | SendToLog
        Write-Host "No Updates To Download..."
    } else 
    {
        "Downloading Updates..." | SendToLog
        Write-Host "Downloading Updates..."
        $Downloader = $UpdateSession.CreateUpdateDownloader()
        $Downloader.Updates = $UpdatesToDownload
        $Downloader.Download()
        "Done downloading updates" | SendToLog
    }
	
    $UpdatesToInstall = New-Object -ComObject 'Microsoft.Update.UpdateColl'
    [bool]$rebootMayBeRequired = $false

    "The following updates are downloaded and ready to be installed:" | SendToLog
    Write-Host "The following updates are downloaded and ready to be installed:"
    foreach ($Update in $SearchResult.Updates) 
    {
        if (($Update.IsDownloaded)) {
            "> $($Update.Title)" | SendToLog
            Write-Host "> $($Update.Title)"
            $UpdatesToInstall.Add($Update) |Out-Null
              
            if ($Update.InstallationBehavior.RebootBehavior -gt 0){
                [bool]$rebootMayBeRequired = $true
            }
        }
    }
    
    if ($UpdatesToInstall.Count -eq 0) 
    {
        'No updates available to install...' | SendToLog
        Write-Host 'No updates available to install...'
        $global:MoreUpdates=0
        $global:RestartRequired=0
        "Breaking out of script" | SendToLog
        break
    }

    if ($rebootMayBeRequired) {
        "These updates may require a reboot" | SendToLog
        Write-Host 'These updates may require a reboot'
        $global:RestartRequired=1
    }
	
    
    Write-Host "Installing updates...";"Installing updates..." | SendToLog
  
    $Installer = $script:UpdateSession.CreateUpdateInstaller()
    $Installer.Updates = $UpdatesToInstall
    $InstallationResult = $Installer.Install()
  
    Write-Host "Overall installation Result: $($InstallationResult.ResultCode)"; "Overall installation Result: $($InstallationResult.ResultCode)" | SendToLog
    Write-Host "Reboot Required: $($InstallationResult.RebootRequired)"; "Reboot Required: $($InstallationResult.RebootRequired)" | SendToLog
    Write-Host "Listing of updates installed and individual installation results:";"Listing of updates installed and individual installation results:" | SendToLog
    
    if ($InstallationResult.RebootRequired) {
        $global:RestartRequired=1
    } else {
        $global:RestartRequired=0
    }
    
    for($i=0; $i -lt $UpdatesToInstall.Count; $i++) {
        $UpdateResult = New-Object -TypeName PSObject -Property @{
            Title = $UpdatesToInstall.Item($i).Title
            Result = $InstallationResult.GetUpdateResult($i).ResultCode
        }
        $updateResult
        "Result: $($UpdateResult.Result) Title:$($UpdateResult.title)" | SendToLog
    }
	
    "End of install function" | SendToLog
}

#Log Function
Function SendToLog () {
    [cmdletbinding()]
    param(
        [parameter(
            Mandatory         = $true,
            ValueFromPipeline = $true)]
        $pipelineInput
    )

    $message = $pipelineInput

    $logPath = "C:\WSUS\"
    $LogFile="WindowsUpdatesInstallLog.log"

    if (!(Test-path $Logpath)){Mkdir $Logpath}
    $date = get-date -Format "MM/dd/yy HH:mm:ss"

    "$date $message" | Out-File -Append -FilePath $Logpath$LogFile
}

. Main