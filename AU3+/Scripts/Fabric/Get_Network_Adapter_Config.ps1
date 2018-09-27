#* FileName: GetNetworkAdapterConfig.ps1
#*=============================================
#* Script Name: GetNetworkAdapterConfig.ps1
#* Created: [1/6/2014]
#* Author: Kristine Lange
#* Company: Microsoft
#* Email: Krlange@microsoft.com
#* Reqrmnts:
#*	Cluster must be up
#* 
#* Keywords:
#*=============================================
#* Purpose: Retrieves the network adapter for all nodes in the appliance
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 1/10/2014 1:50 PM
#* Changes:
#* 1. Write output file
#* 2. Remove IPV6 IPs
#* 3. Validate DHCP against XML
#* 4. Add progress report
#* 
#* Modified: 1/20/2014 3:40 PM
#* 1. Validate DHCP against Enterprise NIC instead of XML because the XML may be wrong.
#*    Validation against XML will be moved to Publish XML tool.
#* 
#* Modified 1/30/2014
#* 1. Added logging to the event log
#* 2. Added some error catching
#* 3. Changed output slightly
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Variables
$CurrTime = get-date -Format MMddyy-hhmmss
$DHCPItems = @("ScopeId", "StartRange", "EndRange", "SubnetMask")
$DHCPCheckItems = @()

#Output file

$OutputFile = "D:\PdwDiagnostics\NetworkConfig\NetworkConfig_$CurrTime.txt"
if (!(test-path "D:\PdwDiagnostics\NetworkConfig"))
{
    New-item "D:\PdwDiagnostics\NetworkConfig" -ItemType Dir | Out-Null
}
if (!(test-path $OutputFile))
{
    New-Item $OutputFile -ItemType File|out-null
}

#Creating node list
Write-host "`nCreating node list...`n"
$nodelist = GetNodeList -full

#Main code
Function GetNetworkAdapterConfig
{
    foreach ($node in $nodelist)
    {
	    Write-Host "Retrieving network adapter for $node..."
        "---------------------------------"| out-file -append $OutputFile
		$node | out-file -append $OutputFile
		"---------------------------------"| out-file -append $OutputFile

        # Retrieve network adapter config
        # Only return IPV4 IPs
		try
		{
    		Invoke-Command $node -SCRIPTBLOCK {[regex]$ipv4="\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}";gwmi win32_networkadapterconfiguration | Where-Object  {$_.ipaddress}|ft Description, @{Expression={$_.IPaddress -match $ipv4};Label="IPAddress"} , @{Expression={$_.IPSubnet -match $ipv4};Label="Subnet"}, @{Expression={$_.DefaultIPGateway -match $ipv4};Label="Default Gateway"},DNSServerSearchorder -AutoSize -Wrap}|out-file -append $OutputFile
		}
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Problem connecting to $node `n`n $($_.exception)"
			Write-Error "Problem connecting to $node `n`n $($_.exception)" -ErrorAction Continue 
		}
	   
	    if ($node -like "*-WDS")
        {
            Write-host "Getting DHCP server scope from $node..."
			try
			{
            	$DHCPscope = Invoke-Command $node -SCRIPTBLOCK {Get-DhcpServerv4Scope|where {$_.name -eq "Enterprise"}}
				$DHCPScope | select ScopeID,SubnetMask,Name,State,StartRange,EndRange,LeaseDuration | ft |out-file -append $OutputFile        
				$DHCPScopeID = $DHCPscope.ScopeId
            	$DHCPStartRange = $DHCPscope.StartRange
            	$DHCPEndRange = $DHCPscope.EndRange
            	$DHCPSubnetMask = $DHCPscope.SubnetMask
			}
			catch
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error getting DHCP scope from $node `n`n $($_.exception)"
				Write-Error "Error getting DHCP scope from $node `n`n $($_.exception)" -ErrorAction Continue 
			}
             

            #Compare DHCP scope to Enterprise NIC IP and subnet
			
			try
			{
				$EnterpriseNic = Invoke-Command $node -SCRIPTBLOCK {gwmi Win32_NetworkAdapter |Where-Object {$_.netconnectionid -like "*VMSEthernet*"}|% {$_.netconnectionid;$_.GetRelated('Win32_NetworkAdapterConfiguration')}}              
				$EnterpriseNicShortened = (($EnterpriseNic.ipaddress).split(".")[0..2] -join ".")
				$EnterpriseNicSubnetShortened = (($EnterpriseNic.ipsubnet).split('.')[0..2] -join '.')
            }
			catch
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error getting Enterprise nic information from $node `n`n $($_.exception)"
				Write-Error "Error getting Enterprise nic information from $node `n`n $($_.exception)" -ErrorAction Continue 
			}


			
			#check that the scope matches the nics on AD node using the first 3 octets

			Write-Host -NoNewline "`tDHCP Scope ID: "
			if ($DHCPScopeID -match $EnterpriseNicShortened)
            {
				Write-Host -ForegroundColor Green "Good"
				$DHCPCheckItems += "ScopeID"
			}
			else{Write-Host -ForegroundColor Red "BAD!!!"}
                
			Write-Host -NoNewline "`tDHCP start range: "	
            if ($DHCPStartRange -match $EnterpriseNicShortened)
            {
				Write-Host -ForegroundColor Green "Good"
				$DHCPCheckItems += "StartRange"
			}
			else{Write-Host -ForegroundColor Red "BAD!!!"}

			Write-Host -NoNewline "`tDHCP end range: "
            if ($DHCPEndRange -match $EnterpriseNicShortened)
            {
				Write-Host -ForegroundColor Green "Good"
				$DHCPCheckItems += "EndRange"
			}
			else{Write-Host -ForegroundColor Red "BAD!!!"}

			Write-Host -NoNewline "`tDHCP subnet mask: "
            if ($DHCPSubnetMask -match $EnterpriseNicSubnetShortened)
            {
				Write-Host -ForegroundColor Green "Good"
				$DHCPCheckItems += "SubnetMask"
			}    
			else{Write-Host -ForegroundColor Red "BAD!!!"}
			
            "---------------------------------"| out-file -append $OutputFile
            "Results of DHCP scope validation" | out-file -append $OutputFile
            "---------------------------------"| out-file -append $OutputFile
            "Properties that Match Enteprise NIC: " + ($DHCPCheckItems -join ", ")  |out-file -append $OutputFile
            "Properties that do not match Enteprise NIC: " + (((compare-object $DHCPItems $DHCPCheckItems).inputobject) -join ", ") | out-file -append $OutputFile
			"" | out-file -append $OutputFile
            
			if ((compare-object $DHCPItems $DHCPCheckItems).inputobject)
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message " DHCP Properties that do not match Enteprise NIC: $((compare-object $DHCPItems $DHCPCheckItems).inputobject)"			
			}
			
			if ($DHCPCheckItems.Count -lt 4)
            {
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "DHCP scope is incorrect. Refer to KB 2911469 for instructions on reconfiguring it."
                write-host -foreground red "`nDHCP scope is incorrect. This does not impact appliance use. Contact CSS for assistance on reconfiguring DHCP.`n"
                "`nDHCP scope is incorrect. Refer to KB 2911469 for instructions on reconfiguring it."| out-file -append $OutputFile
				"" | out-file -append $OutputFile
            }
 	    }
     }
	 
	 Write-Host "`nOutput Located at: $OutputFile"
}

. GetNetworkAdapterConfig