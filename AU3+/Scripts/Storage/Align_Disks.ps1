#* FileName: AlignCsvs.ps1
#*=============================================
#* Script Name: AlignCsvs.ps1
#* Created: [1/7/2013]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*	Cluster must be online
#*  Should be PDW Domain Admin
#* Keywords:
#*=============================================
#* Purpose:
#*	Will check for misaligned CSV's, then fix them  
#*	after prompting user
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Date: [1/29/2014]
#* Issue:
#* Solution:
#*	Event logging added
#*=============================================
. $rootPath\Functions\PdwFunctions.ps1

#Set up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

Try
{
	$physList=@()
	$physList = GetNodeList -FQDN -phys
}
catch
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
}

if(!$physList)
{
	Write-Host "`n"
	Write-Error "***No HSA's Found in the nodelist!***"
	return
}

#Check for misaligned CSVs
$badNodeList=@()
$CsvList=@()
$badCsvList=@()

$CsvList = Get-ClusterSharedVolume

#If this is a V1 hardware appliance, exit
if ($csvList.name -like "*SQL*")
{
	Throw "***V1 HARDWARE DETECTED*** CSV's do not need to be aligned on V1 hardware."
}

foreach ($CSV in $CsvList)
{
	if ($CSV.name.substring(1,2) -ne $CSV.ownernode.name.substring($CSV.ownernode.name.length-2,2))
	{
		$CsvNum = $CSV.name.substring(1,2)
		#check to make sure the name is valid (sometimes CSVs get renamed to "new volume")
		try
		{
			#try and change the number to an int - if it throws an error the data is invalid
			[int]$CsvNum |out-null
		}
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "THE FOLLOWING CSV HAS AN INVALID NAME: $($csv.name)`nFix the name then try operation again"
			Throw "THE FOLLOWING CSV HAS AN INVALID NAME: $($csv.name)`nFix the name then try operation again" 
		}
		
		$newNodeName = $CSV.ownernode.name.split("-")[0] + "-HSA" + $CsvNum
		
		$badNodeList += $newNodeName
		$badCsvList += $CSV
	}
}

#remove duplicates
$badNodeList = $badNodeList | select -Unique 



if($badNodeList)
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Misaligned CSVs found for nodes: $badNodeList"
	Write-Host -ForegroundColor Yellow "`nMisaligned CSVs found for nodes: "$badNodeList
	#foreach($node in $badNodeList){Write-Host $node}
	
 	$input = Read-Host "`nWould you like to align disks that are misaligned? (this is an online operation) (y/n)"
	if ($input -eq 'y')
	{

		foreach ($CSV in $badCsvList)
		{
			$CsvNum = $CSV.name.substring(1,2)
			$newNodeName = $CSV.ownernode.name.split("-")[0] + "-HSA" + $CsvNum
			
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Moving $CSV disks to $newNodeName"
			Write-host -NoNewline "`nMoving $CSV disks to $newNodeName..."
			Try
			{
				$moveResult = $CSV | move-clusterSharedVolume $newNodeName
			}
			catch
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error encountered attempting to move $CSV disks to $newNodeName `n`n $_"
				Write-Error "Failed to move $CSV disks to $newNodeName `n`n $_"
			}
			
			if($moveResult.state -eq "online" -and $moveResult.ownernode.name -eq "$newNodeName")
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Moved $CSV disks to $newNodeName `n`n CSV: $($moveresult.name)`n Current state: $($moveresult.State)`n New Owner: $($moveresult.Ownernode.name)"
				write-host -ForegroundColor Green " Success"
				Write-host "CSV: $($moveresult.name)`t Current state: $($moveresult.State)`t New Owner: $($moveresult.Ownernode.name)"
			}
			else
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error during move, CSV is not in expected state or incorrect owner. CSV: $($moveresult.name)`t Current state: $($moveresult.State)`t Current Owner: $($moveresult.Ownernode.name)"
				Write-Error "Error during move, CSV is not in expected state or incorrect owner. CSV: $($moveresult.name)`t Current state: $($moveresult.State)`t Current Owner: $($moveresult.Ownernode.name)"
			}
		}
	}
}
else
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "***No Misaligned CSVs found***"
	Write-Host -ForegroundColor Green "`n***No Misaligned CSVs found***"
}

$userInput = read-Host "`nRecommended: Would you like to update the storage cache on all physical nodes's? (y/n)"
if($userinput -eq "y")
{
	try
	{
		Write-host "`nUpdating Storage cache across all physical nodes in parallel"
		ExecuteDistributedPowerShell -command {update-hostStorageCache;update-StorageProviderCache -discoverylevel Full} -nodelist $physList
		Write-EventLog -Source $source -LogName "ADU" -EventId 9999 -EntryType Information -message "Storage cache updated on all nodes"
	}
	catch
	{
		Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error Updating storage cache `n`n $_"
		Write-error "Error encountered updating storage cache $_"
	}
}
