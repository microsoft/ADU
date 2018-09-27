#*=============================================
#* PDWPublishXMLs.ps1
#*
#*
#* Authors:                                                                          
#* Ryan Stucker, Kristine Lange, Nick Salch                                                                       
#*
#* .Purpose :                                                                          
#* This script is used to Publish manually editted XML Documents                      
#* after they have been validated.                                                   
#*
#* Syntax: .\PDWPublishXMLs.ps1
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 1/9/2014 6:00 PM
#* Changes: 
#* 1. Replaced Function GenerateNodeList with call to PDWFunction.ps1 GetNodeList.
#*    This fixes issue where files are not propagated to ISCSI VMs.
#* 2. Moved logs to C:\PDWDiagnostics to be consistent with other diagnostic tools.
#* 3. Removed $afd, $fabricDomain, $port and $CopyNodeList.
#* 4. Ouptut formatting changes. 
#* 
#* Modified: 2/19/2014
#* 1. Added logging
#* 2. Added error handling
#* 3. Brought up to ADU standards
#*=============================================
                                                   
<#
.SYNOPSIS
    This tool is to dynamically publish to all nodes the XMLs in the target UNC directory.  No parameters are accepted, but you are prompted for the UNC Path
.DESCRIPTION
    This tool is to dynamically publish to all nodes the XMLs in the target UNC directory.
.EXAMPLE
    .\PDWPublishXMLs.ps1
#>

. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Variables
#[xml]$apd = Get-Content C:\PDWINST\media\AppliancePdwDefinition.xml
#$pdwDomain = $apd.AppliancePdw.Topology.DomainName
$pdwDomain = GetPDWDomainNameFromXML
[string]$CurrTime = Get-Date -DisplayHint DateTime -Format yyyyMMddHHmmss

#Lists
$NodeList = GetNodeList -fqdn -full
$Archive="C:\PDWDiagnostics\PDWPublish_XML_Archive\$CurrTIme"

Function PDWPublishXMLs
{

	
	do
	{
		$badInput = $false
		$XMLServer = "\\$pdwDomain-ctl01\SQLPDW10\"
		
		#check that control node share is reachable - exit if it is not
		try
		{
			Test-Path $XMLServer | Out-null
		}
		catch [UnauthorizedAccessException]
		{
			if((whoami).split("\")[0] -ne $pdwDomain)
			{
				Write-Error -ErrorAction Continue -Message "Access Denied to SQLPDW10 share - you must be PDW Domain user to use this tool"
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Access Denied to SQLPDW10 share - you must be PDW Domain user to run this script`nFull Error:`n$_" 
			}
			else
			{
				Write-Error -ErrorAction Continue -Message "Access Denied to SQLPDW10 share"
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Access Denied to SQLPDW10 share`nFull Error:`n$_" 
			}
			return
		}
		catch
		{
			Write-Error -ErrorAction Continue -Message "Control node share not reachable`nmake sure the appliance is online"
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Control node share not reachable`nmake sure the appliance is online`nFull Error:`n$_" 
			return
		}
		
		[string]$XMLSourceDir= Read-host "`nXML UNC Source Directory (Leave Blank for \\$pdwDomain-CTL01\SQLPDW10)"
		   
		if ($XMLSourceDir -eq "")
    	{
        	$XMLSourceDir = $XMLServer
    	}
		
		if($XMLSourceDir[0] -ne $XMLSourceDir[1] -or $XMLSourceDir[0] -ne "\")
		{
			Write-Host -ForegroundColor Red -BackgroundColor Black "ERROR: Please enter a path starting with `'\\`'`nIf the path is on the localhost then start with \\localhostname\C`$"
			$badInput = $true
		}
	}while($badInput)
	
	#add on a '\' if it's not there for the comparison
	if ($XMLSourceDir[$xmlsourcedir.length-1] -ne "\")
	{$XMLSourceDir += "\"}
	
	write-eventlog -entrytype Information -Message "XML Source set to $XMLSourceDir" -Source $source -LogName ADU -EventId 9999 
	
	#confirm that the files are being copied correctly
	if ((dir "$XMLSourceDir*.xml").name)
	{
		$xmls = (dir "$XMLSourceDir*.xml").name
		Write-Host "`nThis tool will copy the following files from $XmlSourceDir to c:\pdwinst\media on all nodes:"
		$xmls
		Read-Host "`nPress Enter to continue (CTRL-C to Quit)"
		write-eventlog -entrytype Information -Message "Will copy the following files from $XmlSourceDir to c:\pdwinst\media on all nodes:`n`n$xmls" -Source $source -LogName ADU -EventId 9999 
	}
	else
	{
		#exit if no XMLs found in the source
		write-eventlog -entrytype Error -Message "No PDW XMls found in source location $XMLSourceDir" -Source $source -LogName ADU -EventId 9999 
		Write-Error -ErrorAction Continue "No PDW XMls found in source location $XMLSourceDir or source location not reachable"
		return
	}
    mkdir $Archive |out-null
    
    Write-Host -ForegroundColor Green "`nSource Location: $XMLSourceDir" 
     
    $ArchiveNode = "$Archive\Source"
    Write-Host "`nArchiving files from Source location to: `n$ArchiveNode...`n"
	write-eventlog -entrytype Information -Message "Archiving files from source location to $archiveNode" -Source $source -LogName ADU -EventId 9999 
	
    mkDir $ArchiveNode |out-null
    Copy-Item $XMLSourceDir\*.xml $ArchiveNode\ |out-null
	
	
    if ($XMLSourceDir.ToUpper() -ne $XMLServer.ToUpper())
	{
		###Archive the control node share if it is not the source
        $ArchiveNode = "$Archive\SQLPDW10"
        Write-Host "Archiving Control Node Share XMLs (SQLPDW10)"
		write-eventlog -entrytype Information -Message "Archiving Control Node Share: $XMLServer to $archiveNode" -Source $source -LogName ADU -EventId 9999 
		mkDir $ArchiveNode |out-null
		try
		{
			Copy-Item $XMLServer\*.xml $ArchiveNode\ |out-null
		}
		catch
		{
			Write-Error -ErrorAction Continue -Message "Error encountered archiving files from control node share $XMLServer to $archiveNode`n$_"			
			return
		}
		
		###Copying new files to control node share since it is not the source
        Write-Host "Copying new XMLs to Control Node Share (SQLPDW10)`n" 
		write-eventlog -entrytype Information -Message "Copying new XMLs to Control Node Share: $XMLServer" -Source $source -LogName ADU -EventId 9999 
		
		try
		{
	    	Copy-Item $XMLSourceDir\*.xml $XMLServer\ |out-null
		}
		catch
		{
			write-eventlog -entrytype Error -Message "Error encountered copying new xmls to Control node share`n$_" -Source $source -LogName ADU -EventId 9999 
			Write-Error -ErrorAction Continue -Message "Error encountered copying new xmls to Control node share`n$_"
			return
		}
	}
	
		
	###Archive the old XMLs on all nodes
	Write-Host "Archiving old XMLs to $archive" 
    foreach ($node in $NodeList)
	{
		$shortName = $node.split(".")[0]
		$nodeLocation = "\\$shortName\C$\PDWINST\Media\"
        $ArchiveNode = "$Archive\$shortName"

        if ($XMLSourceDir.ToUpper() -ne $shortName.ToUpper())
	    {
			write-host "$shortName " -NoNewline
			write-eventlog -entrytype Information -Message "Archiving old XMLs on $shortname to $archivenode" -Source $source -LogName ADU -EventId 9999 
          
            mkDir  $ArchiveNode |out-null
			try
			{
		    	Copy-Item $nodeLocation*.xml $ArchiveNode\ |out-null
			}
			catch
			{
				Write-Error -ErrorAction Continue -Message "Error encountered archiving xmls from $shortname to $archivenode`n$_"				
				return
			}
			Write-Host -ForegroundColor Green "Done" 
        }
		else{Write-Host "Skipping Source Node: $shortname"}
	}
	
	###Copy new XMLs to all nodes
	Write-host "`nCopying new XMLs from $XMLSourceDir to servers... "
	
	foreach ($node in $NodeList)
	{
		$shortName = $node.split(".")[0]
		$nodeLocation = "\\$shortName\C$\PDWINST\Media\"
        $ArchiveNode = "$Archive\$shortName"
		
        if ($XMLSourceDir.ToUpper() -notlike $nodeLocation.ToUpper())
	    {
			write-host "$shortName " -NoNewline
			write-eventlog -entrytype Information -Message "Copying New XMLs from sourcedir: $sourceDir to $shortname" -Source $source -LogName ADU -EventId 9999 
            
			try
			{
		    	Copy-Item $XMLSourceDir\*.xml $nodeLocation |out-null
			}
			catch
			{
				write-eventlog -entrytype Error -Message "Error copying New XMLs from sourcedir: $sourceDir to $shortname" -Source $source -LogName ADU -EventId 9999 
				Write-Error -ErrorAction Continue -Message "Error copying New XMLs from sourcedir: $sourceDir to $shortname`n$_"
				return
			}
			Write-Host -ForegroundColor Green "Done"
        }
		else{Write-Host "Skipping Source Node: $shortname"}
	}
	
	Write-Host "`nNew Xmls copied out to all servers. Old Files archived at: $Archive`n"
}

. PDWPublishXMLs