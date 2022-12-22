Write-Host "Running Defrag"
if ($null -ne (Get-Command Optimize-Volume -ErrorAction SilentlyContinue)) {
    Optimize-Volume -DriveLetter C
} else {
    Defrag.exe c: /H
}
