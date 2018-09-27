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
#* Date: [DATE_MDY]
#* Time: [TIME]
#* Issue:
#* Solution:
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
function GetNodeList ([switch]$fqdn,[switch]$HSA=$false,[switch]$HST=$false,[switch]$fab=$false,[switch]$pdw=$false,[switch]$phys=$false,[switch]$cmp=$false,[switch]$ctl=$false,[switch]$full=$false)
{
	#initialize nodeList array
	$nodeList = @()
	
	if($HSA){$nodeList += (Get-ClusterNode | ? {$_.name -like "*-HSA*"}).name}
	if($HST){$nodeList += (Get-ClusterNode | ? {$_.name -like "*-HST*"}).name}
	if($phys){$nodeList += (Get-ClusterNode).name}
	if($fab){$nodeList += (Get-ClusterNode).name; $nodeList += (Get-ClusterGroup | ? {$_.name -like  "*-AD" -or $_.name -like "*-vmm"}).name}
	if($pdw){$nodeList += (Get-clusterGroup | ? {$_.name -like "*-CMP*" -or $_.name -like "*-CTL*" -or $_.name -like "*-MAD*"}).name} 
	if($cmp){$nodeList += (Get-clusterGroup | ? {$_.name -like "*-CMP*"}).name}
	if($ctl){$nodeList += (Get-clusterGroup | ? {$_.name -like "*-CTL*"}).name}
	if($full){$nodeList += (Get-ClusterNode).name; $nodeList += (Get-clusterGroup | ? {$_.name -like "*-*" -and $_.name.length -le 15}).name} 

	#make sure there were no values entered twice
	$nodeList = $nodeList | select -Unique
	
	#if fqdn switch was given then add the fqdn
	if($fqdn)
	{
		$fqdnNodeList = @()
		
		foreach($node in $nodeList)
		{
			#set the domain
			$domain = $node.split("-")[0]
			
			#decide if it's pdw or fab
			if(($node -like "*-HST*") -or ($node -like "*-HSA*") -or ($node -like "*-AD*") -or ($node -like "*-VMM*") -or ($node -like "*-ISCSI*"))
			{
				$FullName = "$node.$domain.fab.local"
			}
			else
			{
				$FullName = "$node.$domain.pdw.local"
			}
			$fqdnNodeList += $FullName
		}
	
		#make sure there were no values entered twice
		$fqdnNodeList = $fqdnNodeList | select -Unique
		return $fqdnNodeList
	}
	
	return $nodeList;
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
#* GetPdwDomainUsername
#* Created: [1/3/2014]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for PDW Domain Username
#*	and return it
#*=============================================
Function GetPdwDomainUsername
{
	$U= Read-host "`nPDW Domain Admin Username"
	return $U
}

#*=============================================
#* GetPdwDomainPassword
#* Created: [1/3/2014]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for PDW domain admin password
#*	and return it
#*=============================================
Function GetPdwDomainPassword
{
	$securePassword = Read-Host "PDW Domain Admin Password" -AsSecureString
	$P = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
	return $P
}
#*=============================================
#* GetFabDomainUsername
#* Created: [1/13/2014]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for fabric Domain Username
#*	and return it
#*=============================================
Function GetFabDomainUsername
{
	$U= Read-host "`nFabric Domain Admin Username"
	return $U
}

#*=============================================
#* GetFabDomainPassword
#* Created: [1/13/2014]
#* Author: Nick Salch
#* Arguments: 
#*=============================================
#* Purpose:
#*	This function will ask the user for fabric domain admin password
#*	and return it
#*=============================================
Function GetFabDomainPassword
{
	$securePassword = Read-Host "Fabric Domain Admin Password" -AsSecureString
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
#*  $pdwDomain - PDW domain name
#*=============================================
#* Purpose:
#*	This function will verify that the PDW credentials.
#*	returns true if good, false if bad
#*=============================================
#Change 1/29/2014: Took out the true/false return. You should
# use try/catch to catch error in your script.
# 1/31/2014: Will ask for creds if they are not passed
Function CheckPdwCredentials
{
	param ($U=$null,$P=$null,$pdwDomain=$null)
	$port = 17001
	write-host "`nChecking PDW Credentials"
	
	#check credentials exist
	if (!$U -or !$P -or !$pdwDomain)
	{
		Write-Error "Paramters were not successfully sent to CheckPdwCredentials function"
		return $false
	}
	
	#check credentials work
    $auth = sqlcmd -S "$pdwDomain-sqlctl01,$port" -U $U -P $P -Q "select @@version" -I
	
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
#* GenerateFullNodeListFromXML
#* Created: [10/22/2013]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose:
#*	This function generates a fabric and PDW nodelist file in
#*	PWD based on all of the nodes it finds in the XMLs
#*=============================================
#Update 1/29/2014 (Nicksalc): Doesn't return true and returns list variable instead of writing to file
Function GenerateFullNodeListFromXML
{
    Try
    {
	[xml]$apdXml = Get-Content "\\$pdwDomain-CTL01\G$\LOG_01\SQLPDW10\AppliancePDWDefinition.xml" -ErrorAction Stop
	[xml]$ahdXml = Get-Content "\\$pdwDomain-CTL01\G$\LOG_01\SQLPDW10\ApplianceHostDefinition.xml" -ErrorAction Stop
	[xml]$afdXml = Get-Content "\\$pdwDomain-CTL01\G$\LOG_01\SQLPDW10\ApplianceFabricDefinition.xml" -ErrorAction Stop
    }
    catch
    {
        Write-Host -ForegroundColor Yellow "`nCan't get XMLs from CTL Share, trying locally..."
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
	
	$FullNodeList=@()
	if ($afdxml.ApplianceFabric.Nodes)
	{
		#version for AU.5 and older
		$FullNodeList+=$ahdXml.ApplianceHost.Topology.Cluster |% {$_.Node.Name}
		$FullNodeList+=$afdXml.ApplianceFabric.Nodes.VmmNode.Name
		$FullNodeList+=$afdXml.ApplianceFabric.Nodes.AdNode.Name
		$FullNodeList+=$afdXml.ApplianceFabric.Nodes.iscsinodes.ChildNodes.name
		$FullNodeList+=$apdXml.AppliancePdw.Topology.Nodes.ChildNodes.name
	}
	elseif ($afdxml.ApplianceFabric.Region)
	{
		#for AU1 and newer
		#version for AU.5 and older
		$FullNodeList+=$ahdXml.ApplianceHost.Appliance.regions.Region | ? {$_.type -eq "Pdw"} | % {$_.clusters.cluster.nodes.node.name}
		$FullNodeList+=$afdXml.ApplianceFabric.Region.nodes.VmmNode.Name
		$FullNodeList+=$afdXml.ApplianceFabric.Region.nodes.AdNode.Name
		$FullNodeList+=$afdXml.ApplianceFabric.Region.nodes.IScsiNodes.IScsiNode.name
		$FullNodeList+=$apdXml.AppliancePdw.Region.Nodes.node.name
	}
	else
	{
		Write-Error "Did not recognize appliance fabric definition XML format, exiting"
	}
	return $FullNodeList				
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
function ExecutePowerShell
{
	param($command=$null,$outputpath=$null)
	
	if(!$command -or !$outputpath)
	{
		Write-Error "Paramters were not successfully sent to ExecutePowershell function"
		return $false
	}
	
    invoke-expression $command | out-file $outputPath
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
	param($nodeList=$null,$command=$null,$outputPath=$null)
	###Need to check parameters
	
	#create the powershell commands as jobs
	$jobArray = @()
	foreach($node in $nodeList)
	{
		$job = Invoke-Command -AsJob -ScriptBlock $command -ComputerName $node
		$jobArray += $job
	}
	
	foreach ($runningJob in $jobArray)
	{
		#pause until the job completes
		while ($runningJob.state -eq "Running" -or $runningJob.state -eq "NotStarted")
		{Start-Sleep 1}
		
		"-----------------------------------" >> "$outputPath"	
		$runningJob.Location >> "$outputPath"
		"-----------------------------------" >> "$outputPath"

		if ($runningJob.state -ne "Completed")
		{$runningJob.state >> "$outputPath"}
		
		Try
		{
			receive-job $runningJob >> "$outputPath"
		}
		catch [System.Management.Automation.Remoting.PSRemotingTransportException]
		{
			Write-Error -ErrorAction Continue "Error encountered connecting to $($RunningJob.location)`n $_.exception"
		}
	}
}

#*=============================================
#* Function: ExecuteParallelDistributedPowerShell2
#* Created: [1/7/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$command
#*	$nodeList
#*=============================================
#* Purpose: Will execute a powershell command to all
#*	nodes in the nodelist in parallel. Named 2 because PDWDiag uses the other one
#*=============================================
function ExecuteParallelDistributedPowerShell2
{
	param($nodeList=$null,$command=$null)
	###Need to check parameters

	#create the powershell commands as jobs
	$jobArray = @()
	foreach($node in $nodeList)
	{
		$job = Invoke-Command -AsJob -ScriptBlock {param([string]$cmd);invoke-expression $cmd} -ArgumentList $command -ComputerName $node
		$jobArray += $job
	}
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
	
		$restulsList += "$runningJOb.location"
		$resultsList +=$results
		
		$results
	}
	#return $resultsList
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
	param($PdwQuery=$null,$U=$null,$P=$null,$pdwDomain=$null,$port="17001",$outputPath=$null)
	###Need to add a check that variables were set

	#Run query against PDW
	#$SQLCmd = sqlcmd -S "$pdwDomain-sqlctl01,$port" -U $U -P $P -Q "$PdwQuery" -I -o $outputpath -s "|" -W -k -w 9999
	if($outputpath)
	{
		#invoke-sqlcmd -query "$PdwQuery" -serverInstance "$pdwDomain-sqlctl01,$port" -username $u -password $P | Export-Csv -NoTypeInformation -Delimiter "|" -path $outputPath
		invoke-sqlcmd -query "$PdwQuery" -serverInstance "$pdwDomain-sqlctl01,$port" -username $u -password $P | Export-Csv -NoTypeInformation -Delimiter "," -path $outputPath
		return
	}
	else
	{
		$sqlcmd = invoke-sqlcmd -query "$PdwQuery" -serverInstance "$pdwDomain-sqlctl01,$port" -username $u -password $P
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

#	sqlcmd -S $node -I -Q "$Query" -o $outputPath -s "|" -W -k -w 9999
	if($outputpath)
	{
		#Invoke-Sqlcmd -ServerInstance "pcss03-cmp01"  -Query "select * from sys.databases"
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
#*  Provide teh path without the drive letter example: perflogs\test\*.txt
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
	
	#get the name of MAD01
	$PdwNodeList = GetNodeList -pdw

	$mad01Name = $PdwNodeList | ? {$_ -like "*-MAD01"}
	$domainName = ($mad01Name.split("-"))[0]

	#Get PDW Version
	#$PdwVersion = Invoke-Command -ComputerName "$mad01Name.$domainName.pdw.local" -ScriptBlock {gwmi win32_product | ? {$_.name -like "Microsoft SQL Server * Parallel Data Warehouse"}}
	
	#$PdwVersion = $PdwVersion.version
	
	#return $PdwVersion
	$PDWVersionInfo = sqlcmd -Q "Select @@Version" -S "$domainName-sqlctl01,17001" -U $u -P $P -I
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
	param($credential=$null)
	
	#get the name of MAD01
	$PdwNodeList = GetNodeList -pdw

	$mad01Name = $PdwNodeList | ? {$_ -like "*-MAD01"}
	$domainName = ($mad01Name.split("-"))[0]
	
	#if creds were specified use those, otherwise use current user
	if($cred)
	{
		$PavVersion = Invoke-Command -credential $cred -ComputerName "$mad01Name.$domainName.pdw.local" -ScriptBlock {gwmi win32_product | ? {$_.name -eq "Microsoft SQL Server PDW Appliance Validator x64"}} 
		$PavVersion = $PavVersion.version
	}
	else
	{
		#Get PDW Version without specifying credentials
		$PavVersion = Invoke-Command -ComputerName "$mad01Name.$domainName.pdw.local" -ScriptBlock {gwmi win32_product | ? {$_.name -eq "Microsoft SQL Server PDW Appliance Validator x64"}} 
		$PavVersion = $PavVersion.version
	}
	
	return $PavVersion
}

#*=============================================
#* Function: GetFabDomainName
#* Created: [1/3/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Returns the name of the Fab domain as found
#* in Get-ClusterNode
#*=============================================
function GetFabDomainName
{
	$nodelist = getNodeList -phys
	$nodelist+=""
	$FabDom = $nodelist
	$FabDom = $fabdom.split("-")[0]

	return $FabDom
}

#*=============================================
#* Function: GetPdwDomainName
#* Created: [1/3/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Returns the name of the PDW domain as found
#* in Get-ClusterGroup
#*=============================================
function GetPdwDomainName
{
	$nodelist = getNodeList -pdw
	$nodelist+=""
	$PdwDom = $nodelist
	$PdwDom = $PdwDom.split("-")[0]

	return $PdwDom
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
	Import-Module SQLPS -DisableNameChecking
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
	###Need to check parameters

	$nodeList = $nodeList | ? {$_ -ne $null}
	#create the powershell commands as jobs
	$jobArray = @()
	foreach($node in $nodeList)
	{	
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

#*=============================================
#* Function: GetFabDomainNameFromXML
#* Created: [4/8/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Will return the Fabric domain name
#* after reading it from the AFD xml
#*=============================================
Function GetFabDomainNameFromXML
{
	[xml]$afd = Get-Content C:\PDWINST\media\ApplianceFabricDefinition.xml
	
	#decide if this is AU1+ or AU.5-
	if ($afd.ApplianceFabric.Nodes)
	{
		#version for AU.5 and older
    	$fabricDomain = $afd.ApplianceFabric.Nodes.AdNode.DomainName
	}
	elseif ($afd.ApplianceFabric.Region)
	{
		#for AU1 and newer
		$fabricDomain = $afd.ApplianceFabric.region.Nodes.AdNode.DomainName
	}
	else
	{
		Write-Error "GetFabDomainNameFromXml: Did not recognize ApplianceFabricDefinition.xml format, exiting"
	}
    return $fabricDomain
}

#*=============================================
#* Function: GetPdwDomainNameFromXML
#* Created: [4/8/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose: Will return the Pdw domain name
#* after reading it from the AFD xml
#*=============================================
Function GetPDWDomainNameFromXML
{
	[xml]$apd = Get-Content C:\PDWINST\media\AppliancePdwDefinition.xml
	
	#decide if this is AU1+ or AU.5-
	if ($apd.AppliancePdw.Topology.Nodes)
	{
		#version for AU.5 and older
    	$pdwDomain = $apd.AppliancePdw.Topology.DomainName
	}
	elseif ($apd.AppliancePdw.Region)
	{
		#for AU1 and newer
    	$pdwDomain = $apd.AppliancePdw.region.name
	}
	else
	{
		Write-Error "GetPdwDomainNameFromXml: Did not recognize AppliancePdwDdefinition.XML format, exiting"
	}
    return $pdwdomain
}

#*============================================
#* Function: LoadPDWDefinitionXMLFromCTL
#* Created: [10/14/2014]
#* Author: Kristine Lange
#*	
#*=============================================
#* Purpose: Load PDW definition XML
#* from the control node
#*=============================================
function LoadPDWDefinitionXMLFromCTL {
    param($WorkloadAdmin)
    [xml]$appliancePDWDefn = Invoke-Command $PDWDomain-CTL01 -Credential $WorkloadAdmin -scriptblock {Get-Content  "G:\LOG_01\SQLPDW10\AppliancePDWDefinition.xml"} -ErrorAction Stop
    return $appliancePDWDefn	
}

#*============================================
#* Function: LoadFabricDefinitionXMLFromCTL
#* Created: [10/14/2014]
#* Author: Kristine Lange
#*	
#*=============================================
#* Purpose: Load Fabric definition XML
#* from the control node
#*=============================================
function LoadFabricDefinitionXMLFromCTL {
    param($WorkloadAdmin)
    [xml]$applianceFabricDefn = Invoke-Command $PDWDomain-CTL01 -Credential $WorkloadAdmin -scriptblock {Get-Content  "G:\LOG_01\SQLPDW10\ApplianceFabricDefinition.xml"} -ErrorAction Stop
    return $applianceFabricDefn	
}	
    
#*============================================
#* Function: LoadHostDefinitionXMLFromCTL
#* Created: [10/14/2014]
#* Author: Kristine Lange
#*	
#*=============================================
#* Purpose: Load Host definition XML
#* from the control node
#*=============================================
function LoadHostDefinitionXMLFromCTL {
    param($WorkloadAdmin)
    [xml]$applianceHostDefn = Invoke-Command $PDWDomain-CTL01 -Credential $WorkloadAdmin -scriptblock {Get-Content  "G:\LOG_01\SQLPDW10\ApplianceHostDefinition.xml"} -ErrorAction Stop	
    return $applianceHostDefn	
}	
