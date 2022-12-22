function PcliPshell 
{
<#
.DESCRIPTION
    This will add pssnapins/modules of vmware powercli into powershell. You will get
    powercli core, vds and vum scriptlets/snapsins/modules in powershell which will enable you
    to create, run powercli scripts into powershell ISE since powercli itself lacks an IDE.
.LINK
    Script posted over: github.com/MrAmbiG/vmware
#>

Import-Module VMware.VimAutomation.Core     -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.Vds      -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.Cis.Core -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.Storage  -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.vROps    -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.HA       -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.License  -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.Cloud    -ErrorAction SilentlyContinue
Import-Module VMware.VimAutomation.PCloud   -ErrorAction SilentlyContinue
Import-Module VMware.VumAutomation          -ErrorAction SilentlyContinue
}

# TODO Item: Add health check to RunasAdmin Else Fail...

## Requires RunasAdmin
$key = "HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds"
Set-ItemProperty $key ConsolePrompting True

Set-ExecutionPolicy -ExecutionPolicy Bypass
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
install-module PSWindowsUpdate -Confirm:$false

PcliPshell
## End RunasAdmin

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -ParticipateInCeip $false -confirm:$false | Out-Null
Clear-host

$vcenter = $(Write-Host "Enter vCenter name/IP :" -ForegroundColor yellow -NoNewLine; Read-Host)
$vuser = Get-Credential -Message "Enter vCenter Username"
$TemplateCreds = Get-Credential -Message "Local Admin Account for Template"
write-host -foregroundcolor Cyan "Templates"
$Templates = Get-Template -Server $vcenter
$menu = @{}
for ($i=1;$i -le $Templates.count; $i++) 
{ Write-Host "$i. $($Templates[$i-1].name)" 
$menu.Add($i,($Templates[$i-1].name))}

[int]$ans = Read-Host 'Enter selection'
$selection = $menu.Item($ans) ; Get-Template -Server $vcenter -Name  $selection | Set-Template -ToVM -confirm:$false | Out-Null
#$Template = $(Write-Host "Enter Template Name :" -ForegroundColor yellow -NoNewLine; Read-Host)

Connect-viserver -server $vcenter -credential $vuser | Out-Null

Write-Host -ForegroundColor Cyan "Converting template $selection to VM"
#Get-Template -Server $vcenter -Name $template | Set-Template -ToVM -confirm:$false | Out-Null
Write-Host -ForegroundColor Cyan "Powering on $template"
Start-VM -VM $Template | Out-Null

$TempVM = Get-VM -Name $Template
If ($tempVM.ExtensionData.Guest.ToolsRunningStatus -ne 'guestToolsRunning') {
    Write-Host -foregroundcolor cyan "Waiting for $($tempVM.name)" -NoNewline
    do {
        $TempVM = Get-VM -Name $Template
        Write-Host -foregroundcolor cyan "." -NoNewline
        start-Sleep -Seconds 2
        $TempVM = Get-VM -Name $Template
        
    } until ($tempVM.ExtensionData.Guest.ToolsRunningStatus -eq 'guestToolsRunning')
    }
If ($tempVM.ExtensionData.Guest.ToolsRunningStatus -eq 'guestToolsRunning') {
    Write-Host "`n"
    Write-Host -foregroundcolor Green "$($TempVM.Name) is Active... Connecting to IP : $($TempVM.ExtensionData.Guest.IpAddress)"
}

$Task = Invoke-Command -Credential $TemplateCreds -ComputerName ($TempVM.ExtensionData.Guest.IpAddress) `
    -ScriptBlock { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned;`
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
    -PSWUSettings @{SmtpServer="relay.uthet.com";From="Monthly_update_alert@PSScript.local";To="derek.nilson@uthet.com";Port=25} -Verbose

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
Write-Host -ForegroundColor Cyan "Tasks Completed, IsBusy should equal False, and resultant email sent."
$BusyTask
Write-host -foregroundcolor Pink "Cleaning up"
Set-ItemProperty $key ConsolePrompting False
Disconnect-viserver -force -Confirm:$false
