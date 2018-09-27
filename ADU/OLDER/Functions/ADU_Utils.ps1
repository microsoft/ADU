#* FileName: ADT_Utils.ps1
#*=============================================
#* Script Name: ADT_Utils.ps1
#* Created: [10/24/2013] 
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*
#* Keywords:
#*=============================================
#* Purpose: Standard utilities to use in ADT 
#*	scripts.
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
#* Pause-Host
#* Created: [1/20/2014]
#* Author: Nick Salch
#* Arguments: 
#*	
#*=============================================
#* Purpose:
#*	This function will pause until a key is pressed, 
#*  then return the key. This is useful for timing out 
#*  if no input in a certain period
#*=============================================
#pause and wait for key input, will check twice a second for key input
function Pause-Host
{
    param(
    		$Delay = 5 #delay in seconds
    	 )
    #i'm going to check for input twice a second
    $counter = 0;
    While(!$host.UI.RawUI.KeyAvailable -and ($counter++ -lt $Delay*2))
    {
    	[Threading.Thread]::Sleep(500)
    }

    return $host.ui.RawUI.KeyAvailable
}

#*=============================================
#* OutputMenu
#* Created: [10/22/2013]
#* Author: Nick Salch
#* Arguments: 
#*	$args array of things you want to output in
#*	the menu
#*=============================================
#* Purpose:
#*	This function will display a list based on the 
#*	options passed to it. It will return false if 
#*	if it fails, otherwise returns selection int.
#*  Will return Q if user wants to quit or go back
#*=============================================

function OutputMenu
{
	param([string]$header=$null,$options=$null)
	
	do{
		#check the length of the header and make to bars of the same length
		$i=0
		$headerLine=$null
		While ($i++ -lt $header.length){$headerLine += "-"}
		
		#output the header
		write-host -ForegroundColor Cyan "`n$headerLine`n$header`n$headerLine"

		$visibleCounter=1
		$options | foreach {
			if ($_.header)
			{
				#set the length of the headerline
				$headerLine=$null
				$i=0
				While ($i++ -lt $_.header.length){$headerLine += "-"}
				#output the section header
				Write-host -foregroundcolor cyan "`n$($_.header)`n$headerLine"
			}
			else
			{
				#output the menu option
				Write-Host "$($visibleCounter) $_"
				$visibleCounter++
			}
		}
		Write-Host "`nQ Quit/Back"
		
		$input = Read-Host "`nPlease make your selection"
		
		###check for q and return if it is###
		if($input -eq "q"){return "q"}

		try
		{
			[int]$intInput = $input
		}	
		catch
		{
			#catching if it's not an int
			$intInput = $null
			Write-Host "Couldn't change $input to an int"
		}
		
		#set the length of the array without the hashtables
		$arrayLength = ($options | ? {($_.gettype()).name -ne "hashtable"}).length
		
		#check that the number is between 1 and $options.length
		if($intInput -lt 0 -or $intInput -gt $arrayLength)
		{
			$intInput=$null
		}
	}while(!$intInput)
	
	$optionsNoHash = $options | ?{($_.gettype()).name -ne "hashtable"}
	return $optionsNoHash[$intInput-1]
}

#recursively GCI of the files and subfolders in order	
Function GetFileAttributes
{
	Param($path)

	$files = gci $path | select Name,Basename,Attributes,FullName
	
	foreach ($file in $files)
	{
		if ($file.attributes -ne "Directory")
		{
			write-output $($file.baseName)
		}
		else
		{
			write-output @{Header=$($file.baseName)}
			GetFileAttributes "$($file.FullName)"
		}
	}

}

#*============================================
#* Function: GetDuplicate
#* Created: [9/10/2014]
#* Author: Kristine Lange
#* Source: http://mikepfeiffer.net/2010/04/working-with-duplicate-array-values-in-powershell
#*	
#*=============================================
#* Purpose: Will return the duplicate values
#* in an array
#*=============================================

Function GetDuplicate {
    param($array, [switch]$count)
    begin {
        $hash = @{}
    }
    process {
        $array | %{ $hash[$_] = $hash[$_] + 1 }
        if($count) {
            $hash.GetEnumerator() | ?{$_.value -gt 1} | %{
                New-Object PSObject -Property @{
                    Value = $_.key
                    Count = $_.value
                }
            }
        }
        else {
            $hash.GetEnumerator() | ?{$_.value -gt 1} | %{$_.key}
        }    
    }
}