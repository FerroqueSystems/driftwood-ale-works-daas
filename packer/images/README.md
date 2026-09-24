# Azure Image Builds

This folder contains the Packer scaffolding used to build Windows base images
and publish them into an Azure Compute Gallery created by Terraform.

By default, the base template creates a clean Windows image, optionally installs
Chocolatey and Chocolatey packages, optionally installs Microsoft 365 Apps with
shared computer activation, optionally installs the Citrix VDA, optionally runs
Citrix Optimizer, prepares the VM for Citrix MCS capture, and then generalizes it.

## Files

- `azure-windows-base.pkr.hcl`: reusable Azure Packer template for Windows builds
- `win11-azure.pkrvars.hcl.example`: example build variables for Windows 11
  (the only image built right now)
- `files/unattend.xml`: Windows Setup answer file uploaded to the build VM
  and passed to sysprep via `/unattend:` - suppresses OOBE's interactive
  network/Microsoft-account/privacy screens on every machine later created
  from the published image (see "OOBE" section below)
- `scripts/windows/install-chocolatey.ps1`: bootstraps Chocolatey on the build VM
- `scripts/windows/install-chocolatey-packages.ps1`: installs requested Chocolatey packages
- `scripts/windows/install-desktopinfo.ps1`: copies DesktopInfo from blob storage and registers it to run at user logon
- `scripts/windows/install-m365-apps.ps1`: downloads the Office Deployment Tool and installs Microsoft 365 Apps with shared computer activation
- `scripts/windows/install-citrix-vda.ps1`: downloads and runs the Citrix VDA installer
- `scripts/windows/install-cloudpaging-player.ps1`: downloads and silently installs Cloudpaging Player for all users
- `scripts/windows/run-citrix-optimizer.ps1`: downloads the Citrix Optimizer zip and runs the selected template
- `scripts/windows/create-local-admin.ps1`: optionally creates/updates a local admin account for break-glass Bastion RDP access
- `scripts/windows/prepare-citrix-master-image.ps1`: performs final cleanup before sysprep
- `scripts/windows/sysprep.ps1`: final generalization step before image capture

## Workflow

1. Create the Azure Compute Gallery and image definitions from
   `infra/foundation/terraform`.
2. Copy one of the `*.example` var files to a real `*.pkrvars.hcl` file.
3. Review the source marketplace image values.
4. Add the Chocolatey packages you want baked into the image.
5. Upload the Citrix VDA installer and Citrix Optimizer zip to the private artifact blob container.
6. Generate read-only SAS URLs for those blobs.
7. Add the Citrix VDA installer URL and silent install arguments when you are ready to build a usable Citrix image.
8. Add the Citrix Optimizer zip URL and template name if you want the image optimized during the build.
9. Leave `prepare_for_citrix_mcs = true` for normal catalog image builds.
10. Run `packer init`.
11. Run `packer build`.

## Installer Model

The image template no longer relies on `winget`. Applications are installed
through Chocolatey, which aligns better with the handbook flow and is more
reliable for Azure image baking than depending on App Installer.

Example Chocolatey packages should be declared in the real `*.pkrvars.hcl`
files, for example:

```hcl
install_chocolatey_packages = true
chocolatey_packages = [
  "googlechrome",
  "vscode",
  # "notepadplusplus"
]
```

To bake in Microsoft 365 Apps for a shared, multi-user host (Citrix multi-session
or RDS), enable it and point at an Office Deployment Tool (ODT) download URL.
Since many users on the same VM will activate the same Office install, the
default `m365_apps_config_xml` sets `SharedComputerLicensing=1` — the script
enforces that this property is present and set to `1` whenever
`install_m365_apps` is enabled:

```hcl
install_m365_apps = true
m365_apps_odt_url = "https://<your-storage-or-artifact-location>/officedeploymenttool.exe"
# Optionally override m365_apps_config_xml to change products, languages, or channel.
```

The ODT download link on the Microsoft site issues a versioned redirect, so
download the current `officedeploymenttool.exe` once and host it from your own
artifact storage (see below) so builds stay reproducible.

Sources:
- Office Deployment Tool: https://learn.microsoft.com/deployoffice/overview-office-deployment-tool
- Shared computer activation: https://learn.microsoft.com/deployoffice/overview-shared-computer-activation

For Citrix images, add the VDA installer explicitly as well. This repo's
environment uses traditional on-prem AD + two Cloud Connectors (see the
top-level README's "Architecture decisions"), so `/controllers` **is**
needed at install time - pass the Cloud Connectors' FQDNs so the installer
populates `ListOfDDCs` in the registry. Without it, VDAs on an
`identity_type = "ActiveDirectory"` catalog have no reliable way to
discover the Cloud Connectors and register (a real bug this repo hit -
see the top-level README's "Status / next steps"):

```hcl
install_citrix_vda        = true
citrix_vda_installer_url  = "https://<your-storage-or-artifact-location>/VDAWorkstationSetup_2402.exe"
citrix_vda_installer_args = "/quiet /noreboot /mastermcsimage /enable_hdx_ports /includeadditional \"Citrix MCS IODriver\" /controllers \"cc-0.yourdomain.local cc-1.yourdomain.local\""
```

And add Citrix Optimizer from blob storage if desired:

```hcl
run_citrix_optimizer          = true
citrix_optimizer_zip_url      = "https://<your-storage-or-artifact-location>/CitrixOptimizerTool.zip"
citrix_optimizer_template_name = "Citrix_Windows_11_2009.xml"
```

The exact VDA installer binary and command line should match your Citrix release
and whether the image is single-session or multi-session.

For a non-persistent VDI image, upload the Cloudpaging Player installer to the
private artifact container and enable it alongside the VDA. Supply the silent
arguments required by the specific Player release; the script accepts exit code
`3010` as success when the installer requests a reboot:

```hcl
install_cloudpaging_player        = true
cloudpaging_player_installer_url  = "https://<your-storage-or-artifact-location>/CloudpagingPlayerSetup.exe"
cloudpaging_player_installer_args = "/quiet /norestart"
```

The Player is installed while Packer is running as the image administrator, so
the installation is present for every provisioned desktop. Use the vendor's
machine-wide installation options when the supplied installer exposes them.

For Citrix image management and prepared-image catalogs, Citrix requires:
- VDA version 2311 or later
- the MCS I/O driver explicitly installed with `/includeadditional "Citrix MCS IODriver"`

Sources:
- https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2411/install-configure/image-management.html
- https://docs.citrix.com/en-us/citrix-virtual-apps-desktops/2507-ltsr/install-configure/install-vdas.html

## Local Admin Account

The AD-domain-joined VDAs this repo provisions (see
[modules/citrix/README.md](../../modules/citrix/README.md)) normally use
domain credentials for RDP over Bastion. If you also want a break-glass
local admin baked into the image for troubleshooting when the domain itself
is unreachable, set both variables - leaving `local_admin_username` empty
skips account creation entirely:

```hcl
local_admin_username = "ferroadmin"
# local_admin_password is sensitive - pass via -var on the command line from
# a secret/environment variable, never commit a real value to *.pkrvars.hcl.
```

In CI, these are passed from the `VDA_LOCAL_ADMIN_USERNAME` /
`VDA_LOCAL_ADMIN_PASSWORD` secrets (see the `build` job in
[.github/workflows/citrix-image-rotation.yml](../../.github/workflows/citrix-image-rotation.yml)),
kept out of the `PACKER_BUILD_VARS_JSON` bundle the same way
`CITRIX_CLIENT_SECRET` is kept out of `TERRAFORM_TFVARS_JSON`.

## OOBE

Windows 11 22H2+ shows several interactive OOBE screens on first boot from a
generalized image - most critically "let's connect you to a network," which
has no visible skip option and hangs indefinitely without one. This is the
"OOBE-hang symptom" referenced elsewhere in this repo's history for VDA
machines provisioned by Citrix MCS from the published golden image.

`files/unattend.xml` fixes this: the `build` block's `file` provisioner
uploads it to `C:/Windows/Temp/unattend.xml` on the build VM, and
`scripts/windows/sysprep.ps1` passes it to `Sysprep.exe` via `/unattend:`,
which is the documented mechanism for persisting an answer file's settings
across generalize. Its `specialize`-pass command sets the `BypassNRO`
registry value that skips the network-required screen, and its
`oobeSystem`-pass settings hide the EULA/OEM-registration/online-account/
wireless-setup screens. It does not handle domain join or computer naming -
Citrix MCS's own machine identity service injects those separately per
machine.

## Boot Diagnostics

`boot_diag_storage_account` (see `win11-azure.pkrvars.hcl.example`) enables
Azure boot diagnostics (console screenshot + serial log) on the build VM
itself - useful for diagnosing a build that boots but never becomes
reachable over WinRM, including an OOBE hang during the build itself (as
opposed to on a machine created later from the published image, which the
`unattend.xml` above targets). Unlike `azurerm_windows_virtual_machine`'s
`boot_diagnostics` block, the `azure-arm` Packer builder has no
Azure-managed-storage option - it requires the name of a storage account
that already exists. In CI this reuses `module.artifact_storage`'s account
(`ARTIFACT_STORAGE_ACCOUNT_NAME`, wired through `write-packer-vars`) rather
than provisioning a dedicated one. Leave empty to disable.

## Artifact Storage

[modules/artifact-storage](../../modules/artifact-storage/README.md), wired
into `environments/citrix-azure` as `module.artifact_storage`, creates a
dedicated private storage account and blob container for image build
artifacts such as:

- `VDAWorkstationSetup_2507.exe`
- `VDAServerSetup_2507.exe`
- `CitrixOptimizerTool.zip`
- custom optimizer XML templates
- `officedeploymenttool.exe`

The recommended pattern is:

1. Keep the storage account private.
2. Upload the artifacts with Azure CLI or AzCopy.
3. Generate read-only SAS URLs for the specific blobs you want Packer to consume.
4. Put those SAS URLs in the real `*.pkrvars.hcl` files.

For Azure Blob storage upload and SAS-style access patterns, see Microsoft Learn:
- Blob upload with AzCopy: https://learn.microsoft.com/azure/storage/common/storage-use-azcopy-blobs-upload
- Anonymous access should remain disabled: https://learn.microsoft.com/azure/storage/blobs/anonymous-read-access-prevent-classic

Chocolatey references:
- Chocolatey setup/install docs: https://docs.chocolatey.org/en-us/choco/setup/
- `choco install` command docs: https://docs.chocolatey.org/en-us/choco/commands/install/

## Example

```bash
cd driftwood-ale-works-daas/packer/images
packer init azure-windows-base.pkr.hcl
packer build -var-file win11-azure.pkrvars.hcl azure-windows-base.pkr.hcl
```
