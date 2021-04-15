#* FileName: Diagnostics_Collection.ps1
#*=============================================
#* Script Name: Diagnostics_Collection.ps1
#* Created: [10/28/2013]
#* Author: Nick Salch, Victor Hermosillo
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*
#* Keywords:
#*=============================================
#* Purpose: capture PDW Diagnostic information
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
                                                  
<#
.SYNOPSIS
    This tool will collect diagnostic information from a PDW appliance. Run with no parameters to run in default mode.
.DESCRIPTION
    This tool will collect logs, DMVs, Dumps, and other diagnostic information using the options provided. 
.EXAMPLE
    .\Diagnostics_Collection.ps1
    Default full-run mode: you will be prompted for PDW credentials, a node list will be generated containing all servers, and all functionality will be enabled for you to select.
.EXAMPLE
    .\Diagnostics_Collection.ps1 -offline
    Offline Mode: This will skip PDW credentials and disable functionality where communication with the PDW is needed. If you select an operation that requires PDW in this mode you will be notified that it is being skipped. 
.EXAMPLE
	.\Diagnostics_Collection.ps1 -offline -nodeList
	NodeList mode: Offline mode, the tool will generate a nodeList then present it to you in Notepad to be edited. 
.EXAMPLE
	.\Diagnostics_Collection.ps1 -username sa -password P@ssW0rd -actions info_bundle,dm_pdw_waits,health_bundle (Right now the bundles don't work correctly- this is actually an usupported feature)
	Unattended mode: by specifying the -actions in the command line the script will run in unattended mode executing the actions you specify. You will be prompted for username and password unless you specify them
#>
Param([switch]$offline,[switch]$nodeList,[string]$Username,[string]$Password,[array]$actions,[string]$outputDir)

#Because Diagnostics_Collection opens in a new window we loose our rootpath variable. Creating it again
$splitPath = $myinvocation.invocationname.split("\")
$rootPath = $splitPath[0..($splitPath.length-4)] -join "\"

#include the functions we need:
. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

$toolVersion="V4.1.0"

#check that there is an XML and set some variables
if ((test-path "C:\PDWINST\media\ApplianceFabricDefinition.xml") -and (test-path "C:\PDWINST\media\AppliancePdwDefinition.xml"))
{
	$fabReg = GetFabRegionName
	$pdwReg = GetPdwRegionName
	$pdwServer = "$pdwReg-sqlctl01"
    $port = 17001
}
else
{
	Write-EventLog -EntryType Error -message "Not able to find fabric and/or PDW definition XMLs under C:\PDWINST\Media" -Source $source -logname "ADU" -EventID 9999  
    write-error "Not able to find fabric and/or PDW definition XMLs under C:\PDWINST\Media"
}

function Diagnostics_Collection
{
	#try catch around everything to make sure we catch anything we missed
	try
	{
		$startTime= get-date

	    If(!$offline)
	    {
			#Load SQL PowerShell module
			Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module...`nThis could take up to 2 minutes.`nIf you don't need to run SQL/PDW Queries, you can avoid this by running .\ADU.ps1 -offline"
			LoadSqlPowerShell
			
			#loop getting creds for $attemptsleft attempts
			$attemptsLeft=2
			do
			{
				if($attemptsLeft -lt 0){write-host -ForegroundColor Red -BackgroundColor Black "Max Attempts reached";start-sleep 2;return}
				if(!$Username){$U = GetPdwUsername}else{$U=$Username;$attemptsLeft=0}
				if(!$Password){$P = GetPdwPassword}else{$P=$Password;$attemptsLeft=0}
				try
				{
					$goodcreds = CheckPdwCredentials -U $U -P $P -PDWDomain $pdwReg
				}
				catch
				{
					Write-EventLog -EntryType Error -message "Error encountered during 'CheckPdwCredentials' function`n$_" -Source $source -logname ADU -EventID 9999
					Write-Error "Error encountered during 'CheckPdwCredentials' function`n$_"
				}
				
				if(!$goodCreds)
				{
					Write-Host -ForegroundColor Yellow "`nBy default, account is locked after 10 failed attempts`nAllowing $attemptsleft more attempts (not based on the max 10 attempts)"
					$attemptsLeft--
				}
				else
				{	
					$Username = $U
					$Password = $P
					$goodcreds = $true
				}
			
			
			}while(!$goodCreds)
		}
			
	    #Read input.xml file into variable
	    if(test-path $rootPath\Config\Diagnostics_Collection_Input.xml){[xml]$inputFile = Get-Content $rootPath\Config\Diagnostics_Collection_Input.xml}
	    else 
	    {
			Write-EventLog -EntryType Error -message "Not able to find input file: $rootPath\Config\Diagnostics_Collection_Input.xml" -Source $source -logname ADU -EventID 9999
		    write-error "Not able to find input file: $rootPath\Config\Diagnostics_Collection_Input.xml"
	    }


	    #generate the Nodelist using XML (in case cluster is down)
		#$FullNodeList = GenerateFullNodeListFromXML
		$FullNodeList = GetNodeList -full -useXml

		if (!$FullNodeList)
	    {
			Write-EventLog -EntryType Error -message "GetNodeList -full -useXml did not return any nodes!" -Source $source -logname ADU -EventID 9999
		    Write-Error "GetNodeList -full useXml did not return any nodes!"
	    }

		#Check for unreachable nodes and remove them from the nodelist
		try
		{
			Write-Host -ForegroundColor Cyan "`nChecking for unreachable nodes..."
			$unreachableNodes = CheckNodeConnectivity $Fullnodelist
		}
		catch
		{
			Write-Error -ErrorAction Continue  "$_"
			Read-Host "pausing"
		}
		if($unreachableNodes)
		{
			Write-Host -ForegroundColor Yellow -BackgroundColor Black "`nWas not able to reach the nodes in the list below`nwould you like to remove them from the nodelist? (RECOMMENDED)"
			$unreachableNodes
			
			$goodInput=$false
			while(!$goodInput)
			{
				if (!$offline)
				{
					$UnreachableNodesInput = Read-Host "`n(Y/N)"
					switch ($UnreachableNodesInput)
					{
						"Y" {$goodInput = $true}
						"N" {$goodInput = $true}
						default {Write-Host -ForegroundColor Red "input not recognized..."}
					}
				}
				else
				{
					Write-host -foregroundcolor yellow "`nOffline Mode detected - auto removing unreachable nodes from list`n"
					Write-EventLog -EntryType Warning -message "Offline Mode detected, removing following unreachable nodes from nodelist automatically: $unreachableNodes" -Source $source -logname ADU -EventID 9999
					$UnreachableNodesInput = "Y"
					$goodInput = $true
				}
			}
			
			if($UnreachableNodesInput -eq "Y")
			{
				#remove the unreachable nodes from the list
				$FullNodeList = $FullNodeList | ? {$_ -notin $unreachableNodes}
				Write-Host "Proceeding with the new nodelist below: "
				$FullNodeList
			}
		}	

	    #set up the output directory
	    $runId= "Diagnostics_Collection_$(get-date -f yyyy-MM-dd_hhmmss)"
		
		#if output directory wasn't provided use the default
		if(!$outputDir)
		{
			$outputDir = "D:\PDWDiagnostics\Diagnostics_Collection\$runID"
		}
		else
		{
			$outputDir += "\$runID"
		}
		
	    mkdir $outputDir -Force | Out-Null
		
		if (!(test-path $outputDir))
		{
			Write-EventLog -EntryType Error -message "Output Path $outputDir could not be found" -Source $source -logname ADU -EventID 9999
			write-error "Output Path $outputDir could not be found"
		}
		
		Write-EventLog -EntryType Information -message "Output Directory set to $outputdir" -Source $source -logname ADU -EventID 9999
		Write-host -foregroundcolor cyan "`nOutput Directory set to $outputdir"
	
	    #if actions aren't specified on command line, display the menu to get actions
	    if(!$actions)
	    {
		    #Loop to display main menu and bring user back there until they exit
		    Do
		    {
			    $optionsArray=@()
			    foreach ($menuOption in $inputFile.menu.option.name)
			    {
				    $optionsArray += $menuOption
			    }

			    [string]$UserInput1 = OutputMenu -options $optionsArray -header "PDW 2012 Diagnostics Collection"


				#function returned -1 for q
			    if($UserInput1 -eq "q"){return;}

				if($userInput1)
				{
		
				    do
				    {
					    Write-Host "`n"
					    $actionsArray=@()
					    foreach ($menuOption in ($inputFile.menu.option | ? {$_.name -eq "$userInput1"}).action.title)
					    {
						    $actionsArray += $menuOption
					    }
					
					    [string]$Userinput2 = OutputMenu -options $actionsArray -header "$userInput1"

						
					    if($Userinput2 -eq "q"){break;break}
					
						if($userInput2)
						{
						    ExecuteAction $userInput1 $userInput2
					    }
					    else{Write-Error -ErrorAction Continue "Option Not Found"}
				    }while ($true)
			    }
			    else{Write-Error -ErrorAction Continue "Option Not Found"}
		    }While($true)
			
		    Write-Host -ForegroundColor Green "Diagnostics Output located under: $outputDir"
	    }
	    else
	    {
		    #run executeAction for an automated run
		    foreach ($actionName in $actions)
		    {
			    $action = $inputFile.menu.option.action | where-object {$_.name -eq $actionName}
			    $option= $action.ParentNode
				ExecuteAction $option.name $action.title
		    }
		
		    Write-Host -ForegroundColor Green "Diagnostics Output located under: $outputDir"
		    $endTime = get-date
			Write-EventLog -EntryType Information -message "Automated run`nStart Time: $startTime `nEnd Time: $endTime" -Source $source -logname ADU -EventID 9999
		    write-host "`nStart Time: $starttime"
		    write-host "End Time:   $endTime"
	    }
		
	}
	catch
	{
		Write-Error -ErrorAction continue "ERROR OCCURED DURING EXECUTION - PRESS ENTER TO CLOSE WINDOW`n`n$_"
		Read-Host
	}
}


function ExecuteAction([string]$UserInput1, [string]$UserInput2)
{
	$QueryObject = ($inputFile.menu.option | ? {$_.name -eq $userinput1}).action | ? {$_.title -eq $userinput2}
	#Values: value, name, type, days, nodes

    $actioncount = ($inputFile.menu.option | ? {$_.name -eq $userinput1}).action.count


	$Error.clear()
	
    switch($QueryObject.type)
    {

        "pshell" 
            {
			    Write-Host -ForegroundColor Cyan "`nEXECUTING: $($QueryObject.name)"
								
			    $outputPath = "$outputDir\$($QueryObject.name).txt"
			
				Write-EventLog -EntryType Information -message "Executing PowerShell Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value)" -Source $source -logname ADU -EventID 9999
				try
				{
					
                	ExecutePowerShell -command $($QueryObject.value) -outputPath $outputPath
				}
				catch
				{
					Write-EventLog -EntryType Error -message "Error Encountered during PowerShell Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value) `n`n$($_.exception)" -Source $source -logname ADU -EventID 9999
					Write-Output "Error Encountered during PowerShell Query: `'$($QueryObject.name)`'`n`n$_" >> $outputpath
					write-error "Error Executing $($QueryObject.name)`nSee ADU Event log for details`n$($_.FullyQualifiedErrorId)" -ErrorAction Continue
				}
            }
        "query_PDW" 
            {
			    Write-Host -ForegroundColor Cyan "`nEXECUTING: $($QueryObject.name)"
			    if(!$offline)
			    {		
				    mkdir -force "$outputDir\PdwQueries\" | Out-Null
				    $outputPath = "$outputDir\PdwQueries\$($QueryObject.name).csv"
				
					Write-EventLog -EntryType Information -message "Executing PDW Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value)" -Source $source -logname ADU -EventID 9999
            	    
					#Run query against PDW
					try
					{
            	    	ExecutePdwQuery -PdwQuery $($QueryObject.value) -outputpath $outputPath -U $Username -P $Password -port $port
					}
					catch
					{
						Write-EventLog -EntryType Error -message "Error Encountered during PDW Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value) `n`n$($_.exception)" -Source $source -logname ADU -EventID 9999
						Write-Output "Error Encountered during PDW Query: `'$($QueryObject.name)`'`n`n$_" >> $outputpath
						write-error "Error Executing $($QueryObject.name)`nSee ADU Event log for details`n$($_.FullyQualifiedErrorId)" -ErrorAction Continue
					}
			    }
			    else 
			    {Write-Host "-offline switch specified: Skipping"}
            }
	    "query_CMP"
		    {
			    Write-Host -ForegroundColor Cyan "`nEXECUTING: $($QueryObject.name)"
			    if(!$offline)
			    {	
				    #for now will grab any node in the list with a CMP in it
				    $sqlNodeList =  $FullNodeList | select-string "CMP"
			
				    foreach ($node in $sqlNodeList)
				    {
					    mkdir -force "$outputDir\$node\sql_instance\" | Out-Null
					    $outputPath = "$outputDir\$node\sql_instance\$($QueryObject.name).csv"
					
						Write-EventLog -EntryType Information -message "Executing SQL CMP Query: `'$($QueryObject.name)`' `n`nQUERY: $($QueryObject.value)" -Source $source -logname ADU -EventID 9999
						try
						{
					    	ExecuteSqlQuery -node $node -Query $($QueryObject.value) -outputpath $outputPath -U $Username -P $Password
						}
						catch
						{
							Write-EventLog -EntryType Error -message "Error Encountered during CMP Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value) `n`n$($_.exception)" -Source $source -logname ADU -EventID 9999
							Write-Output "Error Encountered during CMP Query: `'$($QueryObject.name)`'`n`n$_" >> $outputpath
							write-error "Error Executing $($QueryObject.name)`nSee ADU Event log for details`n$($_.FullyQualifiedErrorId)" -ErrorAction Continue	
						}
				    }
			    }else {Write-Host "-offline switch specified: Skipping"}
		    }
	    "query_CTL"
		    {
			    Write-Host -ForegroundColor Cyan "`nEXECUTING: $($QueryObject.name)"

			    if(!$offline)
			    {
				    $node="$pdwReg-CTL01"
				    mkdir -force "$outputDir\$node\sql_instance\" | Out-Null
				    $outputPath = "$outputDir\$node\sql_instance\$($QueryObject.name).csv"
				    $SqlCtlNode= "$pdwReg-SQLCTL01"
				
					Write-EventLog -EntryType Information -message "Executing SQL CTL Query: `'$($QueryObject.name)`' `n`nQUERY: $($QueryObject.value)" -Source $source -logname ADU -EventID 9999
					try
					{
				    	ExecuteSqlQuery -node $SqlCtlnode -Query $($QueryObject.value) -outputpath $outputPath -U $Username -P $Password
					}
					catch
					{
						Write-EventLog -EntryType Error -message "Error Encountered during CTL Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value) `n`n$($_.exception)" -Source $source -logname ADU -EventID 9999
						Write-Output "Error Encountered during CTL Query: `'$($QueryObject.name)`'`n`n$_" >> $outputpath
						write-error "Error Executing $($QueryObject.name)`nSee ADU Event log for details`n$($_.FullyQualifiedErrorId)" -ErrorAction Continue	
					}
			    }else {Write-Host "-offline switch specified: Skipping"}
		    }
	    "dist_Pshell"
		    {
			    Write-Host -ForegroundColor Cyan "`nEXECUTING: $($QueryObject.name)"
			
			    if (!$($QueryObject.nodes))
			    {
					Write-EventLog -EntryType Error -message "Dist_PShell: No NOdes found in XML to run command on `n`n $($QueryObject.name) `n`n $theQury" -Source $source -logname ADU -EventID 9999
				    Write-Error "Dist_Pshell: No nodes found in xml to run command on `n$($QueryObject.name)`n$($QueryObject.value)"
			    }
            
			    $command = $executioncontext.invokecommand.NewScriptBlock($($QueryObject.value))
                mkdir -force "$outputDir\AllNodes\" | Out-Null
			    $outputPath = "$outputDir\AllNodes\$($QueryObject.name).txt"
            
			    #Formatting for the output file
                $($QueryObject.value) > "$outputPath"
                " " >> "$outputPath"
			
			    $nodeList=@()
			    foreach($node in $($QueryObject.nodes).split(","))
			    {
					#if it's the localhost just add it to the list
				    if($node -eq "local"){$currHost = hostname;$nodeList+= $currHost}
					
					#from the full nodeList, if a node matches the current node from xml, add it to the list
					$FullNodeList | foreach {
						if($_ -like "*-$node*"){$nodeList += $_}
						#if($_ -like "*-$node*" -and ($_ -like "*-AD*" -or $_ -like "*-VMM*" -or $_ -like "*-HS*" -or $_ -like "*-ISCSI*")){$nodeList += $_ + '.' + $fabReg + '.fab.local'}
						#if($_ -like "*-$node*" -and ($_ -like "*-CTL*" -or $_ -like "*-CMP*" -or $_ -like "*-MAD*")){$nodeList += $_ + '.' + $pdwReg + '.pdw.local'}
					}
			    }
				
			    #make sure there's no duplicates
			    $nodeList = $nodeList | Select -Unique

				Write-EventLog -EntryType Information -message "Executing Distributed PowerShell Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value) `n`nOn the following node types: $($QueryObject.nodes)" -Source $source -logname ADU -EventID 9999
				try
				{
			    	ExecuteDistributedPowerShell -nodeList $nodeList -command $command -outputPath $outputPath
				}
				catch
				{
					Write-EventLog -EntryType Error -message "Error Encountered during Distributed PowerShell Query: `'$($QueryObject.name)`' `n`nCommand: $($QueryObject.value) `n`n$($_.exception)" -Source $source -logname ADU -EventID 9999
					Write-Output "Error Encountered during Distributed PowerShell Query: `'$($QueryObject.name)`' `n`n$_" >> $outputpath
					write-error "Error Executing $($QueryObject.name)`nSee ADU Event log for details`n$($_.FullyQualifiedErrorId)" -ErrorAction Continue
				}
		    }
	    "File_Collector"
		    {
			    Write-Host -ForegroundColor Cyan "`nEXECUTING: $($QueryObject.name)"
								
				Write-EventLog -EntryType Information -message "Collecting Files from Filepath: $($QueryObject.value)" -Source $source -logname ADU -EventID 9999
				try
				{
                    if ($QueryObject.value -match "wer")
                    {
			    	    CollectFiles_FolderName -nodeList $FullNodeList -filepath $($QueryObject.value) -outputDir $outputDir -days $($QueryObject.days) -actionName $($QueryObject.name)
                    }
                    else
                    {
			    	    CollectFiles -nodeList $FullNodeList -filepath $($QueryObject.value) -outputDir $outputDir -days $($QueryObject.days) -actionName $($QueryObject.name)
                    }
				}
				catch
				{
					Write-EventLog -EntryType Error -message "Error encountered collecting files: `'$($QueryObject.name)`' `n`nPath: $($QueryObject.value) `n`n$($_.exception)" -Source $source -logname ADU -EventID 9999
					write-error "Error collecting files $($QueryObject.name)`nSee ADU Event log for details`n$($_.FullyQualifiedErrorId)" -ErrorAction Continue	
				}
		    }
        "bundle"
            {			
                #loop through all actions within this option
				$actions = @()
				$actions = ($inputFile.menu.option | ? {$_.name -eq $userinput1}).action.title
				foreach ($action in $actions)
				{
					if ($action -like "*bundle*")
					{#skip
					}
					else{ExecuteAction $UserInput1 $action}
				}
            }
        "custom_bundle"
            {
                #parse out values on the comma
                $splitActions=$($QueryObject.value).Split(",")
            
                #Set Loop Control variables
                $variableIndex=0
                $OptionsCount=$inputFile.menu.option.count

                while($SplitActions[$variableIndex])
                {
                    $currentOption=0

                    #loop to go through options
                    while($CurrentOption -lt $optionsCount)
                    {
                        $totalActions=$inputFile.menu.option[$currentOption].action.count
                        $LcvActionCount=0

                        while(($LcvActionCount -le $totalActions))
                        {
                            #Check for match
                            if($splitActions[$variableIndex] -eq $inputFile.menu.option[$currentOption].action[$LcvActionCount].name)
                            {
                                ExecuteAction $inputFile.menu.option[$currentOption].name $inputFile.menu.option[$currentOption].action[$LcvActionCount].title
								$currentOption++
                                $LCVActionCount++
                            }
                    
                            $LcvActionCount++
                        }
                    $CurrentOption++
                    }

                $variableIndex++
                }
            }
        default {write-Error "COULD NOT FIND AN ACCEPTABLE TYPE NAME IN THE CODE FOR THE TYPE SPECIFIED IN XML: $($QueryObject.type)"}
	}
}

. Diagnostics_Collection