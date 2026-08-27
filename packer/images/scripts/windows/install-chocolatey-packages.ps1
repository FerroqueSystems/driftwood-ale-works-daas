$ErrorActionPreference = "Stop"

if ($env:INSTALL_CHOCOLATEY_PACKAGES -ne "true") {
    Write-Host "Chocolatey package installation disabled for this image build. Skipping."
    exit 0
}

if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
    throw "Chocolatey is not installed. Run install-chocolatey.ps1 first."
}

$packageList = $env:CHOCOLATEY_PACKAGES
if ([string]::IsNullOrWhiteSpace($packageList)) {
    Write-Host "No Chocolatey packages defined. Skipping."
    exit 0
}

$packages = $packageList.Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ }

if ($packages.Count -eq 0) {
    Write-Host "No Chocolatey packages defined after parsing. Skipping."
    exit 0
}

Write-Host "Installing Chocolatey packages: $($packages -join ', ')"

& choco feature enable -n allowGlobalConfirmation | Out-Null
& choco install @packages --no-progress -y

if ($LASTEXITCODE -ne 0) {
    throw "Chocolatey package installation failed with exit code $LASTEXITCODE."
}

Write-Host "Chocolatey package installation completed."
