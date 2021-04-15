#* FileName: ADU.ps1
#*=============================================
#* Script Name: ADU.ps1
#* Created: [10/28/2013]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*
#* Keywords:
#*=============================================
#* Purpose: Appliance Diagnostic Utility
#*=============================================

<#
.SYNOPSIS
    Appliance Diagnostic Utility (ADU) is a tool to help diagnose issues with the Analytics Platform System appliance.
.DESCRIPTION
    In the current release the tools can troubleshoot the fabric and PDW, work on the HDI region is currently in progress. ADU can be used to gather and collect data for diagnostic work and perform specific repair operations.  
.EXAMPLE
    .\ADU.ps1
    Default mode without parameters. You will be prompted to enter credentials when selecting an option that requires this. 
.EXAMPLE
    .\ADU.ps1 -offline
    Offline Mode: This will skip credentials and disable functionality where communication with the PDW database is needed. If you select an operation that requires PDW in this mode you will be notified that it is being skipped. 
.EXAMPLE
	.\ADU.ps1 -PdwUsername sa -PdwPassword P@ssW0rd
	Credentials mode: You can run ADU by passing credentials at the command line, otherwise you will be prompted for username and password.
.EXAMPLE
	.\ADU.ps1 -[action name]
	Unattended mode: By specifying the action name in the command line, the script will run in unattended mode executing the actions you specify. You will be prompted for username and password unless you specify them. Running multiple actions in unattended mode is not supported.
	Supported actions:
		diagnosticActions
		distCmd
		RunPAV
		newDisk
		GetNetConfig
		copyXmls
		AlignCsv
		tableSkew
		replicatedTableSize
		CheckStatistics
		PDWBackupTest
		PDWLoadTest
		
#>

#Parameters that could be included for automatic run - needs to include possible params for subscripts
Param(
	[switch]$LoginAdmin, #Menu Usage: Include the Login processing scripts

#These are parameters needed by sub-scripts
	[switch]$offline, #Script(s) Used: Diagnostics Collection
	[string]$Username=$null, #Script(s) Used: Diagnostics Collection
	[string]$Password=$null, #Script(s) Used: Diagnostics Collection
	[array]$actions=$null, #Script(s) Used: Diagnostics Collection, specify actions for PDWDiag to run
	[string]$database, # database name
	[string]$command, # Script(s) used: Distributed Command
	[switch]$parallel, # Script(s) used: Distributed Command
	[string]$outputDir, #output directory for Diagnostics Collection if not default

#These parameters are for automated runs. Parameter name should be the same as script name
	[switch]$diagnostics_Collection,
	[switch]$Distributed_Command, #Will kick off distributed command tool
	[switch]$Add_New_Disk, #Will kick off add new disk script
	[switch]$Align_Disks, #Will kick off align csv's script
	[switch]$Check_Wmi_Leak, #will kick off check/fix WMI tool
	[switch]$Collect_Sql_Plans, #will kick off the collect sql plans tool
	[switch]$Get_Network_Adapter_Config, #Will kick off get network config script
    [switch]$Manage_Performance_Counters,
    [switch]$Publish_PDW_XMLs, #Will kick off copy xmls script
	[switch]$validate_Pdw_xmls, #will kick off the validate xmls tool
    [switch]$Backup_Test, #will kick off the PDW backup test tool
    [switch]$Database_Space_Report, #will kick off the database space report
    [switch]$Failed_Data_Loads, #will kick off the PDW load test tool
	[switch]$Last_Modified_Statistics, #will kick off the check stats tool
	[switch]$Replicated_Table_Sizes, #will kick off replicated table size tool
	[switch]$Run_Pav, #Will kick off RunPAV
	[switch]$Storage_Health_Check, #will kick off the storage health check
	[switch]$Table_Skew, #will kick off table skew tool
	[switch]$Wellness_Check, #will kick off health check tool

#These parameters are for automated runs, not shown in the menu. Parameter name should be the same as script name
    [switch]$TempDB_Space_Report, #will kick off the TempDB Space Report
    [switch]$CCI_Health #will kick off the CCI Health
	)

################################################################
# Version Number - bump for any updates to any script in ADU!!!#
################################################################
$aduVersion="v4.7"
################################################################
   
#Set a global path variable for all scripts to use
$global:rootPath = $PSScriptRoot

#add prefix to root-path based on PDW Version
#figure out what version I'm on based on existence of WDS node in XML
[xml]$afdXml = Get-Content "c:\PDWINST\MEDIA\applianceFabricDefinition.xml"
if ($afdXml.ApplianceFabric.Region.nodes.WdsNode)
{
	#running AU3 or newer
	$versionPath = "\AU3+"
	$aduVersion += " AU3+"
	$OutputDrive="D:"
}
else
{
	#running older than AU3
	$versionPath = "\OLDER"
	$OutputDrive="C:"
}
$rootPath += $versionPath

#includes
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire"
$source = $MyInvocation.MyCommand.Name #Set Source to scriptname
#adding this check to make sure there isn't a PSU log preventing this one from being created
try
{
    New-EventLog -Source $source -LogName ADU #register the source for the event log
}
catch
{
    #it usually fails becuase ADU has been ran with this source register, and cannot be re-registered under the new log name. Try to clean it up and try again
    if ($_.exception -notlike "*source is already registered*")
    {
        remove-eventlog PSU
        try
        {
            New-EventLog -Source $source -LogName ADU #register the source for the event log
        }
        catch
        {
            Write-Error "Failed to create the necessary eventlog. This is probably because a beta version of this tool has been ran on this appliance has been ran before and could not be cleaned up`n"$_
        }
    }
}
Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Starting $source" 

if(!(test-path "$OutputDrive\PDWDiagnostics")){mkdir "$OutputDrive\PDWDiagnostics" | Out-Null}

#check that this is the proper machine
$hostname = hostname
if($hostname.split("-")[1] -notin "HST01","HST02")
{
    Write-Warning "This tool is intended to be ran on HST01 (HST02 if necessary) as PDW Domain Admin. You are on $hostname"
    Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Warning -message "User is running tool from $hostname" 
}

Do
{
	#Check free space on the output Drive
	#Error handling here because WMI issues causes this to fail
	try
	{
		#get free space on output drive
		[int]$DFreeSpace = (gwmi win32_logicaldisk | ? {$_.deviceID -eq "$OutputDrive"}).freespace / 1gb
	    Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Information -message "Free Space on D: $DFreeSpace GB" 
		
	    $color = "green"
		if($DFreeSpace -lt 50)
		{
			Write-Warning "Free Space on `'$OutputDrive`' is $DFreeSpace`GB, filling this drive by collecting diagnostics will cause issues"
	        Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Warning -message "User Continuing with $DFreeSpace`GB free on D"
			$color = "yellow"
		}
		elseif ($DFreeSpace -lt 5)
		{
	        Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Error -message "Exiting tool because less than 5GB of free space available on $OutputDrive. $DFreeSpace`GB"
			Write-Error "Less than 5gb of free space left on 'D:' drive... Terminating"
		}
	}
	catch
	{
		Write-EventLog -Source $source -logname ADU -EventID 9999 -EntryType Warning -message "Not able to query win32_logicaldisk with wmi. `nThere is likely an issue with WMI on this server.`nSelect yes to continue then run `'Fix WMI Leak`' option of this tool to check/fix`n$_"
		Write-Host "`n"
		Write-warning "Not able to query win32_logicaldisk with wmi. `nThere is likely an issue with WMI on this server.`nSelect yes to continue then run `'Fix WMI Leak`' option of this tool to check/fix"
	}
		
	#If CCI_Health option is present - unhide the CCI_Health script, else hide it
        if ($CCI_Health.IsPresent -eq $false) 
          {
            $ScriptToHide = get-item "$rootpath\Scripts\Reports\CCI_Health.ps1" -Force
            $ScriptToHide.Attributes = "Hidden"
          }
        else
          {
            $ScriptToHide = get-item "$rootpath\Scripts\Reports\CCI_Health.ps1" -Force
            $ScriptToHide.Attributes = "Normal"
          }
		
	#If TempDB_Space_Report option is present - unhide the TempDB_Space_Report script, else hide it
        if ($TempDB_Space_Report.IsPresent -eq $false) 
          {
            $ScriptToHide = get-item "$rootpath\Scripts\Reports\TempDB_Space_Report.ps1" -Force
            $ScriptToHide.Attributes = "Hidden"
          }
        else
          {
            $ScriptToHide = get-item "$rootpath\Scripts\Reports\TempDB_Space_Report.ps1" -Force
            $ScriptToHide.Attributes = "Normal"
          }
		
	#If LoginAdmin option is present - unhide the Logins folder, else hide it
        if ($LoginAdmin.IsPresent -eq $false)
          {
            $LoginFolderPath = get-item "$rootpath\Scripts\Logins" -Force
            $LoginFolderPath.Attributes = "Hidden"
          }
        else
          {
            $LoginFolderPath = get-item "$rootpath\Scripts\Logins" -Force
            $LoginFolderPath.Attributes = "Normal"
          }

	#Build the menu based on the folder structure of this tool
	$MainMenuOptions=@()
	$MainMenuOptions = GetFileAttributes "$rootpath\Scripts\"

    #Check for possible automated runs
    foreach ($option in $MainMenuOptions) 
    {
        #remove folders from the list
        if ($option.gettype().name -eq "string")
        {
            #check if the string found was passed as a parameter
            if ($PSBoundParameters.ContainsKey($option))
            {
                #run the script automated
                write-host -ForegroundColor Cyan "`n--Running in Automated Mode--`n"
                $automated=$true

                [String]$selection = $option
            }
        }

    }

    if (!$Automated)
    {
        #output the menu since no automated run was supplied
        [string]$selection = OutputMenu -header "Appliance Diagnostic Utility $aduVersion"  -options $MainMenuOptions
            
    }    

    #get the full path for the selection
	[string]$FullSelectionPath = (gci "$rootpath\Scripts\" -recurse | ? {$_.baseName -eq $selection}).Fullname 
	

    #add other parameters to the command
    [string[]]$keyArray = $PSBoundParameters.keys
    [string[]]$valueArray = $PSBoundParameters.Values
    #check if parameter is not in mainMenuOptions and if not then pass it along
    foreach ($key in $KeyArray)
    {
        if($key -notin $MainMenuOptions)
        {
            #get the value for this key
            $value = $valueArray[$keyArray.IndexOf($key)]
            $FullSelectionPath += " -$key $value"
        }
    }

	#return if q was entered which returned a -1
	if($selection -eq "q"){return}

    #if selection was PDWDiag open it in a new window otherwise, run selection in current window
    if ($selection -like "*Diagnostics_Collection*")
    {
        start-process PowerShell.exe "$FullSelectionPath"
    }
    else
    {
	    #Run the command
	    invoke-expression "$FullSelectionPath"
    }
   
}While(!$Automated)
