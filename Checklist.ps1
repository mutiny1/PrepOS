# Disable Defender
Set-MpPreference -DisableRealtimeMonitoring $true -Force
New-ItemProperty -Path “HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender” -Name DisableAntiSpyware -Value 1 -PropertyType DWORD -Force
Uninstall-WindowsFeature -Name Windows-Defender
# Disable UAC
New-ItemProperty -Path HKLM:Software\Microsoft\Windows\CurrentVersion\policies\system -Name EnableLUA -PropertyType DWord -Value 0 -Force
# Enable WinRM
Get-Service -Name 'WinRM' | Stop-Service
winrm quickconfig -quiet
winrm quickconfig -q
winrm quickconfig -transport:http
winrm set winrm/config @{MaxTimeoutms="1800000"}
winrm set winrm/config/winrs @{MaxMemoryPerShellMB="2048"}
winrm set winrm/config/service @{AllowUnencrypted="true"}
winrm set winrm/config/service/auth @{Basic="true"}
winrm set winrm/config/client/auth @{Basic="true"}
winrm set winrm/config/listener?Address=*+Transport=HTTP @{Port="5985"}
Get-Service -Name 'WinRM' | Start-Service
