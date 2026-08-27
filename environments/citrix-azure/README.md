# Citrix Azure Environment

Terraform environment for Driftwood Ale Works' Citrix DaaS deployment on Azure,
following the
[Citrix Automation Handbook, Part 5](https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/).

## Architecture

- **Control plane**: Citrix Cloud (DaaS service, managed by Citrix).
- **Session brokering**: Citrix Cloud Gateway service. No NetScaler ADC is
  deployed or required for this environment.
- **Resource location**: an Azure VNet/subnet (see
  [modules/network](../../modules/network/README.md)) where VDAs run.
- **Hosting connection identity**: an Azure AD app registration/service
  principal (see [modules/identity](../../modules/identity/README.md)) that
  Citrix uses to manage Azure resources.
- **Citrix DaaS objects**: resource location, zone, hypervisor, resource
  pool, image versioning, machine catalogs, and delivery group (see
  [modules/citrix](../../modules/citrix/README.md)), created via the
  `citrix/citrix` Terraform provider. Machine identity is `AzureAD`
  (Entra ID-joined) - no traditional AD domain.
- **No Cloud Connectors**: VDAs register with Citrix Cloud directly via
  Rendezvous Protocol instead of routing control/HDX traffic through Cloud
  Connector VMs (which also require traditional AD domain membership,
  incompatible with the Entra-ID-only design above). The Azure hosting
  connection talks to Azure's ARM API directly, so MCS provisioning doesn't
  need Cloud Connectors either. `modules/cloud-connectors` still exists in
  the repo for a future resource location that might need them, but isn't
  wired into this environment. Enabling Rendezvous is a Citrix policy
  setting, not yet wired up in Terraform - see the top-level README's status
  list.
- **Image build artifacts**: a private storage account + blob container (see
  [modules/artifact-storage](../../modules/artifact-storage/README.md)) that
  holds the Citrix VDA installer and Citrix Optimizer zip Packer downloads
  from.
- **Monthly image rotation**: after each Patch Tuesday, a new golden image is
  built, cut into a new machine catalog, phased into the delivery group, and
  the old catalog/image decommissioned - see
  [modules/citrix's rotation section](../../modules/citrix/README.md#monthly-image-catalog-rotation)
  and [.github/workflows/citrix-image-rotation.yml](../../.github/workflows/citrix-image-rotation.yml).

## Layout

- `backend.tf` - remote state configuration
- `bootstrap-tfstate-commands.txt` - one-time Azure CLI commands to create
  the resource group/storage account/container `backend.tf` points at
  (Terraform can't create its own state backend)
- `providers.tf` - provider declarations (`azurerm`, `azuread`, `citrix`)
- `main.tf` - environment-specific root resources and module invocations
- `variables.tf` - environment inputs
- `outputs.tf` - environment outputs
- `terraform.tfvars.example` - template of values to fill in; copy to
  `terraform.tfvars` (gitignored) with real values
- `rotation.auto.tfvars.json` - the git-tracked golden image/machine catalog
  rotation state (`image_versions`) - see
  [modules/citrix's rotation section](../../modules/citrix/README.md#monthly-image-catalog-rotation).
  Edited by `.github/workflows/citrix-image-rotation.yml`, not by hand.
- `bootstrap-github-runner-commands.txt` - one-time manual steps to register
  the self-hosted GitHub Actions runner (see
  [modules/github-runner](../../modules/github-runner/README.md))

## Getting started

1. Run the commands in `bootstrap-tfstate-commands.txt` once (requires
   `az login`) to create the resource group/storage account/container that
   `backend.tf` points at - Terraform can't create its own state backend.
   If you use different names, update `backend.tf` to match.
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in:
   - Azure subscription/tenant IDs (from the Azure side of today's meeting)
   - Citrix Cloud customer ID and API client ID (from the Citrix Cloud side)
3. Export `CITRIX_CLIENT_SECRET` (and Azure credentials, e.g. via `az login`
   or `ARM_*` env vars) in your shell - do not put secrets in tfvars files.
4. `terraform init && terraform plan`.
5. Once applied, run `bootstrap-github-runner-commands.txt`'s steps to bring
   up the self-hosted runner.

See the top-level README's secrets/variables list for what
`.github/workflows/citrix-image-rotation.yml` needs configured in the GitHub
repo before it can run.
