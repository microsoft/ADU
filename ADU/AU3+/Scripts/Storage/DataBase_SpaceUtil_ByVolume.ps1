#* FileName: DataBase_SpaceUtil_ByVolume.ps1
#*=============================================
#* Script Name: DataBase_SpaceUtil_ByVolume.ps1
#* Created: [11/22/2017]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Requirements:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: DataBase Space Utilization By Volume
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 11/22/2017 sfacer
#* Changes
#* 1. Original version
#* Modified: 06/16/2021 sfacer
#* Changes
#* 1. Reworked to summarize space allocations by volume / CMP node
#* Modified: 07/28/2021 sfacer
#* Changes
#* 1. Included TempDB and PDWTempDB
#* 2. Added code to load SQL Module
#*=============================================

. $rootPath\Functions\PdwFunctions.ps1

#Set up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

#Get PdwDomainName
$PDWRegion = GetPdwRegionName
$PDWHOST = "$PDWRegion-sqlctl01"

# Get username and credentials		
if(!$username)
	{   $PDWUID = GetPdwUsername; $PDWPWD = GetPdwPassword }
else
	{   $PDWUID = $username; $PDWPWD = $password }	

if ($PDWUID -eq $null -or $PDWUID -eq "")
  {
    Write-Host  "UserName not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }
	
if ($PDWPWD -eq $null -or $PDWPWD -eq "")
  {
    Write-Host  "Password not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }

if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD))
  {
    Write-Host  "UserName / Password authentication failed - script is exiting" -ForegroundColor Red
    pause
    return
  }



Try
{
    $CtlNode = GetNodeList -ctl
	$CMPList = @()
	$CMPList = GetNodeList -cmp
}
catch
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
}

$CurrTime = get-date -Format yyyyMMddHHmmss
$FileName = "DBSpaceUtilByVolume_$CurrTime.csv"
$OutputFile = "D:\PDWDiagnostics\StorageReport\$FileName"

If (!(test-path "D:\PDWDiagnostics\StorageReport"))
  {
	New-item "D:\PDWDiagnostics\StorageReport" -ItemType Dir | Out-Null
  }

## Get the volume list on each CMP node
$Script  = "`$CMPNode = @{Name=`"NodeName`";expression={`$env:computername}};"
$Script += "`$FileSizeGB = @{Name=`"FileSize`";expression={[math]::round(($`_.Length / 1073741824),4)}};"
$Script += "Get-ChildItem G:\Data*\Data\*.*df -Recurse  | SELECT `$CMPNode, Directory, Name, `$FileSizeGB "

$results = ExecuteDistributedPowerShell -nodeList $CMPList -command $Script


#########################################################################

write-output "CONNECTING TO PDW..."

## ===================================================================================================================================================================
Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

try 
	{
		$connection = New-Object System.Data.SqlClient.SqlConnection
		$connection.ConnectionString = "Server=${PDWHOST},17001; ;Database=master;User ID=${PDWUID};Password=${PDWPWD}";
		$connection.Open();
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to connect `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to connect to the APS PDW database... Exiting" #Writing an error and exit
        return
	}


$SQLQuery =  "SELECT d.name as DBName, dm.physical_name as Mapped_DB
FROM sys.databases d INNER JOIN sys.pdw_database_mappings dm ON d.database_id = dm.database_id
WHERE  d.name NOT IN ('master');" 

$rset_DBNames = Invoke-Sqlcmd -query $SQLQuery -ServerInstance "$CTLNode,17001" -UserName ${PDWUID} -Password ${PDWPWD}

$tblFileData = $NULL
$tblFileData = New-Object system.Data.DataTable "FileData"
$ColFileSize = New-Object system.Data.DataColumn FileSize,([double])
$ColKeyField = New-Object system.Data.DataColumn KeyField,([string])
$tblFileData.columns.add($ColFileSize)
$tblFileData.columns.add($ColKeyField)

$tblSummedFileData = $NULL
$tblSummedFileData = New-Object system.Data.DataTable "SummedFileData"
$colDBName = New-Object system.Data.DataColumn UserDBName,([string])
$colSysDBName = New-Object system.Data.DataColumn SysDBName,([string])
$colCMPNode = New-Object system.Data.DataColumn CMPNode,([string])
$colFolder = New-Object system.Data.DataColumn DataFolder,([string])
$ColTotalFileSize = New-Object system.Data.DataColumn TotalFileSize,([double])
$tblSummedFileData.columns.add($colDBName)
$tblSummedFileData.columns.add($colSysDBName)
$tblSummedFileData.columns.add($colCMPNode)
$tblSummedFileData.columns.add($colFolder)
$tblSummedFileData.columns.add($ColTotalFileSize)

foreach ($result in $results) 
  {
    $SysDBName = ($result.Name).Substring(0, ($Result.Name).indexOf("_", 5))
    $UserDBName = ($rset_DBNames | ?{$_.Mapped_DB -eq $SysDBName} | SELECT DBName).DBName
    $NodeName = $result.NodeName
    $Directory = $result.Directory

    $NewFileDataRow = $tblFileData.NewRow()
    $NewFileDataRow.FileSize = $result.FileSize
    $NewFileDataRow.KeyField = "$UserDBName|$SysDBName|$NodeName|$Directory"
    $tblFileData.Rows.Add($NewFileDataRow)
  }

$GroupedFileData = $tblFileData | Group-Object -Property KeyField

foreach ($FileDataGroup in $GroupedFileData) {
    $KeyField = $FileDataGroup.Name
    $FileDataSet = $FileDataGroup.Group
    [double]$FileSizeSum = 0
    foreach ($FileDataSetEntry in $FileDataSet) {
        $FileSizeSum += $FileDataSetEntry.FileSize
      }

    $UserDBName = ($KeyField.Split("|"))[0]
    $SysDBName = ($KeyField.Split("|"))[1]
    if ($SysDBName -eq "tempdb" -or $SysDBName -eq "templog")
      {
        $UserDBName = "TempDB"
      }    
    if ($SysDBName -eq "pdwtempdb1" )
      {
        $UserDBName = "pdwtempdb1"
      }
    $NodeName = ($KeyField.Split("|"))[2]
    $Directory = ($KeyField.Split("|"))[3]

    $NewFileDataRow = $tblSummedFileData.NewRow()
    $NewFileDataRow.UserDBName = $UserDBName
    $NewFileDataRow.SysDBName = $SysDBName
    $NewFileDataRow.CMPNode = $NodeName
    $NewFileDataRow.DataFolder = $Directory
    $NewFileDataRow.TotalFileSize = $FileSizeSum
    $tblSummedFileData.Rows.Add($NewFileDataRow)
  }

$connection.Close()

$tblSummedFileData | SORT UserDBName, CMPNode, DataFolder |  SELECT @{Name="DB Name"; Expression="UserDBName"},@{Name="System DB Name"; Expression="SysDBName"},@{Name="CMP Node"; Expression="CMPNode"},@{Name="Data Folder"; Expression="DataFolder"},@{Name="Allocated Space (GB)"; Expression="TotalFileSize"} | export-csv -NoTypeInformation $OutputFile

Write-Host "`nOutput file saved to $OutputFile" -ForegroundColor Green
