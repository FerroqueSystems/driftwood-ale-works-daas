$ErrorActionPreference = "Stop"

if ($env:INSTALL_CHOCOLATEY_PACKAGES -ne "true") {
    Write-Host "Chocolatey bootstrap disabled for this image build. Skipping."
    exit 0
}

if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
    Write-Host "Chocolatey already installed."
    exit 0
}

Write-Host "Installing Chocolatey."

Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
    throw "Chocolatey installation completed but choco.exe was not found."
}

Write-Host "Chocolatey installed successfully."
