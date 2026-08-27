[CmdletBinding()]
param(
    [string]$SourceUrl = "https://driftwoodctximages.blob.core.windows.net/image-build-artifacts/DesktopInfo/",
    [string]$DestinationPath = "C:\DesktopInfo",
    [string]$TaskName = "DesktopInfo"
)

$ErrorActionPreference = "Stop"

$azCopy = Get-Command azcopy.exe -ErrorAction SilentlyContinue
if (-not $azCopy) {
    throw "AzCopy is not installed or is not available on PATH. Install AzCopy before running this script."
}

New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null

Write-Host "Copying DesktopInfo files to $DestinationPath."
& $azCopy.Source copy $SourceUrl $DestinationPath --recursive=true --overwrite=ifSourceNewer
if ($LASTEXITCODE -ne 0) {
    throw "AzCopy failed with exit code $LASTEXITCODE."
}

$desktopInfoPath = Join-Path $DestinationPath "desktopinfo.exe"
if (-not (Test-Path $desktopInfoPath -PathType Leaf)) {
    throw "desktopinfo.exe was not found at $desktopInfoPath after the copy."
}

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $desktopInfoPath -WorkingDirectory $DestinationPath
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Force | Out-Null

Write-Host "Registered scheduled task '$TaskName' for $currentUser."