$ErrorActionPreference = "Stop"

if ($env:PREPARE_FOR_CITRIX_MCS -ne "true") {
    Write-Host "Citrix MCS preparation disabled for this image build. Skipping."
    exit 0
}

Write-Host "Preparing Windows image for Citrix MCS capture."

# Demo environment only - firewalling isn't a concern here, and Windows
# Defender Firewall blocking the Cloud Connector's inbound registration
# "test call" (port 80) is what caused VDAs to sit "Unregistered" and get
# torn down by MCS auto-recovery. Disabling only the Domain profile isn't
# enough - a freshly cloned machine can still be classified Public/Private
# during the window before domain trust/NLA resolves, so all three profiles
# need to be off. Baked into the image (not a per-machine runtime tweak) so
# every MCS-cloned VDA comes up this way without manual intervention. Revisit
# with real firewall rules instead of a blanket disable before any
# production use.
Write-Host "Disabling Windows Defender Firewall (all profiles) for this demo image."
Set-NetFirewallProfile -All -Enabled False

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
