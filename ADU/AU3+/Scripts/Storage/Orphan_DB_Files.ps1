#* FileName: Orphan_DB_Files.ps1
#*=============================================
#* Script Name: Orphan_DB_Files.ps1
#* Created: [11/30/2017]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Requirements:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: Identify orphaned DB files
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Modified: 11/30/2017 sfacer
#* Changes
#* 1. Original version
#*=============================================
#* Modified: 04/12/2018 sfacer
#* Changes
#* 1. Added missing 'Loading SQL PowerShell Module' section
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

    write-error "UserName not entered - script is exiting" -ErrorAction SilentlyContinue
    Write-Host  "UserName not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }
	
if ($PDWPWD -eq $null -or $PDWPWD -eq "")
  {
    write-error "Password not entered - script is exiting" -ErrorAction SilentlyContinue
    Write-Host  "Password not entered - script is exiting" -ForegroundColor Red
    pause
    return
  }

if (!(CheckPdwCredentials -U $PDWUID -P $PDWPWD))
  {

    write-error "UserName / Password authentication failed - script is exiting" -ErrorAction SilentlyContinue
    Write-Host  "UserName / Password authentication failed - script is exiting" -ForegroundColor Red
    pause
    return
  }

## ===================================================================================================================================================================
Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell
Write-Host " "


Try
{
	$CMPList=@()
	$CMPList = GetNodeList -cmp
}
catch
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
}

$CurrTime = get-date -Format yyyyMMddHHmmss
$FileName = "OrphanDBFiles_$CurrTime.csv"
$OutputFile = "D:\PDWDiagnostics\StorageReport\$FileName"

If (!(test-path "D:\PDWDiagnostics\StorageReport"))
  {
	New-item "D:\PDWDiagnostics\StorageReport" -ItemType Dir | Out-Null
  }

$OutputFileLocal = "C:\Temp\$FileName"

## Get the volume list on each CMP node
Write-Host "Capturing file data from CMPxx nodes ..." -ForegroundColor Yellow

$Script  = "`$CMPNode = @{Name=`"NodeName`";expression={`$env:computername}};"
$Script += "`$FileSizeGB = @{Name=`"FileSize`";expression={[math]::round(($`_.Length / 1073741824),4)}};"
$Script += "Get-ChildItem G:\Data*\Data\*.*df -Recurse  | ?{$`_.Name -notlike `"*temp*`"} | SELECT `$CMPNode, Directory, Name, `$FileSizeGB "

$File_results = ExecuteDistributedPowerShell -nodeList $CMPList -command $Script


#########################################################################

Write-Host "Capturing database data ..." -ForegroundColor Yellow
Write-Host "Connecting to PDW..."

try 
	{
		$connection = New-Object System.Data.SqlClient.SqlConnection
		$connection.ConnectionString = "Server=${PDWHOST},17001; Database=master;User ID=${PDWUID};Password=${PDWPWD}";
		$connection.Open();
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to connect `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to connect to APS ... Exiting" #Writing an error and exit
        return
	}


$Query="SELECT dm.physical_name as Mapped_DB
  FROM sys.databases d INNER JOIN sys.pdw_database_mappings dm ON d.database_id = dm.database_id
  WHERE  d.name NOT IN ('master', 'tempdb');"
$DBName_results = Invoke-Sqlcmd -Query $Query -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD

# Define a table for the output
$tblOrphanedFiles = New-Object system.Data.DataTable "OrphanedFiles"
$colNodeName = New-Object system.Data.DataColumn NodeName,([string])
$colFolder = New-Object system.Data.DataColumn Folder,([string])
$colFileName = New-Object system.Data.DataColumn FileName,([string])
$colFileSize = New-Object system.Data.DataColumn FileSize,([single])
$tblOrphanedFiles.Columns.Add($colNodeName)
$tblOrphanedFiles.Columns.Add($colFolder)
$tblOrphanedFiles.Columns.Add($colFileName)
$tblOrphanedFiles.Columns.Add($colFileSize)

$File_results | ForEach {

    $NodeName = $_.NodeName
    $Folder = $_.Directory
    [single]$FileSize = $_.FileSize
    $FileDBName = $_.Name
    $FileDBName_Prefix = $FileDBName.Substring(0,($FileDBName.IndexOfAny("_", 4)))
    If ( -not ($FileDBName_Prefix -in $DBName_results.Mapped_DB) )
      {  
        Write-Host "FileName not found in Mapped DB Names: $FileDBName" -ForegroundColor Red

        $NewRow = $tblOrphanedFiles.NewRow()
        $NewRow.NodeName = $NodeName
        $NewRow.Folder = $Folder
        $NewRow.FileName = $FileDBName
        $NewRow.FileSize = $FileSize
        $tblOrphanedFiles.Rows.Add($NewRow)

      }

  }

If ($tblOrphanedFiles.Rows.Count -eq 0)
  {
    Write-Output "No orphaned files found" > $OutputFile
  }
Else
  {
    $tblOrphanedFiles | SORT-OBJECT NodeName, Folder, FileName | SELECT NodeName, Folder, FileName, FileSize | Export-csv $OutputFile -NoTypeInformation
  }

Write-Host "`nOutput file saved to $OutputFile" -ForegroundColor Green
