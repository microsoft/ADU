#* FileName: Generate_CSV_From_XMLs_BETA.ps1
#*=============================================
#* Script Name: Generate_CSV_From_PDW_XMLs.ps1
#* Created: [9/9/15]
#* Author: David Lyth
#* Revamped for ADU by: Nick Salch
#* Company: Microsoft
#* Email: David.Lyth@Microsoft.com
#* Nick.Salch@Microsoft.com
#* Keywords:
#*=============================================
#* Purpose: Creates a CSV file that has all of the IPs
#* that are kept in the PDW XML files
#*=============================================

#Set up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

$XmlPath = "C:\PDWINST\Media"
$outputPath = "D:\PDWDiagnostics\GenCsvFromXmls\"
mkdir -force $outputPath |Out-Null
$timestamp = get-date -Format MMddyy-hhmmss
$outputFile = "$outputPath\ApplianceDetails_$timestamp.csv"
Write-Host -ForegroundColor Cyan "================================"
Write-Host -ForegroundColor Cyan "= Generate CSVs From Xmls BETA ="
Write-Host -ForegroundColor Cyan "================================"
Write-Host "This tool will create an excel-friendly CSV file that contains all of the IP information 
it can gather from the PDW/HDI XMLs. 

This tool is in beta state and has not been fully tested on all hardware vendors"


# hash table of rack information
#$Racktable = @{}
#$hpdata.ApplianceInfo.regions.region.nodes.node | foreach { $racktable[$_.name] = $_.RackId + ' ' + $_.Location }


#Test-path the XML's and if it finds them then get-content
Foreach ($path in "$xmlPath\ApplianceFabricDefinition.xml",
"$XmlPath\ApplianceHostDefinition.xml",
"$XmlPath\AppliancePdwDefinition.xml",
"$xmlPath\AppliancehdiDefinition.xml",
"$xmlPath\HPApplianceDetails.xml")
{
	if (Test-Path $path)
	{
		Write-Host -ForegroundColor Green "`nWorking on $path..."
		$currXml = [xml](Get-Content $path)
		
		switch (($currXml | get-member -MemberType property | ? {$_.name -like "Appliance*"}).name)
		{
			"ApplianceFabric"	
			{
				Write-Host "Finding Fabric VMs..."
				
				#Fabric VMs ...hardcoded categories for now
				$currXml.ApplianceFabric.region.nodes.adnodes.adnode | 
				    select @{Expression={$_.name};label='ServerName'},
				           @{Expression={$_.ethernet};label='Ethernet'},
				           @{Expression={$_.ib1};label='IB1'},
				           @{Expression={$_.ib2};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={''};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
				
				$currXml.ApplianceFabric.region.nodes.vmmnode | 
				    select @{Expression={$_.name};label='ServerName'},
				           @{Expression={$_.ethernet};label='Ethernet'},
				           @{Expression={$_.ib1};label='IB1'},
				           @{Expression={$_.ib2};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={''};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
					
				$currXml.ApplianceFabric.region.nodes.iscsinodes.IScsiNode | 
				    select @{Expression={$_.name};label='ServerName'},
				           @{Expression={$_.ethernet};label='Ethernet'},
				           @{Expression={$_.ib1};label='IB1'},
				           @{Expression={$_.ib2};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={''};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
			}
			"ApplianceHost"		
			{
				Write-Host "Finding Host Servers..."
				
				# physical nodes
				$currXml.ApplianceHost.Appliance.Regions.region.clusters.cluster.nodes.node |
				    select @{Expression={$_.name};label='ServerName'},
				           @{Expression={$_.ethernet};label='Ethernet'},
				           @{Expression={$_.IB1};label='IB1'},
				           @{Expression={$_.IB2};label='IB2'},
				           @{Expression={$_.BmcAddress};label='BMC'},
				           @{Expression={"TBA"};label='Serial'},
				           @{Expression={$racktable.$($_.name.Substring($_.name.IndexOf('-')))};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
			}
			"AppliancePDW"
			{
				Write-Host "Finding PDW Servers..."
				
				# PDW VMs
				$currXml.AppliancePdw.Region.Nodes.node |
				    select @{Expression={$_.name};label='ServerName'},
				           @{Expression={$_.ethernet};label='Ethernet'},
				           @{Expression={$_.IB1};label='IB1'},
				           @{Expression={$_.IB2};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={''};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
			}
			"ApplianceHdi"
			{
				Write-host "Finding HDI Server"
				
				#HDI VMs
				$currXml.Appliancehdi.Region.Nodes.node |
				    select @{Expression={$_.name};label='ServerName'},
				           @{Expression={$_.ethernet};label='Ethernet'},
				           @{Expression={$_.IB1};label='IB1'},
				           @{Expression={$_.IB2};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={''};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
			}
			"HpApplainceDetails"
			{
				Write-Host "Reading HP Appliance Details file"
				
				#non-server items...switches, etc
				$currXml.ApplianceInfo.ETH_Switches.Eth_Switch | 
				   select @{Expression={'Ethernet Switch #' + $_.switchid};label='ServerName'},
				           @{Expression={$_.switchIP};label='Ethernet'},
				           @{Expression={''};label='IB1'},
				           @{Expression={''};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={$_.rackid + ' ' + $_.location};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
					
				$currXml.ApplianceInfo.IB_Switches.IB_Switch | 
				   select @{Expression={'IB Switch #' + $_.switchid};label='ServerName'},
				           @{Expression={$_.switchIP};label='Ethernet'},
				           @{Expression={''};label='IB1'},
				           @{Expression={''};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={$_.rackid + ' ' + $_.location};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
					
				$currXml.ApplianceInfo.IB_Switches.IB_Switch | 
				   select @{Expression={'IB Switch #' + $_.switchid};label='ServerName'},
				           @{Expression={$_.switchIP};label='Ethernet'},
				           @{Expression={''};label='IB1'},
				           @{Expression={''};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={$_.rackid + ' ' + $_.location};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
					
				$currXml.ApplianceInfo.PDUs.PDU | 
				   select @{Expression={'PDU #' + $_.pduid};label='ServerName'},
				           @{Expression={$_.pduIP};label='Ethernet'},
				           @{Expression={''};label='IB1'},
				           @{Expression={''};label='IB2'},
				           @{Expression={''};label='BMC'},
				           @{Expression={""};label='Serial'},
				           @{Expression={$_.rackid + ' ' + $_.location};label='Rack'}  |
				    export-csv -append -NoTypeInformation -path $outputFile
			}
			
		}
	}
	else 
	{
		Write-Host -ForegroundColor Red "`nCould not find $path"
	}
}

Write-Host "`nOutput found at $outputFile"








