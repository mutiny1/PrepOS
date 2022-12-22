# Required for WinRM
Set-NetConnectionProfile -NetworkCategory Private
winrm quickconfig
Set-Item wsman:\localhost\client\TrustedHosts -Value *

# Install PSWindowsUpdate module
# on management station
# AsAdmin
Install-Module PSWindowsUpdate -Force

