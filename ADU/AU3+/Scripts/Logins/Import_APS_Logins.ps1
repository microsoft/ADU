#* FileName: Import_APS_Logins.ps1
#*=====================================================================
#* Script Name: Import_APS_Logins.ps1
#* Created: [02/15/2018]
#* Author: Simon Facer
#* Company: Microsoft
#* Email: sfacer@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=====================================================================
#* Purpose: Import APS Logins
#*=====================================================================

#*=====================================================================
#* REVISION HISTORY
#*=====================================================================
#* Modified: 03/02/2018
#* Changes:
#* Original Version
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


$HostName = HostName
$DomainName = ($HostName.Split("-"))[0]

[void][System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.AccountManagement")

function Validate-Credentials([System.Management.Automation.PSCredential]$credentials)
{
    $pctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Domain, $DomainName)
    $nc = $credentials.GetNetworkCredential()
    return $pctx.ValidateCredentials($nc.UserName, $nc.Password)
}


#* Assign variables, test for and create if necessary the output folder, test and assign database credentials
try
	{
		# Domain name and CTL host name
		$PDWHOST = GetNodeList -ctl	
		$counter = 1
		$CurrTime = get-date -Format yyyyMMddHHmmss
        $ApplianceName = ($PDWHOST.Split("-"))[0]

	}
catch
	{
		write-eventlog -entrytype Error -Message "Failed to assign variables `n`n $_.exception" -Source $source -LogName ADU -EventId 9999	
		Write-error "Failed to assign variables... Exiting" #Writing an error and exit
	}	


    $HostName = hostname
    $AdminUser = $Hostname -replace "-HST01", "\Administrator"

    $Message = "Import APS Logins"
    $Message += "`r`n`r`nEnter the Password for the domain Administrator account"


    $Cred = Get-Credential -UserName $AdminUser -Message $Message
    if(!$Cred) 
      {
        Write-Host "No Credential Supplied - Exiting Function"  -BackgroundColor Yellow -ForegroundColor DarkRed
        Pause
        Return
      }

    if ((Validate-Credentials $cred) -eq $false)  
      {
        Write-Host "Authentication Failed - Exiting Function"  -BackgroundColor Yellow -ForegroundColor DarkRed
        Pause
        Return
      }






## ===================================================================================================================================================================
Write-Host -ForegroundColor Cyan "`nLoading SQL PowerShell Module..."
LoadSqlPowerShell

Try
  {
	$CTLNode=@()
	$CTLNode = GetNodeList -ctl
  }
catch
  {
	Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Couldn't create nodelist - cluster may not be online `n`n $_"
  }

$InputFiles = Get-ChildItem -Path "D:\PDWDiagnostics\Login"

$tblFiles = $NULL
$tblFiles = New-Object system.Data.DataTable "LoginFiles"
$colIdx = New-Object system.Data.DataColumn Index,([string])
$colFileName = New-Object system.Data.DataColumn FileName,([string])
$colMenuItem = New-Object system.Data.DataColumn MenuItem,([string])
$tblFiles.columns.add($colIdx)
$tblFiles.columns.add($colFileName)
$tblFiles.columns.add($colMenuItem)

[int]$Idx = 0

foreach ($InputFile in $InputFiles)
  {
    $OrigAppliance = ($InputFile.Name).Split("_.")[0]
    $OrigFileDateTime = ($InputFile.Name).Split("_.")[1]
    $OrigFile_yyyy = $OrigFileDateTime.Substring(0,4)
    $OrigFile_mmm = $OrigFileDateTime.Substring(4,2)
    $OrigFile_dd = $OrigFileDateTime.Substring(6,2)
    $OrigFile_hh = $OrigFileDateTime.Substring(8,2)
    $OrigFile_mm = $OrigFileDateTime.Substring(10,2)
    $OrigFile_ss = $OrigFileDateTime.Substring(12,2)
    $OrigFileDateTime = $OrigFile_mmm + "/" + $OrigFile_dd + "/" + $OrigFile_yyyy + " " + $OrigFile_hh + ":" + $OrigFile_mm + ":" + $OrigFile_ss
    $tblFile = $tblFiles.NewRow()
    $Idx += 1
    $tblFile.Index = $Idx
    $tblFile.FileName = $InputFile.Name
    $tblFile.MenuItem = $OrigAppliance + " - " + $OrigFileDateTime
    $tblFiles.Rows.Add($tblFile)
  }

Clear-Host

$FileToLoad = -1
do
  {

    Write-Host "Select Login File to Load, or 'Q' to quit" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Yellow
    Write-Host ""
    foreach ($tblFile in $tblFiles)
      {
        Write-Host $tblFile.Index "  " $tblFile.MenuItem
      }
    Write-Host ""

    $FileNum = ""
    $FileNum = Read-Host "Enter 1..$idx or Q >>"
    if ($FileNum -gt 0 -and $FileNum -le $Idx)
      {
        $FileToLoad = $FileNum        
      }
    elseif ($FileNum -eq "Q")
      {
        $FileToLoad = 0
      }
    else
      {
        Clear-Host
        Write-Host "$FileNum is out of bounds or not numeric" -ForegroundColor DarkYellow
        Write-Host ""
      }

  } while ($FileToLoad -lt 0)


if ($FileToLoad -eq 0)
  {
    Write-Host "Login Import cancelled"-ForegroundColor Cyan
    Pause
    return
  }


foreach ($tblFile in $tblFiles)
  {
    if ($tblFile.Index -eq $FileToLoad)
      {
        $FileToLoad = $tblFile.FileName
      }
  }

$SQLFileName_Drop = ".\AU3+\Config\implogin_Drop.txt"
$SQLFileName_Create1 = ".\AU3+\Config\implogin_Create1.txt"
$SQLFileName_Create2 = ".\AU3+\Config\implogin_Create2.txt"

Invoke-Sqlcmd -InputFile $SQLFileName_Drop -ServerInstance $CTLNode  -Database "TempDB"
Invoke-Sqlcmd -InputFile $SQLFileName_Create1 -ServerInstance $CTLNode  -Database "TempDB"
Invoke-Sqlcmd -InputFile $SQLFileName_Create2 -ServerInstance $CTLNode  -Database "TempDB"


Import-csv "D:\PDWDiagnostics\Login\$FileToLoad" | foreach {
    $SQLCommand = $_.ScriptData
    $CheckSum = $_.CheckSumValue

    ## NOTE - ' chracaters in the SQL Command sting will cause errors in the INSERT statement below, 
    ##        ' characters will be replaced with ~ for the INSERT,
    ##        ~ characters will be reset to ' in the SQL processing
    $SQLCommand = $SQLCommand -replace "'", "~"
    
    $SQLExecute = "INSERT APSLogin (ScriptData, CheckSumValue) VALUES ('$SQLCommand', $CheckSum )"
    ##Write-Host $SQLExecute -ForegroundColor Green
    Invoke-Sqlcmd -Query "$SQLExecute" -ServerInstance $CTLNode  -Database "TempDB" -QueryTimeout 3600
  }

$SQLExecute = "EXEC sp_implogin_APS "
$rset_ImportLogins = Invoke-Sqlcmd -Query $SQLExecute -ServerInstance $CTLNode  -Database "TempDB" -QueryTimeout 3600

if (($rset_ImportLogins.results)[0].StartsWith('>') -eq $true)
  {
    $rset_ImportLogins.Results | foreach {write-Host $_ -ForegroundColor Red}
  }


else
  {
    $rset_ImportLogins.Results | foreach {write-Host $_ -ForegroundColor Green}
  }

Invoke-Sqlcmd -InputFile $SQLFileName_Drop -ServerInstance $CTLNode  -Database "TempDB"

PAUSE
