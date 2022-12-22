function Check-IsElevated
{
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)
    if ($p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
   { Write-Output $true }      
    else
   { Write-Output $false }   
}

if (-not(Check-IsElevated))
{   Write-Host -ForegroundColor Red "Please run this script with elevation."
    Write-host -ForegroundColor Yellow " Requires changes too:"
    write-host "`tSet-ExecutionPolicy -ExecutionPolicy Bypass`n`tSet-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted`n`tinstall-module PSWindowsUpdate -Confirm:$false"
    WRite-host -ForegroundColor Cyan "Exiting script .. 3 seconds"
    Start-sleep -Seconds 3}
Else { 
Write-Host -ForegroundColor Yellow "Elevation granted"

Clear-Host
## Requires RunasAdmin
Write-Host -ForegroundColor Yellow "Setting requirements:"
write-host "`tSet-ExecutionPolicy -ExecutionPolicy Bypass`n`tSet-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted`n`tinstall-module PSWindowsUpdate -Confirm:$false"
Set-ExecutionPolicy -ExecutionPolicy Bypass
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
install-module PSWindowsUpdate -Confirm:$false
## End RunasAdmin

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -ParticipateInCeip $false -confirm:$false | Out-Null

$vcenter = $(Write-Host "Enter vCenter name/IP :" -ForegroundColor yellow -NoNewLine; Read-Host)
$vuser = Get-Credential -Message "Enter vCenter Username"
$TemplateCreds = Get-Credential -Message "Local Admin Account for Template"
Connect-viserver -server $vcenter -credential $vuser | Out-Null

Write-Host -ForegroundColor Cyan "Gathering CL Templates..."
$CI = Connect-CisServer -server $Vcenter -Credential $Credobject -Verbose
$CLTemplates = Get-ContentLibraryItem
$counter = 0
Write-host -foregroundcolor Green "`nChoose CL Template"
Foreach ($CLtemplate in $CLtemplates){
    write-host -foregroundcolor Green "$counter CL" -NoNewLine
    write-host " - " -nonewline 
    Write-host -foregroundcolor Cyan "`t$CLTemplate $($CLTemplate.contentlibrary)"
    $counter += 1
    }
$choice = Read-host -Prompt "Choose template to Patch"
$CLID = $($templates[$choice].ID)
$spec = @{}
$spec.name = "Update$($templates[$choice].Name)"
$spec.placement = @{}
$spec.powered_on = $false
$_this = Get-CisService 'com.vmware.vcenter.vm_template.library_items.check_outs'
$_this.check_out($CLID, $spec)

Write-Host -ForegroundColor Cyan "Gathering Templates..."
$Templates = Get-Template -Server $vcenter
#$counter = 0
Write-host -foregroundcolor Green "`nChoose Template"
Foreach ($template in $templates){
    write-host -foregroundcolor Green $counter -NoNewLine
    write-host " - " -nonewline 
    Write-host -foregroundcolor Cyan $Template
    $counter += 1
    }
$choice = Read-host -Prompt "Choose template to Patch"

Write-Host -ForegroundColor Cyan "Converting template $($templates[$choice].name) to VM"
Get-Template -Server $vcenter -Name $($templates[$choice].name) | Set-Template -ToVM -confirm:$false | Out-Null

Write-Host -ForegroundColor Cyan "Powering on $($templates[$choice].name)"
Start-VM -VM $($templates[$choice].name) | Out-Null

$TempVM = Get-VM -Name $($templates[$choice].name)
If ($tempVM.ExtensionData.Guest.ToolsRunningStatus -ne 'guestToolsRunning') {
    Write-Host -foregroundcolor cyan "Waiting for $($tempVM.name)" -NoNewline
    do {
        $TempVM = Get-VM -Name $($templates[$choice].name)
        Write-Host -foregroundcolor cyan "." -NoNewline
        start-Sleep -Seconds 2
        $TempVM = Get-VM -Name $($templates[$choice].name)
        
    } until ($tempVM.ExtensionData.Guest.ToolsRunningStatus -eq 'guestToolsRunning')
    }
If ($tempVM.ExtensionData.Guest.ToolsRunningStatus -eq 'guestToolsRunning') {
    Write-Host "`n"
    Write-Host -foregroundcolor Green "$($TempVM.Name) is Active... Connecting to IP : $($TempVM.ExtensionData.Guest.IpAddress)"
}

$Task = Invoke-Command -Credential $TemplateCreds -ComputerName ($TempVM.ExtensionData.Guest.IpAddress) -ScriptBlock { `
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned;`
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted;`
    install-module NuGet -Confirm:$false;`
    install-module PSWindowsUpdate -Confirm:$false;`
    Enable-WURemoting
    $WUList = Get-WUList # -Severity 'Important','Critical'
    Return $WUlist
} 
Write-Host -foregroundcolor Red "Install these patches? Ctrl+C to exit, Enter to continue"
$Task
Pause

Install-WindowsUpdate -ComputerName ($TempVM.ExtensionData.Guest.IpAddress) `
    -Severity 'Important','Critical' -MicrosoftUpdate -AcceptAll `
    -IgnoreReboot -SendReport `
    -PSWUSettings @{SmtpServer="relay.uthet.com";From="$template@update_alert@PSScript.local";To="derek.nilson@uthet.com";Port=25} -Verbose

Write-host -foregroundcolor Green "Update task started, wait on email for completion."

$BusyTask = Invoke-Command -Credential $TemplateCreds -ComputerName ($TempVM.ExtensionData.Guest.IpAddress) -ScriptBlock { `
    $Busy = Get-WUInstallerStatus;`
    If ($Busy.IsBusy -eq 'True'){
        do {
            start-Sleep -Seconds 30
            Write-Host "Installing Patches"
        } Until ($Busy.IsBusy -eq 'False')
    }
    Return $Busy
}
Write-Host -ForegroundColor Cyan "Tasks Completed, IsBusy should equal False"
$BusyTask
Disconnect-viserver -force -Confirm:$false
}
