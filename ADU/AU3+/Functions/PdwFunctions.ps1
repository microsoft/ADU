#* FileName: PdwFunctions.ps1
#*=============================================
#* Script Name: PdwFunctions.ps1
#* Created: [10/22/2013]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*	Use dot-source notation to use these functions
#* Keywords:
#*=============================================
#* Purpose:
#*	This is a list of functions that are useful when 
#*	dealing with PDW V2
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Date: [10/7/2014]
#* Issue: AU3 Support
#* Solution: All Functions updated to support 
#*  AU3. Not backwards compatible
#*
#*=============================================

#*=============================================
#* FUNCTION LISTINGS
#*=============================================
#* Function: GetNodeList
#* Created: [10/22/2013]
#* Author: Nick Salch
#* Arguments: 
#*	[switch] $HSA - add hsa nodes to the list
#*	[switch] $HST - add hst nodes to the list
#*	[switch] $fab - add fabric nodes to the list
#*	[switch] $pdw - add pdw nodes to the list
#*	[switch] $phys - add physical nodes to the list
#*	[switch] $full - add all nodes to the list
#*	
#*pre-req: assumes you are running from a physical node - could add a check
#*pre-req: assumes the cluster is up
#*=============================================
#* Purpose:
#*	This function returns an array of names to make a nodelist
#* 	based on the nodetypes you specify. You can specify multiple
#*	node types.
#*=============================================
function GetNodeList (	[switch]$useXml=$false,
						[switch]$includeHdi=$false,
						[switch]$fqdn=$false,
						[switch]$HSA=$false,
						[switch]$HST=$false,
						[switch]$fab=$false,
						[switch]$pdw=$false,
						[switch]$phys=$false,
						[switch]$cmp=$false,
						[switch]$ctl=$false,
						[switch]$HDN=$false,
						[switch]$HSN=$false,
						[switch]$HHN=$false,
						[switch]$HMN=$false,
						[switch]$fullPDW=$false,
						[switch]$fullHDI=$false,
						[switch]$full=$false)
{
	if ($HDN -or $HHN -or $HMN -or $fullHDI)
	{
		$includeHDI = $true
	}
	#initialize nodeList array
	$nodeList = @()
	
	#Get the short domain name 
	$fabReg = GetFabRegionName
	
	if (!$useXml)
	{
		#PDW Section
		if($HSA){$nodeList += (Get-ClusterNode | ? {$_.name -like "*-HSA*"}).name}
		if($HST){$nodeList += (Get-ClusterNode | ? {$_.name -like "*-HST*"}).name}
		if($phys){$nodeList += (Get-ClusterNode).name}
		if($fab){$nodeList += (Get-ClusterNode).name; 
				$nodeList += (Get-ClusterGroup | ? {$_.name -like  "*-WDS" -or $_.name -like "*-vmm"}).name
				$nodeList += "$fabReg-AD01","$fabReg-AD02"}
		if($pdw){$nodeList += (Get-clusterGroup | ? {$_.name -like "*-CMP*" -or $_.name -like "*-CTL*"}).name} 
		if($cmp){$nodeList += (Get-clusterGroup | ? {$_.name -like "*-CMP*"}).name}
		if($ctl){$nodeList += (Get-clusterGroup | ? {$_.name -like "*-CTL*"}).name}
		if($full -or $fullPDW){$nodeList += (Get-ClusterNode).name;
				$nodeList += (Get-clusterGroup | ? {$_.name -like "*-*" -and $_.name.length -le 15}).name;
				$nodeList += "$fabReg-AD01"
				if ($nodeList -contains "$fabReg-HST02") {$nodeList += "$fabReg-AD02"} }

		#HDI section
		#HDI does not yet have FQDN or -useXML functionality
		if ($includeHDI)
		{
			$HDICluster= "$fabreg-WFOHST02" #((Get-Cluster).name).replace("-WFOHST01","-WFOHST02")
			if (Get-cluster -name $HDICluster -erroraction silentlycontinue)
			{
				if($HSA){$nodeList += (Get-Cluster -name $HDICluster | Get-ClusterNode | ? {$_.name -like "*-HSA*"}).name}
				if($HST){$nodeList += (Get-Cluster -name $HDICluster | Get-ClusterNode | ? {$_.name -like "*-HST*"}).name}
				if($phys){$nodeList +=(Get-Cluster -name $HDICluster | Get-ClusterNode).name}
				if($HDN){$nodeList += (Get-Cluster -name $HDICluster | Get-clusterGroup | ? {$_.name -like "*-HDN*"}).name} 
				if($HSN){$nodeList += (Get-Cluster -name $HDICluster | Get-clusterGroup | ? {$_.name -like "*-HSN*" }).name} 
				if($HHN){$nodeList += (Get-Cluster -name $HDICluster | Get-clusterGroup | ? {$_.name -like "*-HHN*"}).name} 
				if($HMN){$nodeList += (Get-Cluster -name $HDICluster | Get-clusterGroup | ? {$_.name -like "*-HMN*"}).name} 
				if($full -or $fullHDI){$nodeList +=(Get-Cluster -name $HDICluster | Get-ClusterNode).name; 
						$nodeList += (Get-Cluster -name $HDICluster | Get-clusterGroup | ? {$_.name -like "*-*" -and $_.name.length -le 15}).name}
			}
			else {write-debug "No HDI Cluster found, continuing without it"}
		}
	}
	else
	{
		#get the region name for trying the CTL node share
		$Pdwreg = GetPdwRegionName
		
		Try
	    {
			[xml]$apdXml = Get-Content "\\$pdwReg-CTL01\G$\LOG_01\SQLPDW10\AppliancePDWDefinition.xml" -ErrorAction Stop
			[xml]$ahdXml = Get-Content "\\$pdwReg-CTL01\G$\LOG_01\SQLPDW10\ApplianceHostDefinition.xml" -ErrorAction Stop
			[xml]$afdXml = Get-Content "\\$pdwReg-CTL01\G$\LOG_01\SQLPDW10\ApplianceFabricDefinition.xml" -ErrorAction Stop
	    }
	    catch
	    {
	        Write-Host -ForegroundColor Yellow "`nCan't get XMLs from CTL Share, using local copy..."
	        Try
	        {
	        	[xml]$apdXml = Get-Content "c:\PDWINST\Media\AppliancePDWDefinition.xml" -ErrorAction Stop
			    [xml]$ahdXml = Get-Content "c:\PDWINST\Media\ApplianceHostDefinition.xml" -ErrorAction Stop
			    [xml]$afdXml = Get-Content "c:\PDWINST\Media\ApplianceFabricDefinition.xml" -ErrorAction Stop
	        }
	        Catch
	        {
	            Write-Error "Not able to Obtain XMLs from CTL share or locally."
	            Return $false
	        }

	        if($apdXml -and $ahdXml -and $afdXml)
	        {write-host -ForegroundColor Green "XMLs Loaded"}
	    }		
	
		if ($afdXml.ApplianceFabric.Region.nodes.WdsNode)
		{
			#Au3 and newer
			if ($full){$phys=$true;$fab=$true;$pdw=$true}
			if($fab){$phys=$true;$vmm=$true;$WDS=$true;$iscsi=$true;$ad=$true}
			if($pdw){$cmp=$true;$ctl=$true}
			if($phys){$HSA=$true;$HST=$true}
			if($HSA){$nodeList +=($ahdXml.ApplianceHost.Appliance.regions.Region | ? {$_.type -eq "Pdw"}).clusters.cluster.nodes.node.name | ? {$_ -like "*HSA*"}}
			if($HST){$nodeList +=($ahdXml.ApplianceHost.Appliance.regions.Region | ? {$_.type -eq "Pdw"}).clusters.cluster.nodes.node.name | ? {$_ -like "*HST*"}}
			if($cmp){$nodeList += $apdXml.AppliancePdw.Region.Nodes.node.name | ? {$_ -like "*-CMP*"}}
			if($ctl){$nodeList += $apdXml.AppliancePdw.Region.Nodes.node.name | ? {$_ -like "*-CTL*"}}
			if($AD){$nodeList += "$fabReg-AD01","$fabReg-AD02"} 
			if($VMM){$nodeList += "$fabReg-VMM"} 
			if($WDS){$nodeList += "$fabReg-WDS"}
			if($iscsi){$nodeList+=$afdXml.ApplianceFabric.Region.nodes.IScsiNodes.IScsiNode.name}
		}
		else
		{
			Write-Error "Did not recognize appliance fabric definition XML format, exiting"
		}
	}
	
	#if fqdn switch was given then add the fqdn to all nodes in the list
	if($fqdn)
	{
		$fqdnNodeList = @()
		
		$domain = GetDnsDomainName
		
		foreach($node in $nodeList)
		{
			$FullName = "$node.$domain"
			
			$fqdnNodeList += $FullName
		}
		
		$nodeList = $fqdnNodeList
	}
	
	#make sure there were no values entered twice
	$nodeList = $nodeList | select -Unique
	
	return $NodeList
}

#*=============================================
#* GetDNSDomainName
#* Created: [10/7/2014]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
<#	This function will get the full DNS Domain
	name from the current node
=============================================#>
Function GetDNSDomainName
{
	return [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().name
}

#*=============================================
#* GetPdwUsername
#* Created: [10/24/2013]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for PDW Username
#*	and return it
#*=============================================
Function GetPdwUsername
{
	$U= Read-host "`nPDW Username"
	return $U
}
#*=============================================
#* GetPdwPassword
#* Created: [10/24/2013]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for PDW password
#*	and return it
#*=============================================
Function GetPdwPassword
{
	$securePassword = Read-Host "PDW Password" -AsSecureString
	$P = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
	return $P
}


#*=============================================
#* GetDomainUsername
#* Created: [10/7/2014]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for Domain Username
#*	and return it
#*=============================================
Function GetDomainUsername
{
	$U= Read-host "`nDomain Admin Username"
	return $U
}

#*=============================================
#* GetDomainPassword
#* Created: [10/7/2014]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for domain admin password
#*	and return it
#*=============================================
Function GetDomainPassword
{
	$securePassword = Read-Host "Domain Admin Password" -AsSecureString
	$P = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
	return $P
}
#*=============================================
#* Function: CheckPdwCredentials
#* Created: [10/24/2013]
#* Edited: [1/3/2014]
#* Author: Nick Salch
#* Arguments: 
#*	$u - PDW username (optional)
#*	$p - PDW password (optional)
#*=============================================
#* Purpose:
#*	This function will verify that the PDW credentials.
#*	returns true if good, false if bad
#*=============================================
#Change 
# 1/29/2014: Took out the true/false return. You should use try/catch to catch error in your script.
# 1/31/2014: Will ask for creds if they are not passed
# 10/7/2014: Gets pdw region by itself instead of asking for it
Function CheckPdwCredentials
{
	param ($U=$null,$P=$null)
	$port = 17001
	write-host "`nChecking PDW Credentials"
	
	$pdwReg = GetPdwRegionName
	
	#check credentials exist
	if (!$U -or !$P -or !$pdwReg)
	{
		Write-Error "Paramters were not successfully sent to CheckPdwCredentials function"
		return $false
	}
	
	#check credentials work
    $auth = sqlcmd -S "$pdwReg-ctl01,$port" -U $U -P $P -Q "select @@version" -I
	
	if ($auth | select-string "Microsoft Corporation Parallel Data Warehouse" ) 
	{
        write-host -ForegroundColor Green "PDW Credentials Verified"
		return $true
	}
    else
    {
		return $false
    }
}

#*=============================================
#* Function: ExecutePowerShell
#* Created: [10/28/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$command
#*	$outputPath
#*=============================================
#* Purpose: Runs a powershell command and writes the
#*	output to a file at the path specified. 
#*=============================================
#* Modified 1/31/2014 (nicksalc): use invoke-expression instead of calling powershell again
#* Modified 10/13/2014 (nicksalc): made $outputPath optional - returns results otherwise
function ExecutePowerShell
{
	param($command=$null,$outputpath=$null)
	
	if(!$command)
	{
		Write-Error "`$command was not successfully sent to ExecutePowershell function"
		return $false
	}
	
	if($outputpath)
	{
    	invoke-expression $command | out-file $outputPath
	}
	else
	{
		invoke-expression $command
	}
}

#*=============================================
#* Function: ExecuteDistributedPowerShell
#* Created: [10/28/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$command
#*	$outputPath
#*=============================================
#* Purpose: Will execute a powershell command to all
#*	nodes in the nodelist in parallel
#*=============================================
function ExecuteDistributedPowerShell
{
	param($nodeList=$null,[string]$command=$null,[string]$outputPath=$null)
	
	#convert the command string to a scriptblock
	$sb = $ExecutionContext.InvokeCommand.NewScriptBlock($command)
	
	#create the powershell commands as jobs
	$jobArray = @()
	foreach($node in $nodeList)
	{
		$job = Invoke-Command -AsJob -ScriptBlock $sb -ComputerName $node
		$jobArray += $job
	}
	
	if($outputpath)
	{
		foreach ($runningJob in $jobArray)
		{
			#pause until the job completes
			while ($runningJob.state -eq "Running" -or $runningJob.state -eq "NotStarted")
			{Start-Sleep 1}
			

			"-----------------------------------" >> "$outputpath"
			$runningJob.Location >> "$outputPath"
			"-----------------------------------" >> "$outputpath"

			if ($runningJob.state -ne "Completed")
			{$runningJob.state >> "$outputpath"}
			
			Try
			{
				receive-job $runningJob >> "$outputpath"
			}
			catch [System.Management.Automation.Remoting.PSRemotingTransportException]
			{
				Write-Error -ErrorAction Continue "Error encountered connecting to $($RunningJob.location)`n $_.exception"
			}
		}
	}
	else
	{
		$resultsList=@()
		foreach ($runningJob in $jobArray)
		{
			write-host -NoNewline -ForegroundColor Cyan "`n$($runningJob.Location)"
			#pause until the job completes
			while ($runningJob.state -eq "Running" -or $runningJob.state -eq "NotStarted")
			{}	
		
			#Check/output the completed state
			if ($runningJob.state -ne "Completed")
			{Write-host -ForegroundColor Red " $runningJob.state"}
			else{Write-Host -ForegroundColor Green " Completed"}

			$results = receive-job $runningJob
		
			#$restulsList += "$($runningJOb.location)"
			#$resultsList +=$results
				
			$results
		}
	}
}

#*=============================================
#* Function: ExecutePdwQuery
#* Created: [10/28/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$command
#*	$outputPath
#*=============================================
#* Purpose: Executes a query against PDW and outputs
#*	the results to the path specified. Results are 
#*	pipe delimited
#*=============================================
#* Modified 1/31/2014 (nicksalc): use invoke-sqlcmd
function ExecutePdwQuery 
{
	param($PdwQuery=$null,$U=$null,$P=$null,$port=$null,$outputPath=$null)
	
	#check that params were set
	if (!$PdwQuery -or !$U -or ! $P -or !$port)
	{
		Write-Error "Query, username, password, and/or port number not successfully sent to function"
	}

	$PdwReg = GetPdwRegionName 
	
	#Run query against PDW
	if($outputpath)
	{
		invoke-sqlcmd -query "$PdwQuery" -serverInstance "$PdwReg-sqlctl01,$port" -username $u -password $P -QueryTimeout 100 | Export-Csv -NoTypeInformation -Delimiter "," -path $outputPath
		return
	}
	else
	{
		$sqlcmd = invoke-sqlcmd -query "$PdwQuery" -serverInstance "$PdwReg-sqlctl01,$port" -username $u -password $P
		return $sqlcmd
	}
	
}

#*=============================================
#* Function: ExecuteSqlQuery
#* Created: [10/28/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$command
#*	$outputPath
#*=============================================
#* Purpose: executes a sql query against the node
#* 	specified and outputs the results to path specified.
#*	results are Pipe - delimited
#*=============================================
function ExecuteSqlQuery
{
	param($node=$null,$Query=$null,$U=$null,$P=$null,$outputPath=$null)
	###Need to add a check that variables were set

	if($outputpath)
	{
		invoke-sqlcmd -query "$Query" -serverInstance "$node" | Export-Csv -NoTypeInformation -Delimiter "," -path $outputPath
		return
	}
	else
	{
		$sqlcmd = invoke-sqlcmd -query "$Query" -serverInstance $node
		return $sqlcmd
	}
}

#*=============================================
#* Function: CollectFiles
#* Created: [10/28/2013]
#* Edited: [1/3/2014]
#* Author: Nick Salch
#* Arguments: 
#*	$nodeList
#*	$filePath
#*	$outputdir - directly where output will be placed
#*	$days - only get files newer than this many days. If it doesn't fall in the range it will grab most recent
#*=============================================
#* Purpose: Collects files in the path provided
#*	and copies them to the output path provided
#*  Provide the path without the drive letter example: perflogs\test\*.txt
#*=============================================
function CollectFiles
{
	param($nodeList=$null,$filepath=$null,$outputDir=$null,$days=$null,$actionName=$null)
	if((!$nodelist) -or (!$filepath) -or (!$outputDir) -or (!$days))
	{
		Write-Host -ForegroundColor Red "Variable not set for CollectFiles function"
		return $false
	}

	#set up a drive letter array of possible choiced G-N (nodes 1-10) - still need all drives for V2 on V1
	$driveList = ("C$","Z$","G$","H$","I$","J$","K$","L$","M$","N$","O$","P$")
	$now = get-date
	
	foreach ($server in $nodelist)
	{
		foreach ($driveLetter in $driveList)
		{
			if(Test-Path "\\$server\$driveLetter\$filepath")
            {
                #mkdir -force "$outputDir\$server\$actionName" | Out-Null
                mkdir -force "$outputDir\$actionName" | Out-Null
                $FileList=$NULL

				$fileList = Get-ChildItem "\\$server\$driveLetter\$filePath" | where {$_.lastWriteTime -ge $now.AddDays(-$days)}

				#if that was empty, grab the one with newest date
				if (!$fileList) 
				{
					$FileList=(get-childitem "\\$server\$driveLetter\$filePath"|sort-object lastWriteTime -desc )[0]
				}
				
				#Write-Host "Copying to $outputDir\$actionName\$server_$($_.name)"

				#Copy-Item -Recurse $FileList "$outputDir\$server\$actionName" -Force | Out-Null
                foreach($file in $fileList)
                {
                    if($file.name -notlike "*$server*")
                    {
                        "$outputDir\$actionName\$server-$($file.name)"
                        copy-item -recurse $file.fullname "$outputDir\$actionName\$server-$($file.name)" -Force | out-null
                    }
                    else
                    {
                        "$outputDir\$actionName\$($file.name)"
                        Copy-Item -Recurse $file "$outputDir\$actionName" -Force | Out-Null
                    }
                }
                #$fileList | % {"$outputDir\$actionName\$server-$($_.name)";copy-item -recurse $_.fullname "$outputDir\$actionName\$server-$($_.name)" -Force | out-null} 
            }
		}
	}
}

#*=============================================
#* Function: CollectFiles_FolderName
#* Created: [09/14/2018]
#* Edited: []
#* Author: Simon Facer
#* Based on CollectFiles
#*   Adds functionality to include the last SubFolder name
#*   Based on a need to collect WER (Windows Error Report) files, where the files are all named the same,
#*   but with a different folder name
#* Arguments: 
#*	$nodeList
#*	$filePath
#*	$outputdir - directly where output will be placed
#*	$days - only get files newer than this many days. If it doesn't fall in the range it will grab most recent
#*=============================================
#* Purpose: Collects files in the path provided
#*	and copies them to the output path provided
#*  Provide the path without the drive letter example: perflogs\test\*.txt
#*=============================================
function CollectFiles_FolderName
{

	param($nodeList=$null,$filepath=$null,$outputDir=$null,$days=$null,$actionName=$null)
	if((!$nodelist) -or (!$filepath) -or (!$outputDir) -or (!$days))
	{
		Write-Host -ForegroundColor Red "Variable not set for CollectFiles function"
		return $false
	}
	$now = get-date
    $driveLetter = "C$"
$nodelist	
	foreach ($server in $nodelist)
	{
        $Files = $null
        $PathIdx = ($FilePath).split("\").count - 1
        $FileNameSearch = ($FilePath).split("\")[$PathIdx]
        $FileNameSearchPath = "\\$server\$driveLetter\" + $filepath.Substring(0,($filepath.Length - $FileNameSearch.Length) - 1)
        $FileList = Get-ChildItem -path $FileNameSearchPath -Include $FileNameSearch -Recurse -ErrorAction SilentlyContinue

		if($FileList.Count -gt 0) {
            mkdir -force "$outputDir\$actionName" | Out-Null

            foreach($file in $fileList) {
                $FilePath = $file.DirectoryName
                $PathIdx = ($FilePath).split("\").count - 1
                $FolderLastPath = ($FilePath).split("\")[$PathIdx]
                mkdir -force "$outputDir\$actionName\$server\$FolderLastPath" | Out-Null
                "$outputDir\$actionName\$server\$FolderLastPath\$($file.name))"
                $FileDateTime = (($file.CreationTime).Year).ToString() + (($file.CreationTime).Month).ToString("00") + (($file.CreationTime).Day).ToString("00") + "_" + (($file.CreationTime).Hour).ToString("00") + (($file.CreationTime).Minute).ToString("00") + (($file.CreationTime).Second).ToString("00") + "."
                copy-item -recurse $file.fullname "$outputDir\$actionName\$server\$FolderLastPath\$FileDateTime$($file.name)" -Force | out-null
              }
          }
      }
  }

#*=============================================
#* Function: GetPdwVersion
#* Created: [10/29/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$command
#*	$outputPath
#*=============================================
#* Purpose: Returns the PDW Version installed
#*	as reported by win32_products on MAD01
#*=============================================
function GetPdwVersion
{
	param($u=$null,$p=$null)
	if(!$U -or !$P)
	{
		Write-Error "Username and/or password not sent to GetPdwVersion function"
	}
	
	$Pdwreg = GetPdwRegionName
	
	#return $PdwVersion
	$PDWVersionInfo = sqlcmd -Q "Select @@Version" -S "$Pdwreg-sqlctl01,17001" -U $u -P $P -I
	
	#parse out just the version number
	$PdwVersion = $PDWVersionInfo.split(" ") | select-string -Pattern "\d{1,2}\.\d{1,2}\.\d{1,4}\.\d{1,2}"
	$PdwVersion = $PdwVersion.toString()
	
	return $PDWVersion
}

#*=============================================
#* Function: GetPavVersion
#* Created: [10/29/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$command
#*	$outputPath
#*=============================================
#* Purpose: Returns the PAV Version installed
#*	as reported by win32_products on MAD01
#*=============================================
function GetPavVersion
{
	param($cred=$null)
	#need to change this to use CTL01
	$Ctl01Name = GetNodeList -ctl
	
	#Get PDW Version without specifying credentials
	$PavVersion = Invoke-Command -ComputerName "$CTL01Name" -ScriptBlock {gwmi win32_product | ? {$_.name -eq "Microsoft SQL Server PDW Appliance Validator x64"}} 
	$PavVersion = $PavVersion.version
	
	return $PavVersion
}

#*=============================================
#* Function: GetFabRegionName
#* Created: [10/7/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Returns the name of the Fab region 
#* 	using local hostname (always a physical)
#*=============================================
function GetFabRegionName
{
	#this tool is always ran from a host so we can just use hostname
	$hostname = hostname
	$FabReg = $hostname.split("-")[0]

	return $FabReg
}

#*=============================================
#* Function: GetPdwRegionName
#* Created: [10/7/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Returns the name of the PDW domain as found
#* in XML
#*=============================================
function GetPdwRegionName
{
	#get the name from the XML
	[xml]$apdXml= Get-Content "C:\PDWINST\MEDIA\AppliancePdwDefinition.xml"

	$PdwList = $apdXml.AppliancePdw.Region.nodes.Node.name #using V1 xml for now
	#$PdwList = $apdXml.AppliancePdw.Region.Nodes.node.name #V2 version
	$Pdwreg = (($PdwList | ? {$_ -like "*-CTL01"}).split("-"))[0]

	return $Pdwreg
}

#*=============================================
#* Function: GetHardwareVendor
#* Created: [1/8/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Returns the hardware vendor of the 
#* server it is run on 
#*=============================================
Function GetHardwareVendor
{
	return (gwmi win32_systemenclosure).manufacturer
}

#*=============================================
#* Function: LoadSqlPowerShell
#* Created: [2/5/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: This loads SQL PowerShell then drops
#* back to the previous directory
#*=============================================
Function LoadSqlPowerShell
{
	Push-Location
    if ((Get-Module -Name SQLServer).count -gt 0) {
        Write-EventLog -entrytype Information -Message "Skipping Import-Module SQLPS, Module SQLServer is already imported" -Source $source -LogName ADU -EventId 9999
      }
    else {
    	Import-Module SQLPS -DisableNameChecking
      }
       
	Pop-Location
}

#*=============================================
#* Function: CheckNodeConnectivity
#* Created: [2/7/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Will return an array of nodes from the nodelist
#* provided that are not reachable
#*=============================================
function CheckNodeConnectivity
{
	param([array]$nodeList=$null)
	
	#check param was sent
	if(!$nodeList)
	{
		Write-Error "Nodelist not sent to CheckNodeConnectivity function"
	}
	
	#remove nulls from the list
	$nodeList = $nodeList | ? {$_ -ne $null}
	
	#create the powershell commands as jobs
	$jobArray = @()
	foreach($node in $nodeList)
	{	
		#run it everywhere except localhost
		if($node -notlike "$(Invoke-Expression hostname)*")
		{
			$jobArray += Test-Connection -ComputerName $node -Count 1 -AsJob
		}
	}
		
	$resultsList=@()
	$unreachableNodes=@()
	foreach ($runningJob in $jobArray)
	{
		#pause until the job completes
		while ($runningJob.state -eq "Running" -or $runningJob.state -eq "NotStarted")
		{Start-Sleep 1}	
	
		$jobResult= Receive-Job $runningJob

		if($jobResult.statusCode -ne 0)
		{
			$unreachableNodes+=$jobResult.address
		}
	}
	return $unreachableNodes
}
