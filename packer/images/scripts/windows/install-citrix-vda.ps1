$ErrorActionPreference = "Stop"

$resumeMarkerPath = "C:\Temp\PackerInstallers\citrix-vda-resume-required.txt"
$metaInstallRegistryPath = "HKLM:\SOFTWARE\Citrix\MetaInstall"

if ($env:INSTALL_CITRIX_VDA -ne "true") {
    Write-Host "Citrix VDA installation disabled for this image build. Skipping."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($env:CITRIX_VDA_INSTALLER_URL)) {
    throw "CITRIX_VDA_INSTALLER_URL must be set when INSTALL_CITRIX_VDA=true."
}

if ([string]::IsNullOrWhiteSpace($env:CITRIX_VDA_INSTALLER_ARGS)) {
    throw "CITRIX_VDA_INSTALLER_ARGS must be set when INSTALL_CITRIX_VDA=true."
}

$normalizedInstallerArgs = $env:CITRIX_VDA_INSTALLER_ARGS.ToLowerInvariant()
if ($normalizedInstallerArgs -notmatch 'includeadditional.+citrix mcs iodriver') {
    throw "CITRIX_VDA_INSTALLER_ARGS must include /includeadditional ""Citrix MCS IODriver"" for Citrix image management catalog builds."
}

$installerRoot = "C:\Temp\PackerInstallers"
New-Item -ItemType Directory -Path $installerRoot -Force | Out-Null

$installerUrl = $env:CITRIX_VDA_INSTALLER_URL
$installerArgs = $env:CITRIX_VDA_INSTALLER_ARGS
$fileName = [System.IO.Path]::GetFileName(([System.Uri]$installerUrl).AbsolutePath)
if ([string]::IsNullOrWhiteSpace($fileName)) {
    $fileName = "CitrixVDAInstaller.exe"
}

$localPath = Join-Path $installerRoot $fileName

if (-not (Test-Path $localPath)) {
    Write-Host "Downloading Citrix VDA installer from $installerUrl"
    Invoke-WebRequest -Uri $installerUrl -OutFile $localPath -UseBasicParsing
}

$installPhase = $env:CITRIX_VDA_INSTALL_PHASE
if ([string]::IsNullOrWhiteSpace($installPhase)) {
    $installPhase = "initial"
}

function Get-MetaInstallExitCode {
    return (Get-ItemProperty -Path $metaInstallRegistryPath -Name ExitCode -ErrorAction SilentlyContinue).ExitCode
}

Write-Host "Installing Citrix VDA during phase '$installPhase'"
$process = Start-Process -FilePath $localPath -ArgumentList $installerArgs -Wait -PassThru
$exitCode = $process.ExitCode

if ($installPhase -eq "initial") {
    if ($exitCode -eq 0 -or $exitCode -eq 8) {
        Remove-Item -Path $resumeMarkerPath -Force -ErrorAction SilentlyContinue
        Write-Host "Citrix VDA installation completed during initial phase with exit code $exitCode."
        exit 0
    }

    if ($exitCode -eq 3) {
        Set-Content -Path $resumeMarkerPath -Value "resume-required" -Encoding ascii
        Write-Host "Citrix VDA installation requires reboot and resume. Continuing build."
        exit 0
    }

    throw "Citrix VDA installer failed with exit code $exitCode."
}

if ($installPhase -eq "resume") {
    if (-not (Test-Path $resumeMarkerPath)) {
        Write-Host "Citrix VDA resume phase not required. Skipping."
        exit 0
    }

    if ($exitCode -eq 0 -or $exitCode -eq 8) {
        Remove-Item -Path $resumeMarkerPath -Force -ErrorAction SilentlyContinue
        Write-Host "Citrix VDA installation completed during resume phase with exit code $exitCode."
        exit 0
    }

    if ($exitCode -eq 3) {
        $metaExitCode = Get-MetaInstallExitCode
        if ($metaExitCode -eq 8) {
            Remove-Item -Path $resumeMarkerPath -Force -ErrorAction SilentlyContinue
            Write-Host "Citrix VDA resume phase returned 3, but MetaInstall exit code is 8. Treating as success."
            exit 0
        }
    }

    throw "Citrix VDA installer failed during resume phase with exit code $exitCode."
}

throw "Unsupported CITRIX_VDA_INSTALL_PHASE '$installPhase'."
