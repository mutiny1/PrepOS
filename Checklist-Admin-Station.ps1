Set-NetConnectionProfile -NetworkCategory Private
winrm quickconfig
Set-Item wsman:\localhost\client\TrustedHosts -Value *
