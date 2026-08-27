$ErrorActionPreference = "Stop"

if ($env:INSTALL_CLOUDPAGING_PLAYER -ne "true") {
    Write-Host "Cloudpaging Player installation disabled for this image build. Skipping."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($env:CLOUDPAGING_PLAYER_INSTALLER_URL)) {
    throw "CLOUDPAGING_PLAYER_INSTALLER_URL must be set when INSTALL_CLOUDPAGING_PLAYER=true."
}

if ([string]::IsNullOrWhiteSpace($env:CLOUDPAGING_PLAYER_INSTALLER_ARGS)) {
    throw "CLOUDPAGING_PLAYER_INSTALLER_ARGS must be set when INSTALL_CLOUDPAGING_PLAYER=true."
}

$installerRoot = "C:\Temp\PackerInstallers"
New-Item -ItemType Directory -Path $installerRoot -Force | Out-Null

$installerUrl = $env:CLOUDPAGING_PLAYER_INSTALLER_URL
$fileName = [System.IO.Path]::GetFileName(([System.Uri]$installerUrl).AbsolutePath)
if ([string]::IsNullOrWhiteSpace($fileName)) {
    $fileName = "CloudpagingPlayerInstaller.exe"
}

$localPath = Join-Path $installerRoot $fileName
Write-Host "Downloading Cloudpaging Player installer from $installerUrl"
Invoke-WebRequest -Uri $installerUrl -OutFile $localPath -UseBasicParsing

Write-Host "Installing Cloudpaging Player for all users"
$process = Start-Process -FilePath $localPath -ArgumentList $env:CLOUDPAGING_PLAYER_INSTALLER_ARGS -Wait -PassThru
if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
    throw "Cloudpaging Player installer failed with exit code $($process.ExitCode)."
}

Write-Host "Cloudpaging Player installation completed with exit code $($process.ExitCode)."
