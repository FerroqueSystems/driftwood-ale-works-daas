$ErrorActionPreference = "Stop"

if ($env:INSTALL_M365_APPS -ne "true") {
    Write-Host "Microsoft 365 Apps installation disabled for this image build. Skipping."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($env:M365_APPS_ODT_URL)) {
    throw "M365_APPS_ODT_URL must be set when INSTALL_M365_APPS=true."
}

if ([string]::IsNullOrWhiteSpace($env:M365_APPS_CONFIG_XML)) {
    throw "M365_APPS_CONFIG_XML must be set when INSTALL_M365_APPS=true."
}

$installerRoot = "C:\Temp\PackerInstallers"
$odtExtractPath = Join-Path $installerRoot "ODT"
New-Item -ItemType Directory -Path $installerRoot -Force | Out-Null
New-Item -ItemType Directory -Path $odtExtractPath -Force | Out-Null

$odtDownloadPath = Join-Path $installerRoot "odtsetup.exe"
Write-Host "Downloading Office Deployment Tool from $($env:M365_APPS_ODT_URL)"
Invoke-WebRequest -Uri $env:M365_APPS_ODT_URL -OutFile $odtDownloadPath -UseBasicParsing

Write-Host "Extracting Office Deployment Tool"
$extractProcess = Start-Process -FilePath $odtDownloadPath -ArgumentList "/extract:`"$odtExtractPath`" /quiet" -Wait -PassThru
if ($extractProcess.ExitCode -ne 0) {
    throw "Office Deployment Tool extraction failed with exit code $($extractProcess.ExitCode)."
}

$setupPath = Join-Path $odtExtractPath "setup.exe"
if (-not (Test-Path $setupPath)) {
    throw "setup.exe was not found after extracting the Office Deployment Tool to $odtExtractPath."
}

$configPath = Join-Path $installerRoot "m365-apps-configuration.xml"
$configXml = $env:M365_APPS_CONFIG_XML
if ($configXml -match '^(?:https?|ftp)://') {
    Write-Host "Downloading Microsoft 365 configuration from $configXml"
    $configXml = Invoke-WebRequest -Uri $configXml -UseBasicParsing | Select-Object -ExpandProperty Content
}

if ($configXml -notmatch '(?i)SharedComputerLicensing"\s*Value="1"') {
    throw "M365_APPS_CONFIG_XML must set the SharedComputerLicensing property to 1 so activation is shared across multiple users on this golden image."
}

Set-Content -Path $configPath -Value $configXml -Encoding utf8

Write-Host "Installing Microsoft 365 Apps with shared computer activation"
$installProcess = Start-Process -FilePath $setupPath -ArgumentList "/configure `"$configPath`"" -Wait -PassThru
if ($installProcess.ExitCode -ne 0) {
    throw "Microsoft 365 Apps installation failed with exit code $($installProcess.ExitCode)."
}

Write-Host "Microsoft 365 Apps installation completed."
