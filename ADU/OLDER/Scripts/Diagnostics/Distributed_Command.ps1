#* FileName: RunDistributedCmd.ps1
#*=============================================
#* Script Name: RunDistributedCmd.ps1.ps1
#* Created: [3/10/2014]
#* Author: Nick Salch
#* Company: Microsoft
#* Email: Nicksalc@microsoft.com
#* Reqrmnts:
#*
#* Keywords:
#*=============================================
#* Purpose: This will display a GUI that will 
#* allow you to run a command against multiple
#* nodes
#*=============================================

#*=============================================
#* REVISION HISTORY
#*=============================================
#* Date: [3/25/2014]
#* Time: [5:38 PM]
#* Issue:
#* 	1. Some names are hidden due to creating new columns in the form 
#* 	too high up. 
#* 	2. Toggle buttons need to be added
#* Solution:
#*	1. Make new column start at 100 instaed of 80
#* 	2. Toggle buttons added
#*=============================================
param([string]$command=$null,[switch]$parallel=$false)

#include the functions we need:
. $rootPath\Functions\PdwFunctions.ps1
. $rootPath\Functions\ADU_Utils.ps1

##Set Up logging
$ErrorActionPreference = "stop" #So that we can trap errors
$WarningPreference = "inquire" #we want to pause on warnings
$source = $MyInvocation.MyCommand.Name #Set Source to current scriptname
New-EventLog -Source $source -LogName "ADU" -ErrorAction SilentlyContinue #register the source for the event log
Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Starting $source" #first event logged

function RunDistributedCmd
{
	$nodeList = GetNodeList -full -fqdn

	Write-Host -ForegroundColor Cyan "`nChecking node connectivity"
	$unreachableNodes = CheckNodeConnectivity $nodeList

	if($unreachableNodes)
	{
		Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Warning -message "Removing the following unreachable nodes from the nodelist:`n$unreachableNodes"		
		Write-Host -ForegroundColor Yellow "The following nodes are unreachable, removing them from the node list"
		$unreachableNodes
		
		#remove the unreachable nodes from the list
		$nodelist = $nodelist | ? {$_ -notin $unreachableNodes}
		Write-Host "`n"
	}
	else 
	{
		Write-Host -ForegroundColor Green "All nodes in list reachable`n"
	}


	$userInput = outputForm $nodelist

	if($userInput.command -ne $null)
	{
		$command = $userInput.command 
		$parallel = $userInput.ParallelMode
	}else{return}


	foreach ($unreachableNode in $userInput.UncheckedNodes)
	{
		$nodelist = $nodelist | ? {$_ -notlike "*-$unreachableNode*"}
	}

	#parallel doesn't log as well
	if($parallel -or $input -eq "y")
	{
		try
		{
			Write-Host -ForegroundColor Cyan "Executing `'$command`' in parallel`n"
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType information -message "Executing parallel distributed command: `'$command`' on nodes; $nodelist"		
			ExecuteParallelDistributedPowerShell2 -nodelist $nodeList -command $command
		}
		catch
		{
			Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error Encountered on at least one node in the nodelist.`nCOMMAND: $command`nNODELIST: $nodelist`n$_"		
			Write-Error -ErrorAction Continue "Error Encountered on at least one node in the nodelist.`nCOMMAND: $command`nNODELIST: $nodelist`n$_"		
		}
	}
	else
	{
		Write-Host -ForegroundColor Cyan "Executing `'$command`'`n"
		Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Information -message "Running `'$command`' on the following nodes: $nodelist" 
		Foreach( $node in $nodeList)
		{
			try
			{
				Write-Host -ForegroundColor Cyan "------------------"
				Write-Host -ForegroundColor Cyan $node.split(".")[0]
				Write-Host -ForegroundColor Cyan "------------------"
				
				Invoke-Command -ComputerName $node -ScriptBlock {param([string]$cmd);invoke-expression $cmd} -ArgumentList $command 

			}
			catch
			{
				Write-EventLog -Source $source -logname "ADU" -EventID 9999 -EntryType Error -message "Error encountered running `'$command`' on $node`n$_" 
				Write-Error -ErrorAction Continue "Error encountered on $($node.split(".")[0])`n$_"
			}
		}
	}
}

function outputForm
{
	param([String[]]$nodelist)
	
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

	 #This creates the form and sets its size and position
	 $objForm = New-Object System.Windows.Forms.Form 
	 $objForm.Text = "Run a Distributed Command"
	 $objForm.Size = New-Object System.Drawing.Size(615,415) 
	 $objForm.StartPosition = "CenterScreen"

	 $objForm.KeyPreview = $True
	 $objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") 
	     {$empID=$objTextBox1.Text;$sn=$objTextBox2.Text;$gn=$objTextBox3.Text;$email=$objTextBox4.Text;$title=$objDepartmentListbox.SelectedItem;
	      $office=$objOfficeListbox.SelectedItem;$objForm.Close()}})
	 $objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") 
	     {$objForm.Close()}})

	 #This creates a label for the TextBox1
	 $objLabel1 = New-Object System.Windows.Forms.Label
	 $objLabel1.Location = New-Object System.Drawing.Size(10,10) 
	 $objLabel1.Size = New-Object System.Drawing.Size(380,20) 
	 $objLabel1.Text = "Enter the command to run:"
	 $objForm.Controls.Add($objLabel1) 
	 
	#Create the combo box with previous commands
	$comboOptions=@()
	$comboOptions=Get-Content "$rootPath\Config\Dist_cmd_hist.txt"
	$comboBox1 = New-Object System.Windows.Forms.ComboBox
	$comboBox1.Location = New-Object System.Drawing.Point(10,30)
	$comboBox1.Size = New-Object System.Drawing.Size(580, 20)
	foreach ($option in $comboOptions)
	{
		$comboBox1.Items.add($option)
	}
	$objForm.Controls.Add($comboBox1)
	
	 #create a label above the node list
	 $objLabel1 = New-Object System.Windows.Forms.Label
	 $objLabel1.Location = New-Object System.Drawing.Size(10,60) 
	 $objLabel1.Size = New-Object System.Drawing.Size(500,20) 
	 $objLabel1.Text = "Check all nodes you would like to include (unreachable nodes not included):"
	 $objForm.Controls.Add($objLabel1) 



	$tabindex=1
	$verticalLocation=110
	$horizontalLocation=20

	 foreach ($node in $nodelist)
	 {
	 	#Shorten name
	 	$node = $node.Split("-")[1]
		$node = $node.split(".")[0]
		
	 	Invoke-Expression ('$' + "$node" + 'obj' + "= new-object system.windows.forms.checkbox")
		Invoke-Expression ('$' + "$node" + 'obj' + ".Location = New-Object System.Drawing.Size($horizontalLocation,$verticalLocation)")
		Invoke-Expression ('$' + "$node" + 'obj' + ".Size = New-Object System.Drawing.Size(80,20)")
		Invoke-Expression ('$' + "$node" + 'obj' + ".Text = `"$node`"")
		Invoke-Expression ('$' + "$node" + 'obj' + ".TabIndex = 4")
		Invoke-Expression ('$objForm.Controls.add($' + "$node" + 'obj)')
		Invoke-Expression ('$' + "$node" + 'obj' + ".checked = `$true")

	    $tabindex++
	    $verticalLocation+=20
		
		#if it gets too long start a new column
		if($verticalLocation -gt 290)
		{
			$verticalLocation=110
			$horizontalLocation+=80
		}
	 }
		
	#This creates a label for the toggle buttons
	$objLabel1 = New-Object System.Windows.Forms.Label
	$objLabel1.Location = New-Object System.Drawing.Size(10,85) 
	$objLabel1.Size = New-Object System.Drawing.Size(50,20) 
	$objLabel1.Text = "Toggles:"
	$objForm.Controls.Add($objLabel1) 
	 
	#action for clicking the checkHSA's button
	$ToggleCheckHSAs  = {
		foreach ($node in $nodelist)
	 	{
	 		#Shorten name
	 		$node = $node.Split("-")[1]
			$node = $node.split(".")[0]
		
			if($node -like "HS*")
			{
				#kind of complicated because of the variable-variable names, but will toggle each checkbox
				Invoke-Expression ("if (" + '$' + "$node" + 'obj' + ".checked -eq `$false){" + '$' + "$node" + 'obj' + ".checked = `$true" + "} else {" + '$' + "$node" + 'obj' + ".checked = `$false" + "}")
			}
		}
	}
	
	#action for clicking the checkCmp's button
	$ToggleCheckCMPs  = {
		foreach ($node in $nodelist)
	 	{
	 		#Shorten name
	 		$node = $node.Split("-")[1]
			$node = $node.split(".")[0]
		
			if($node -like "CMP*")
			{
				#kind of complicated because of the variable-variable names, but will toggle each checkbox
				Invoke-Expression ("if (" + '$' + "$node" + 'obj' + ".checked -eq `$false){" + '$' + "$node" + 'obj' + ".checked = `$true" + "} else {" + '$' + "$node" + 'obj' + ".checked = `$false" + "}")
			}
		}
	}
	
	#action for clicking the checkIscsi's button
	$ToggleCheckIscsis  = {
		foreach ($node in $nodelist)
	 	{
	 		#Shorten name
	 		$node = $node.Split("-")[1]
			$node = $node.split(".")[0]
		
			if($node -like "ISCSI*")
			{
				#kind of complicated because of the variable-variable names, but will toggle each checkbox
				Invoke-Expression ("if (" + '$' + "$node" + 'obj' + ".checked -eq `$false){" + '$' + "$node" + 'obj' + ".checked = `$true" + "} else {" + '$' + "$node" + 'obj' + ".checked = `$false" + "}")
			}
		}
	}
	
	#action for clicking the CTL VMs's button
	$ToggleCheckCtlVms  = {
		foreach ($node in $nodelist)
	 	{
	 		#Shorten name
	 		$node = $node.Split("-")[1]
			$node = $node.split(".")[0]
			
			#covers AD/MAD01/CTL01/VMM
			if($node -like "*AD*" -or $node -like "CTL*" -or $node -like "VMM")
			{
				#kind of complicated because of the variable-variable names, but will toggle each checkbox
				Invoke-Expression ("if (" + '$' + "$node" + 'obj' + ".checked -eq `$false){" + '$' + "$node" + 'obj' + ".checked = `$true" + "} else {" + '$' + "$node" + 'obj' + ".checked = `$false" + "}")
			}
		}
	}
	
	#create a checkAll button for HS*'s
	$CheckHsaButton = New-Object System.Windows.Forms.Button
	$CheckHsaButton.Location = New-Object System.Drawing.Size(60,80)
	$CheckHsaButton.Size = New-Object System.Drawing.Size(75,20)
	$CheckHsaButton.Text = "HST/HSA" 
	$CheckHsaButton.add_click($ToggleCheckHSAs)
	$CheckHsaButton.TabIndex = $tabindex++
	$objForm.Controls.Add($CheckHsaButton)
	
	#create a checkAll button for CMPs
	$CheckCmpButton = New-Object System.Windows.Forms.Button
	$CheckCmpButton.Location = New-Object System.Drawing.Size(145,80)
	$CheckCmpButton.Size = New-Object System.Drawing.Size(75,20)
	$CheckCmpButton.Text = "CMP" 
	$CheckCmpButton.add_click($ToggleCheckCMPs)
	$CheckCmpButton.TabIndex = $tabindex++
	$objForm.Controls.Add($CheckCmpButton)
	
	#create a checkAll button for ISCSIs
	$CheckIscsiButton = New-Object System.Windows.Forms.Button
	$CheckIscsiButton.Location = New-Object System.Drawing.Size(230,80)
	$CheckIscsiButton.Size = New-Object System.Drawing.Size(75,20)
	$CheckIscsiButton.Text = "ISCSI" 
	$CheckIscsiButton.add_click($ToggleCheckIscsis)
	$CheckIscsiButton.TabIndex = $tabindex++
	$objForm.Controls.Add($CheckIscsiButton)
	
	#create a checkAll button for CTL Vms
	$CheckCtlVmsButton = New-Object System.Windows.Forms.Button
	$CheckCtlVmsButton.Location = New-Object System.Drawing.Size(315,80)
	$CheckCtlVmsButton.Size = New-Object System.Drawing.Size(75,20)
	$CheckCtlVmsButton.Text = "CTL VMs" 
	$CheckCtlVmsButton.add_click($ToggleCheckCtlVms)
	$CheckCtlVmsButton.TabIndex = $tabindex++
	$objForm.Controls.Add($CheckCtlVmsButton)
	 
	 
	#add a checkbox for 'run in parallel' option
	$RunInParallelCheckbox = New-Object System.Windows.Forms.Checkbox 
	$RunInParallelCheckbox.Location = New-Object System.Drawing.Size(230,310) 
	$RunInParallelCheckbox.Size = New-Object System.Drawing.Size(180,20)
	$RunInParallelCheckbox.Text = "Run in Parallel (less logging)"
	$RunInParallelCheckbox.TabIndex = 4
	$objForm.Controls.Add($RunInParallelCheckbox)
	
	 #This creates the Ok button and sets the event
	 $OKButton = New-Object System.Windows.Forms.Button
	 $OKButton.Location = New-Object System.Drawing.Size(240,340)
	 $OKButton.Size = New-Object System.Drawing.Size(75,23)
	 $OKButton.Text = "Run"
	 $OKButton.dialogResult=[System.Windows.Forms.DialogResult]::OK
	 $objform.AcceptButton = $OKButton 
	 
	 $OKButton.TabIndex = $tabindex++ 
	 $objForm.Controls.Add($OKButton)

	 #This creates the Cancel button and sets the event
	 $CancelButton = New-Object System.Windows.Forms.Button
	 $CancelButton.Location = New-Object System.Drawing.Size(320,340)
	 $CancelButton.Size = New-Object System.Drawing.Size(75,23)
	 $CancelButton.Text = "Cancel"
	 $CancelButton.dialogResult=[System.Windows.Forms.DialogResult]::Cancel
	 $objform.CancelButton=$CancelButton
	 $CancelButton.TabIndex = $tabindex++
	 $objForm.Controls.Add($CancelButton)

	 $objForm.Add_Shown({$objForm.Activate()})

	$uncheckedNodeList=@()
	
	$dialogResult=$objform.ShowDialog()
	
	foreach ($node in $nodelist)
	{
		#Shorten name
	 	$node = $node.Split("-")[1]
		$node = $node.split(".")[0]
		$host01obj.checked
		
		Invoke-Expression ('if($' + "$node" + 'obj' + '.checked -eq $false){' + '$uncheckedNodeList +=' + "`"$node`"" + '}')	
	}
	
	#add this entry to the previously ran commands (max 10 commands)
	#if the value's not already in the array, flip it, add it, flip it back
	if(!($comboOptions -contains $comboBox1.Text))
	{
		[array]::Reverse($comboOptions)
		$comboOptions += $comboBox1.Text
		[array]::Reverse($comboOptions)
	}
	$comboOptions[0..9] > "$rootPath\Config\dist_cmd_hist.txt"
	
	#set up and return the return hashtable
	if($dialogResult -eq [System.Windows.Forms.DialogResult]::OK)
	{
		[hashtable]$returnVar=@{}
		#$returnVar.command=$objTextBox1.Text
		$returnVar.command=$comboBox1.Text
		$returnVar.UncheckedNodes=$uncheckedNodeList
		
		if($RunInParallelCheckbox.checked)
		{
			$returnVar.ParallelMode=$true
		}else{$returnVar.ParallelMode=$false}
		
		return $returnVar
	}
}

. runDistributedCmd