[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallerUrl,
    [Parameter(Mandatory = $true)][string]$CustomerName,
    [Parameter(Mandatory = $true)][string]$ClientId,
    [Parameter(Mandatory = $true)][string]$ClientSecret,
    [Parameter(Mandatory = $true)][string]$ResourceLocationId
)

# Downloads and silently installs/registers the Citrix Cloud Connector
# software, once this VM is domain-joined (see the JsonADDomainExtension
# step in modules/cloud-connectors/main.tf, which runs before this).
#
# Silent-install mechanism and JSON parameter schema confirmed directly
# against Citrix's own docs (docs.citrix.com, "Install Cloud Connectors from
# the command line"): CWCConnector.exe /q /ParametersFilePath:<json>, with
# customerName/clientId/clientSecret/resourceLocationId/acceptTermsOfService.
# Exit codes: 0 = success, 2 = prerequisite check failed, 1603 = unexpected
# error - see %ProgramData%\Citrix\WorkspaceCloud\InstallLogs for details on
# either failure.

$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\Windows\Temp\install-cloud-connector.log" -Append

$markerPath = "C:\Windows\Temp\cloud-connector-installed.marker"
$installRoot = "C:\Windows\Temp\CloudConnectorInstall"

try {
    if (Test-Path $markerPath) {
        Write-Host "Cloud Connector already installed - skipping (idempotent re-run)."
        exit 0
    }

    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

    $installerPath = Join-Path $installRoot "CWCConnector.exe"
    Write-Host "Downloading Cloud Connector installer..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $installerPath -UseBasicParsing

    $paramsPath = Join-Path $installRoot "cwcconnector_install_params.json"
    $params = @{
        customerName         = $CustomerName
        clientId             = $ClientId
        clientSecret         = $ClientSecret
        resourceLocationId   = $ResourceLocationId
        acceptTermsOfService = "true"
    }
    $params | ConvertTo-Json | Set-Content -Path $paramsPath -Encoding ascii

    try {
        Write-Host "Installing Cloud Connector..."
        $process = Start-Process -FilePath $installerPath -ArgumentList "/q", "/ParametersFilePath:$paramsPath" -Wait -PassThru
        $exitCode = $process.ExitCode
    }
    finally {
        # Contains the Citrix Cloud API client secret in plaintext - remove
        # it immediately regardless of install outcome.
        Remove-Item -Path $paramsPath -Force -ErrorAction SilentlyContinue
    }

    if ($exitCode -ne 0) {
        throw "Cloud Connector installer failed with exit code $exitCode (0=success, 2=prerequisite check failed, 1603=unexpected error - see %ProgramData%\Citrix\WorkspaceCloud\InstallLogs)."
    }

    New-Item -ItemType File -Path $markerPath -Force | Out-Null
    Write-Host "Cloud Connector installation complete."
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Stop-Transcript
}
