# Golden Image Pipeline (Packer)

Builds the Windows master image used by Citrix machine catalogs, following
[Citrix Automation Handbook, Part 5](https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/):
Packer creates a temporary VM in Azure, installs the Citrix VDA and runs
Citrix Optimizer, generalizes/syspreps it, and publishes the result as a new
image version in the Shared Image Gallery managed by
[modules/image-gallery](../modules/image-gallery/README.md).

## Layout

See [images/README.md](images/README.md) for the full file layout and build
walkthrough. In short:

- `images/azure-windows-base.pkr.hcl` - the `azure-arm` Packer build template
  (variables are declared inline)
- `images/win11-azure.pkrvars.hcl.example` - template of values to copy and
  fill in (Windows 11 is the only image built right now)
- `images/scripts/windows/` - VDA install / Citrix Optimizer / cleanup
  scripts

## Prerequisites

1. The Shared Image Gallery and image definition must already exist (created
   by `module.image_gallery` in `environments/citrix-azure`).
2. The Citrix VDA installer and Citrix Optimizer zip must be staged
   somewhere Packer can download them from - upload them to the private
   container created by [modules/artifact-storage](../modules/artifact-storage/README.md)
   and generate read-only SAS URLs, then set `citrix_vda_installer_url` /
   `citrix_optimizer_zip_url`.
3. An Azure identity (e.g. `az login` or federated OIDC login) with rights to
   build VMs in `build_resource_group_name` and publish into the gallery's
   resource group - the template authenticates via `use_azure_cli_auth`, not
   a service principal secret.

## Running a build

```
cd images
packer init azure-windows-base.pkr.hcl
packer validate -var-file=build.auto.pkrvars.hcl azure-windows-base.pkr.hcl
packer build -var-file=build.auto.pkrvars.hcl azure-windows-base.pkr.hcl
```

Copy the relevant `*.pkrvars.hcl.example` file to `build.auto.pkrvars.hcl`
(gitignored) first and fill in real values - do not commit a real vars file.

Once a new image version is published, point the Citrix machine catalog's
master image at the new version (machine catalogs aren't scaffolded yet -
see the top-level README's status list).
