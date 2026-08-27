$ErrorActionPreference = "Stop"

if ($env:PREPARE_FOR_CITRIX_MCS -ne "true") {
    Write-Host "Citrix MCS preparation disabled for this image build. Skipping."
    exit 0
}

Write-Host "Preparing Windows image for Citrix MCS capture."

# Do not clear C:\Windows\Temp during a live Packer session because Packer stores
# its own environment/bootstrap scripts there between provisioners.
$cleanupPaths = @(
    "C:\Temp\PackerInstallers\*",
    "C:\Temp\CitrixOptimizer\*"
)

foreach ($path in $cleanupPaths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Clear-RecycleBin -Force -ErrorAction SilentlyContinue

Write-Host "Citrix MCS preparation completed."
