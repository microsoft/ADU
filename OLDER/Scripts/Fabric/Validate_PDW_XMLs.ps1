#* FileName: ValidateAPSXML.ps1
#*=============================================
#* Script Name: ValidateAPSXML.ps1
#* Created: [9/12/2014]
#* Author: Kristine Lange, Nick Salch
#* Company: Microsoft
#* Email: krlange@microsoft.com, nicksalch@microsoft.com
#* Reqrmnts:
#*
#* Keywords: 
#*=============================================
#* Purpose: Check ApplianceInfo and Definition XMLs
#* For duplicate IPs and if IPs are within range
#* Future versions will do more verifications against the XML
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 10/3/2014
#* 1. Include ClusterIpAddress, ClusterIpAddress0 in the duplicate check
#* 2. Checks if IP is within the specified range (only supports /24 right now)
#* 
#*============================================= 
#* Modified: 10/7/2014
#* 1. Added ValidateAPSXML to ADU
#* 2. Move GetDuplicate function to PDWFunctions.ps1 for cleaner code
#*    in preparation for adding code for other validations
#* 3. Validate definition XMLs
#*=============================================
. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Setup logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "Application" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "Application" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

function ValidateApplianceInfoXML
{

    #Check if user wants to specify a different XML path
    write-host "If on the appliance, must be run from HST01 where ConfigureEthernet will be executed. " -ForegroundColor Cyan
	    [string]$xmlpath = read-host "`If running outside of appliance, specify local path (default = C:\PDWINST\Media)"

    if ($xmlpath -eq "")
    {
        $xmlpath = "C:\PDWINST\Media\ApplianceInfo.xml"
    }

    [xml]$AInfo = Get-Content $xmlpath
    [array]$IPs = $null
    [array]$IPAll = $null
    [int[]]$Octet4 = $null
    $X = 0

    $DHCPServerX = $AInfo.ApplianceInfo.Regions.Region.DhcpServer.DhcpServerStartRange
    $DHCPServerStart = ([ipaddress] $DHCPServerX).GetAddressBytes()[3]
    $DHCPServerEnd = ([ipaddress] $AInfo.ApplianceInfo.Regions.Region.DhcpServer.DhcpServerEndRange).GetAddressBytes()[3]
    $Octet1 = ([ipaddress] $DHCPServerX).GetAddressBytes()[0]
    $Octet2 = ([ipaddress] $DHCPServerX).GetAddressBytes()[1]
    $Octet3 = ([ipaddress] $DHCPServerX).GetAddressBytes()[2]

    $IPs += $Ainfo.ApplianceInfo.Regions.Region.Cluster.ClusterIpAddress
    $IPs += $Ainfo.ApplianceInfo.Regions.Region.Cluster.ClusterIpAddress0
    $IPs += $AInfo.ApplianceInfo.Regions.Region.Nodes.Node.Ethernet
    $IPs += $AInfo.ApplianceInfo.Regions.Region.nodes.node.ClusterEthernet | where {$_ -ne $NULL}
    $IPs += $AInfo.ApplianceInfo.Regions.Region.Nodes.Node.BMCAddress | where {$_ -ne $NULL}

    $IPAll += $AInfo.ApplianceInfo.Regions.Region.Nodes.Node.Ethernet
    $IPAll += $AInfo.ApplianceInfo.Regions.Region.nodes.node.ClusterEthernet | where {$_ -ne $NULL}
    $IPAll += $AInfo.ApplianceInfo.Regions.Region.Nodes.Node.BMCAddress | where {$_ -ne $NULL}
    $IPAll += $AInfo.ApplianceInfo.Regions.Region.nodes.node.IB1
    $IPAll += $AInfo.ApplianceInfo.Regions.Region.nodes.node.IB2
    $IPAll += $AInfo.ApplianceInfo.Regions.Region.nodes.node.ClusterIB1 | where {$_ -ne $NULL}
    $IPAll += $AInfo.ApplianceInfo.Regions.Region.nodes.node.ClusterIB2 | where {$_ -ne $NULL}
     
    # Compare ClusterIP and add single record if the same, else add both
    if ($Ainfo.ApplianceInfo.Regions.Region.Cluster.ClusterIpAddress -eq $Ainfo.ApplianceInfo.Regions.Region.Cluster.ClusterIpAddress0)
    {
        $IPAll += $Ainfo.ApplianceInfo.Regions.Region.Cluster.ClusterIpAddress
    }
    else
    {
        $IPAll += $Ainfo.ApplianceInfo.Regions.Region.Cluster.ClusterIpAddress
        $IPAll += $Ainfo.ApplianceInfo.Regions.Region.Cluster.ClusterIpAddress0
    }

    # Retrieve duplicate IPs
    $dups = getDuplicate $IPAll
    if ($dups)
    {
        write-host "Duplicates found: " $dups
    }
    else
    {
        write-host "No duplicates found" -ForegroundColor Green
    }
    
    # Check if IPs are within range
    write-host "Checking if IPs are within DHCP Server start and end range" -ForegroundColor Cyan

    foreach ($IP in $IPs)
    {
        $Octet4 = $IP | % {$_.split(".")[3]} 
        if (($Octet4 -lt $DHCPServerStart) -or ($Octet4 -gt $DHCPServerEnd))
        {
            write-host "$IP outside of range" -ForegroundColor Red
            $X = $X + 1
        }
    }
	
    if ($X -eq 0)
    {
        write-host "All Ethernet IPs are within the specified range of $DHCPServerX - $DHCPServerEnd" -ForegroundColor Green
    }
}
 
function ValidateDefinitionXMLs
{
    #Variable assignment
    [array]$IPsForRangeValidation = $null
    [array]$IPsFromPDWDefn = $null
    [array]$IPsFromHostDefn = $null
    [array]$IPsFromFabricDefn = $null
    
    #Load definition XMLs
    
    [xml]$tempAppliancePDWDefn = Get-Content "c:\PDWINST\Media\AppliancePDWDefinition.xml" -ErrorAction Stop	
    $PDWDomain = GetPdwDomainNameFromXML
    $WorkloadAdmin = Get-Credential -Username "$PDWDomain\administrator" -Message "Enter Workload Admin Password"
    [xml]$appliancePDWDefn = LoadPDWDefinitionXMLFromCTL($WorkloadAdmin)
    [xml]$applianceFabricDefn = LoadFabricDefinitionXMLFromCTL($WorkloadAdmin)
    [xml]$applianceHostDefn = LoadHostDefinitionXMLFromCTL($WorkloadAdmin)
      
    #Retrieve all IPs
    #Start with PDWDefn
    $IPsFromPDWDefn += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.IB1
    $IPsFromPDWDefn += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.IB2
    $IPsFromPDWDefn += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.Ethernet
    $IPsFromPDWDefn += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.ClusterEthernet
    $IPsFromPDWDefn += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.ClusterIB1
    $IPsFromPDWDefn += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.ClusterIB2

    $IPsForRangeValidation += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.Ethernet
    $IPsForRangeValidation += $appliancePDWDefn.AppliancePdw.Region.Nodes.Node.ClusterEthernet

    #PDWHost
    $IPsFromHostDefn += $applianceHostDefn.ApplianceHost.Appliance.Regions.Region.Clusters.Cluster.Nodes.Node.Ethernet
    $IPsFromHostDefn += $applianceHostDefn.ApplianceHost.Appliance.Regions.Region.Clusters.Cluster.Nodes.Node.IB1
    $IPsFromHostDefn += $applianceHostDefn.ApplianceHost.Appliance.Regions.Region.Clusters.Cluster.Nodes.Node.IB2
    $IPsFromHostDefn += $applianceHostDefn.ApplianceHost.Appliance.Regions.Region.Clusters.Cluster.Nodes.Node.BMCAddress

    $IPsForRangeValidation += $applianceHostDefn.ApplianceHost.Appliance.Regions.Region.Clusters.Cluster.Nodes.Node.Ethernet
    $IPsForRangeValidation += $applianceHostDefn.ApplianceHost.Appliance.Regions.Region.Clusters.Cluster.Nodes.Node.BMCAddress

    #PDWFabric
    $IPsFromFabricDefn += $applianceFabricDefn.ApplianceFabric.Region.Nodes.AdNode.Ethernet
    $IPsFromFabricDefn += $applianceFabricDefn.ApplianceFabric.Region.Nodes.AdNode.IB1
    $IPsFromFabricDefn += $applianceFabricDefn.ApplianceFabric.Region.Nodes.AdNode.IB2

    $IPsForRangeValidation += $applianceFabricDefn.ApplianceFabric.Region.Nodes.AdNode.Ethernet

    #Check for dups
    $DupsinPDW = getDuplicate $IPsFromPDWDefn
    $DupsinHost = getDuplicate $IPsFromHostDefn
    $DupsinFabric = getDuplicate $IPsFromFabricDefn

    if ($DupsinPDW)
    {
        write-host "Duplicates found in AppliancePDWDefinition: " $DupsinPDW
    }
    if ($DupsinHost)
    {
        write-host "Duplicates found in ApplianceHostDefinition: " $DupsinHost
    }
    if ($DupsinFabric)
    {
        write-host "Duplicates found in ApplianceFabricDefinition: " $DupsinFabric
    }
    elseif (($DupsinPDW -eq $null) -and ($DupsinHost -eq $null) -and ($DupsinFabric -eq $null))
    {
        write-host "No duplicates found in any of the definition XMLs" -ForegroundColor Green
    }

    # Check if IPs are within range

    $DHCPServerX = $applianceFabricDefn.ApplianceFabric.Region.Fabric.DhcpServerStartRange
    $DHCPServerStart = ([ipaddress] $DHCPServerX).GetAddressBytes()[3]
    $DHCPServerEnd = ([ipaddress] $applianceFabricDefn.ApplianceFabric.Region.Fabric.DhcpServerEndRange).GetAddressBytes()[3]
    $Octet1 = ([ipaddress] $DHCPServerX).GetAddressBytes()[0]
    $Octet2 = ([ipaddress] $DHCPServerX).GetAddressBytes()[1]
    $Octet3 = ([ipaddress] $DHCPServerX).GetAddressBytes()[2]

    write-host "Checking if IPs are within DHCP Server start and end range $DHCPServerX -  $DHCPServerEnd" -ForegroundColor Cyan

    foreach ($IP in $IPsForRangeValidation)
    {
        $Octet4 = $IP | % {$_.split(".")[3]} 
        if (($Octet4 -lt $DHCPServerStart) -or ($Octet4 -gt $DHCPServerEnd))
        {
            write-host "$IP outside of range" -ForegroundColor Red
            $X = $X + 1
        }
    }
	
    if ($X -eq 0)
    {
        write-host "All Ethernet IPs are within the specified range of $DHCPServerX - $DHCPServerEnd" -ForegroundColor Green
    }
}

#Main code
[byte]$ValidateXMLAction = read-host "Type 1 if validating definition XMLs or 2 for ApplianceInfo"
If ($ValidateXMLAction -eq 1)
{
    ValidateDefinitionXMLs
}
Elseif ($ValidateXMLAction -eq 2)
{
    ValidateApplianceInfoXML
}
Else 
{
    write-host "Not a valid choice. Run tool again and choose 1 or 2." -ForegroundColor Red
}

