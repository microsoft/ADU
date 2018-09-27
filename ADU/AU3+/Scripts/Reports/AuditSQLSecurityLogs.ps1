#* FileName: AuditSQLSecurityLogins.ps1
#*=============================================
#* Script Name: AuditSQLSecurityLogins.ps1
#* Created: [8/17/2015]
#* Author: Shane Risk
#* Company: Microsoft
#* Email: shrisk@microsoft.com
#* Reqrmnts:
#*	
#* 
#* Keywords:
#*=============================================
#* Purpose: Audit SQL Server Failed Login Attempts
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#*  
#*=============================================

param($username=$null,$password=$null)

. $rootPath\Functions\PdwFunctions.ps1

#Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
$source
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

function AuditSqlLogs
{

    #Tell the user what we are doing
$Explanation= "    
    
This procedure will scan the logs on CTL01 to look for malicious login patterns.  
Currently the algorithm is looking for more than five failed logins in a five minute 
period.

"
#print explanation
$Explanation

    ####Get  nodelist and set some names
	Try
	{
		$CtlNode = GetNodeList -ctl
	}
	catch
	{
		Write-EventLog -EntryType Error -message "Error encountered Getting a nodelist. Ensure cluster is online `r`n $($_.exception)" -Source $source -logname "ADU" -EventID 9999
		Write-Error "Error encountered Getting a nodelist. Ensure cluster is online `r`n $($_.exception)"
	}
    
    $LoginThresholdCnt = 5
    $LoginThresholdPeriodinMinutes = 5     
    
    $CurrentDtTm = Get-Date

    #get failed sql auth win events here
    $FailedLogins = GetFailedLoginEvents $CurrentDtTm $CtlNode $Source    

    if($FailedLogins -eq ""){ #No data returned, exit    
        "No event data was returned, procedure will exit."

        #create the output Dir
	    mkdir "D:\PdwDiagnostics\Security\" -Force | out-null

        #add explanation to login detail file
        "No event data was returned" |  out-file "D:\PdwDiagnostics\Security\LoginFailedEvents$timestamp.txt"

        #create file for summarized output
        "No event data was returned"  | out-file "D:\PdwDiagnostics\Security\LoginFailedSummary$timestamp.txt"

    }
    else{
        # we have data - lets parse it 
        #Parse the logins and return summary of activity        
        $EventsbyLogin = ParseFailedLogins $FailedLogins         
        $Summary =  CompileLoginSummary $EventsbyLogin $LoginThresholdCnt  $LoginThresholdPeriodinMinutes
        
        #output array of failed attempts over threshold - filter on count, s/b over 5 for output
        $timestamp = get-date -Format MMddyy-hhmmss
        $FormattedOutput = @()
        $i = -1
        $FormattedOutput = "`r`nUsername`t`tFirstLogin`t`t`tLastLogin`t`t`tAttempts"
        $FormattedOutput += "`r`n--------`t`t`----------`t`t`t---------`t`t`t-------"
        $FormattedOutput += foreach($i in $Summary | Where-Object{$_.Attempts -ge $LoginThresholdCnt})  
            {               
               "`r`n{0}`t`t`t{1}`t`t{2}`t`t{3}" -f $i["Logon"].Trim(), $i["First Attempt"].ToString("MM/dd/yyyy hh:mm:ss"), $i["Last Attempt"].ToString("MM/dd/yyyy hh:mm:ss"), $i["Attempts"].ToString()
            }

        #print to screen
        $FormattedOutput

        #create the output Dir
	    mkdir "D:\PdwDiagnostics\Security\" -Force | out-null

        #add explanation to login detail file
        "All failed logins for the last 60 days.`r`n" |  out-file "D:\PdwDiagnostics\Security\LoginFailedEvents$timestamp.txt"

        #add detail
        $FailedLogins | out-file "D:\PdwDiagnostics\Security\LoginFailedEvents$timestamp.txt" -append

        #create file for summarized output
        $Explanation + $FormattedOutput | out-file "D:\PdwDiagnostics\Security\LoginFailedSummary$timestamp.txt"
    }
}

#Function to retrieve failed sql authentication attempts
function GetFailedLoginEvents([datetime] $CurrentDtTm, [String]$CtlNode,[String]$Source)
{

    Try{
        #Security log event 4625 - failed logins with integrated auth
        #Get failed sql server logins - Application Log event 18456 MSSQLServer provider - failed logins with sql auth    
        $FailedSQLLogins = Get-WinEvent -FilterHashtable @{
            LogName="Application"            
            ProviderName = "MSSqlServer"
            StartTime = $CurrentDtTm.AddDays(-60)
            EndTime = $CurrentDtTm         
            ID=18456
        } -ComputerName $CtlNode 
    }
    Catch{
        $FailedSQLLogins = ""
        Write-EventLog -EntryType Error -message "Error retrieving login events. `r`n Exception:  $_.exception" -Source $Source -logname "ADU" -EventID 9999
        Write-Error "Error retrieving login events. `r`n Exception:  $_.exception"
    }
     
    #Get failed integrated auth logins - Security log event 4625 - filter to Unknown username or bad password reason
     
    Try{  
        $FailedWinLogins = ""<# Get-WinEvent -FilterHashtable @{
            LogName="Security"     

            StartTime = $CurrentDtTm.AddDays(-60)
            EndTime = $CurrentDtTm         
	        ID=4625
        } -ComputerName $CtlNode  | Where-Object {$_.message -like "*Unknown user name or bad password.*"}#>
     }
     Catch{
        $FailedWinLogins = ""
        Write-EventLog -EntryType Error -message "Error retrieving login events. `r`n Exception:  $_.exception" -Source $Source -logname "ADU" -EventID 9999
        Write-Error "Error retrieving login events. `r`n Exception:  $_.exception"
    }

    #check both event variables for data and return them together
    if($FailedSQLLogins -eq ""){
        if($FailedWinLogins -eq "") {
            "" #return nothing - no data   
        }
        else {
            #only windows logins
            $FailedWinLogins  
        }
    }
    elseif($FailedWinLogins -eq ""){
        #only sql logins
        $FailedSQLLogins
    }
    else{
        #Both types of logins
        $FailedSQLLogins + $FailedWinLogins        
    }       
}

#Loop through each event and get the user logon and then store each logon attempt by logon
function ParseFailedLogins($FailedLogins)
{   

    #Note, the results are newest first, so moving in reverse chronological order
    $EventsbyLogin = New-Object Collections.Generic.List[HashTable]
    
    #First pass get logins and store events by login in hashtable of arrays
    foreach($event in $FailedLogins)
    {
        #Parse out the user name from the event
        Try{                     
            $LoginFailedUser = ParseLoginName $event   
        }
        Catch{  
            Write-EventLog -EntryType Error -message "Error encountered parsing a windows event. Event message $event.message `r`n Exception:  $_.exception" -Source $source -logname "ADU" -EventID 9999
		    Write-Error "Error encountered parsing a windows event. Event message $event.message `r`n Exception:  $_.exception"
        }
       
        Try{
            #if its the first pass, initialize the hashmap of arrays
            if($EventsbyLogin.Count -eq 0 ){
                #initialize hashmap of event arrays
                $EventsbyLogin=@{$LoginFailedUser=@($event)}
            }        
            elseif($EventsbyLogin.Count -ge 0 -and $EventsbyLogin["$LoginFailedUser"].count -eq 0){
                #First array entry of a new login
                $EventsbyLogin["$LoginFailedUser"] = @($event)

            }
            else{
                #just add the event        
                $EventsbyLogin["$LoginFailedUser"]+=$event
            }              
        }
        Catch{
            Write-EventLog -EntryType Error -message "Error compiling events by login. Event message $event.message `r`n Exception:  $_.exception" -Source $source -logname "ADU" -EventID 9999
		    Write-Error "Error compiling events by login. Event message $event.message `r`n Exception:  $_.exception"
        }
    }       

    #Return the events by login
    $EventsbyLogin
}

#Loop through all the events for a login and compile summary information for that user logon
function CompileLoginSummary($EventsbyLogin, $LoginThresholdCnt, $LoginThresholdPeriodinMinutes)
{
    #Loop through each event and get the user account and count how many failed logins within the specified time period
    #Note, the results are newest first, so moving in reverse chronological order
    $Summary = New-Object System.Collections.ArrayList
        
    #Now take the events by login and check the thresholds
    foreach($SqlLogin in $EventsbyLogin.keys){ #for each username      
        foreach($LoginAttempt in $EventsbyLogin[$SqlLogin]) #for each logon event for a given username
        {
                        

           Try{               
                #If this is a new login, set the $FirstLoginAttempt variable - count of summary array is 0 or the username of the last object in the array is different than the current username
                If($Summary.Count -eq 0){                
                    [void] $Summary.Add(@{"Logon"=$SqlLogin;"Attempts"=1;"First Attempt"=([datetime]$LoginAttempt.TimeCreated);"Last Attempt"=([datetime]$LoginAttempt.TimeCreated)})               
                }
                #if the last $Summary array entry has the same username as the current $SqlLogin AND the current event time created - last attempt value is less than the threshold value then
                elseif($SqlLogin -eq $Summary[$Summary.Count-1]["Logon"] -and (([datetime]$Summary[$Summary.Count-1]["Last Attempt"]) - ([datetime]$LoginAttempt.TimeCreated)).totalminutes -le $LoginThresholdPeriodinMinutes){               
                    #Login record is from the same username and within the threshold - increment count and log new start time (because we're working backwareds from last event to first event)
                    $Summary[$Summary.Count-1]["Attempts"]++                
                    $Summary[$Summary.Count-1]["First Attempt"]=([datetime]$LoginAttempt.TimeCreated)
                }
                else {
                    #if not, then new username or new sequence from same username - create a new array entry                        
                    [void] $Summary.Add(@{"Logon"=$SqlLogin;"Attempts"=1;"First Attempt"=([datetime]$LoginAttempt.TimeCreated);"Last Attempt"=([datetime]$LoginAttempt.TimeCreated)})                              
                }  
            }
            Catch{
                Write-EventLog -EntryType Error -message "Error compiling security audit summary. `r`nLogin:  $SqlLogin `r`nMessage: $event.message `r`n Exception:  $_.exception" -Source $source -logname "ADU" -EventID 9999
		        Write-Error "Error compiling security audit summary. `r`nLogin:  $SqlLogin `r`nMessage: $event.message `r`n Exception:  $_.exception"
            }
        }
    }

    $Summary
}


#Helper function to return the login name for the user.
function ParseLoginName($event)
{
    Try{
        #Use different rules to parse based on the event type
        if($event.ID -eq 18456){
            #Parse out the user name from the event passed in
            $UserNameStartIx = "Login failed for user '".Length #Get start of user name position
            $UserNameEndIx = $event.message.IndexOf("'", $UserNameStartIx) #Get end of user name position
        
            $event.message.Substring($UserNameStartIx,$UserNameEndIx - $UserNameStartIx) # ("'", $UserNameStartIx)    
         }
         elseif($event.ID=4625){
            "login"
            #rules to parse windows auth failure
            $FailedAccountPosition=$event.message.IndexOf("Account For Which Logon Failed:")
            $UserNameStartIx = $event.message.IndexOf("Account Name:",$FailedAccountPosition) + "Account Name:".length #Get start of user name position
            $UserNameEndIx = $event.message.IndexOf("Account Domain:", $UserNameStartIx) #Get end of user name position
            $Username = $event.message.Substring($UserNameStartIx,$UserNameEndIx - $UserNameStartIx).trim()
            $UserDomainEndIx = $event.message.IndexOf("Failure Information:", $UserNameEndIx) #Get end of user domain position
            $UserDomain = $event.message.Substring($UserNameEndIx,$UserDomainEndIx - $UserNameEndIx).trim() 
            $UserDomain + "\" + $Username 

         }
         else {""}     
    }
    catch{
        Write-EventLog -EntryType Error -message "Error parsing event login. `r`nEvent:  $event.ID $event.message `r`nException:  $_.exception" -Source $source -logname "ADU" -EventID 9999
        Write-Error "Error parsing event login. `r`nEvent:  $event.ID $event.message `r`nException:  $_.exception"
    }
}

. AuditSqlLogs