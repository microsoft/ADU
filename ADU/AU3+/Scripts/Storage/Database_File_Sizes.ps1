#* FileName: DatabaseFiles.ps1
#*=====================================================================
#* Script Name: DatabaseFiles.ps1
#* Created: [11/06/2018]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=====================================================================
#* Purpose: List file aloocated and used space for all files 
#*          in database(s)
#*=====================================================================

#*=====================================================================
#* REVISION HISTORY
#*=====================================================================
#* Modified: 
#* Changes:
#*=====================================================================

param([string]$username,[string]$password,[string]$database)

. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged


#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
	{
		# Domain name and CTL host name
		$PDWHOST = GetNodeList -ctl	
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
		$OutputFileTXT = "D:\PDWDiagnostics\Misc\FileSizeListing_$CurrTime.txt"
		$OutputFileCSV = "D:\PDWDiagnostics\Misc\FileSizeListing_$CurrTime.csv"
		$OutputFileHTML = "D:\PDWDiagnostics\Misc\FileSizeListing_$CurrTime.html"
		if (!(test-path "D:\PDWDiagnostics\Misc"))
			{
				New-item "D:\PDWDiagnostics\Misc" -ItemType Dir | Out-Null
			}
		if (!(test-path $OutputFileTXT))
			{
				New-Item $OutputFileTXT -ItemType File|out-null
			}
		if (!(test-path $OutputFileCSv))
			{
				New-Item $OutputFileCSV -ItemType File|out-null
			}
		if (!(test-path $OutputFileHTML))
			{
				New-Item $OutputFileHTML -ItemType File|out-null
			}

		# Get username and credentials
		
		if(!$username)
			{   $PDWUID = GetPdwUsername; $PDWPWD = GetPdwPassword }
		else
			{   $PDWUID = $username; $PDWPWD = $password }	
	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}	
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


function Get-CTL01MappedDatabaseName ($dbname)
	{	
		$SQLQuery = "SELECT d.name as DBName, dm.physical_name as Mapped_DB
                     FROM sys.databases d INNER JOIN sys.pdw_database_mappings dm ON d.database_id = dm.database_id
                     WHERE d.name = '" + $dbname + "';"

		$rset_MappedDBName = Invoke-Sqlcmd -Query $SQLQuery -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD 
		$MappedDBName=$rset_MappedDBName.Mapped_DB
        
        return $MappedDBName
	}

function Get-CMPxxFiles($CMPNode, $dbname)
	{

		$SQLQuery = "SELECT type, Name, physical_name, size / 128.0 AS Size_MB, CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT)/128.0 as Space_Used_MB 
                     FROM sys.database_files
                     ORDER BY type, file_id;"
		$rset_CMPNodeFiles = $NULL
        $rset_CMPNodeFiles = Invoke-Sqlcmd -Query "$SQLQuery" -ServerInstance "$CMPNode" -Database $dbname

        Return $rset_CMPNodeFiles

	}



## ===================================================================================================================================================================
Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell


## Get the CMPxx node list
Try
{
	$CMPList=@()
	$CMPList = GetNodeList -cmp
}
catch
{
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
}


## Get list of database names
$dbs = Invoke-Sqlcmd -Query "select name from sys.databases where name not in ('master','tempdb','stagedb', 'mavtdb') order by name;" -ServerInstance "$PDWHOST,17001" -Username $PDWUID -Password $PDWPWD

$tblDBFiles = $NULL
$tblDBFiles = New-Object system.Data.DataTable "DBFileList"
$colUserDatabaseName = New-Object system.Data.DataColumn DatabaseName,([string])
$colMappedDatabaseName = New-Object system.Data.DataColumn MappedDatabaseName,([string])
$colCmpNode = New-Object system.Data.DataColumn NodeName,([string])
$colFileType  = New-Object system.Data.DataColumn FileType,([string])
$colLogicalName  = New-Object system.Data.DataColumn LogicalName,([string])
$colPhysicalName  = New-Object system.Data.DataColumn PhysicalName,([string])
$colSizeMB  = New-Object system.Data.DataColumn SizeMB,([decimal])
$colSpaceUsedMB  = New-Object system.Data.DataColumn SpaceUsedMB,([decimal])
$colSpaceUsedPct  = New-Object system.Data.DataColumn SpaceUsedPct,([decimal])
$tblDBFiles.columns.add($colUserDatabaseName)
$tblDBFiles.columns.add($colMappedDatabaseName)
$tblDBFiles.columns.add($colCmpNode)
$tblDBFiles.columns.add($colFileType)
$tblDBFiles.columns.add($colLogicalName)
$tblDBFiles.columns.add($colPhysicalName)
$tblDBFiles.columns.add($colSizeMB)
$tblDBFiles.columns.add($colSpaceUsedMB)
$tblDBFiles.columns.add($colSpaceUsedPct)


#Empty body to hold the html fragments
$HTMLSummary=@()
$HTMLSummary += "<h2>______________________________________________________</h2>"
$HTMLSummary += "<h2>Summary</h2>"
$HTMLbody=@()
$HTMLbody += "<h2>______________________________________________________</h2>"

## For each db, 
##   Get the mapped DB name
##   On each CMP node SQL Instance, get the list of files for the database
do
{
	#create the initial menu array
	$TableMenuOptions=@()
	$TableMenuOptions = (
		#@{"header"="Select a database or all"},
		@{"header"="Run for All Databases"},
		"All DBs",
		@{"header"="Select a single database"}
	)

    # Add the DB names to the array
	for ($i=1;$i -le @($dbs).count; $i++) {$TableMenuOptions+=($($dbs[$i-1].name))}

	[string]$ans = OutputMenu -header "Database File Sizes Listing" -options $TableMenuOptions
	if($ans -eq "q"){break}
		
	if ($ans -eq "All DBs")
	{
		$db=@()
		$db = $dbs.name
	}
	else{$db=$ans}
	
   
	foreach ($database in $db)
		{          
          $UserDBName = $database  
          $MappedDBName = Get-CTL01MappedDatabaseName $database
          Write-Host "Processing: [$UserDBName] (mapped to [$MappedDBName])"  -ForegroundColor Green

          foreach ($node in $CMPList)
	        {
              $CmpNodeFiles = @{}
	          $CmpNodeFiles = Get-CMPxxFiles $node $MappedDBName 
              
              foreach ($CMPNodeFile in $CmpNodeFiles)
                {
                  $NewDBFilesRow = $tblDBFiles.NewRow()
                  $NewDBFilesRow.DatabaseName = $UserDBName
                  $NewDBFilesRow.MappedDatabaseName = $MappedDBName
                  $NewDBFilesRow.NodeName = $node
                  $PhysicalName = $CMPNodeFile.physical_name
                  $LogicalName = $CMPNodeFile.name
                  if ($CMPNodeFile.Type -eq 1) {
                      $NewDBFilesRow.FileType = "Log"
                    }
                  else {
                      if ($PhysicalName -match "primary") {
                          $NewDBFilesRow.FileType = "Primary"
                        }
                      elseif ($LogicalName -match "DIST") {
                          $Distrib = ($LogicalName.split("_"))[1]
                          $NewDBFilesRow.FileType = "Distributed ($Distrib)"
                        }
                      else {
                          $NewDBFilesRow.FileType = "Replicated"
                        }
                    }
                  $NewDBFilesRow.LogicalName = $LogicalName
                  $NewDBFilesRow.PhysicalName = $PhysicalName
                  $NewDBFilesRow.SizeMB = $CMPNodeFile.Size_MB
                  $NewDBFilesRow.SpaceUsedMB =  $CMPNodeFile.Space_Used_MB 
                  [int]$SpaceUsedPct = 10000 * ($CMPNodeFile.Space_Used_MB / $CMPNodeFile.Size_MB)
                  $NewDBFilesRow.SpaceUsedPct = $SpaceUsedPct / 100.00
                  $tblDBFiles.Rows.Add($NewDBFilesRow)
                }

            }



	      #build the body of the HTML

  	      $HTMLbody += "<h2>Database: [$UserDBName], mapped to [$MappedDBName]</h2><br>"
          $HTMLbody += $tblDBFiles | select @{label = "Compute Node" ; Expression = {$_.NodeName}}, @{label = "File Type" ; Expression = {$_.FileType}}, @{label = "File" ; Expression = {$_.PhysicalName}}, @{label = "Size (MB)" ; Expression = {$_.SizeMB}}, @{label = "Used (MB)" ; Expression = {$_.SpaceUsedMB}}, @{label = "Used (Pct)" ; Expression = {$_.SpaceUsedPct}} | ConvertTo-Html -Fragment 
	      $HTMLbody += "<h2>______________________________________________________</h2>"
	      $HTMLbody += "<br>"

	      $tblDBFiles | Export-Csv $OutputFileCSV -NoTypeInformation -Append
  
          $tblDBFiles.Clear()

        }


}while($ans -ne "q")

$Rptdate=Get-Date
$Appliance = (Get-Cluster).name.split("-")[0]


$HTMLOutput=@()
$HTMLOutput += $HTMLbody


#Defining the style
$HTMLhead = @"
	<style>
	BODY{background-color:AliceBlue;}
	TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;}
	TH{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:DarkCyan}
	TD{border-width: 1px;padding: 5px;border-style: solid;border-color: black;background-color:Lavender}
	</style>
"@
ConvertTo-Html -head $HTMLhead -PostContent $HTMLOutput -body "<H1>Database File Report</H1><H2>Appliance: $Appliance<br>Date: $Rptdate</H2>" | out-file $OutputFileHTML


Write-Host -ForegroundColor Cyan "`nOutput also located at: $OutputFileCSV (also .html)"



