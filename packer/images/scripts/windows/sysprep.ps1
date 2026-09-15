$ErrorActionPreference = "Stop"

$sysprepPath = Join-Path $env:SystemRoot "System32\Sysprep\Sysprep.exe"
if (-not (Test-Path $sysprepPath)) {
    throw "Sysprep not found at $sysprepPath"
}

# Uploaded by the "file" provisioner in azure-windows-base.pkr.hcl, right
# before this script runs. Passing it via /unattend: (rather than only
# dropping it in C:\Windows\Panther\Unattend) is the documented sysprep
# mechanism for persisting OOBE answer-file settings across generalize -
# without it, machines later created from this image (including Citrix
# MCS-provisioned VDAs) hang on OOBE's interactive network/Microsoft-account
# screens instead of booting straight through to a usable login state.
$unattendPath = "C:\Windows\Temp\unattend.xml"
if (-not (Test-Path $unattendPath)) {
    throw "Unattend answer file not found at $unattendPath - required to skip OOBE screens on machines created from this image."
}

Write-Host "Starting sysprep generalization with $unattendPath."
Start-Process -FilePath $sysprepPath -ArgumentList "/oobe /generalize /quiet /quit /unattend:$unattendPath" -Wait

$imageStateKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State"
$desiredState = "IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE"
$deadline = (Get-Date).AddMinutes(45)

while ((Get-Date) -lt $deadline) {
    $imageState = (Get-ItemProperty -Path $imageStateKey -Name ImageState -ErrorAction SilentlyContinue).ImageState

    if ($imageState -eq $desiredState) {
        Write-Host "Sysprep completed with image state $imageState."
        exit 0
    }

    Start-Sleep -Seconds 10
}

$setuperr = "C:\Windows\System32\Sysprep\Panther\setuperr.log"
$setupact = "C:\Windows\System32\Sysprep\Panther\setupact.log"

if (Test-Path $setuperr) {
    Write-Host "Sysprep setuperr.log tail:"
    Get-Content $setuperr -Tail 50 -ErrorAction SilentlyContinue | Write-Host
}

if (Test-Path $setupact) {
    Write-Host "Sysprep setupact.log tail:"
    Get-Content $setupact -Tail 50 -ErrorAction SilentlyContinue | Write-Host
}

throw "Timed out waiting for sysprep to reach $desiredState."
