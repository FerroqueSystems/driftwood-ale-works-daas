# Citrix Azure Environment

Terraform environment for Driftwood Ale Works' Citrix DaaS deployment on Azure,
following the
[Citrix Automation Handbook, Part 5](https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/).

## Architecture

- **Control plane**: Citrix Cloud (DaaS service, managed by Citrix).
- **Session brokering**: Citrix Cloud Gateway service. No NetScaler ADC is
  deployed or required for this environment.
- **Resource location**: an Azure VNet/subnet (see
  [modules/network](../../modules/network/README.md)) where domain
  controllers, Cloud Connectors, and VDAs run.
- **Hosting connection identity**: an Azure AD app registration/service
  principal (see [modules/identity](../../modules/identity/README.md)) that
  Citrix uses to manage Azure resources - unrelated to the on-prem AD domain
  identity below, this is purely ARM API authentication for the hosting
  connection.
- **Active Directory**: a new, dedicated AD DS forest across two domain
  controllers (see [modules/domain-controllers](../../modules/domain-controllers/README.md)),
  fully scripted end-to-end. Replaced an earlier Entra ID-joined
  (no traditional AD) design after real device-join issues in production
  with no time to chase down before a deadline.
- **Cloud Connectors**: two VMs, domain-joined, brokering communication
  between Citrix Cloud and this AD-domain-joined resource location (see
  [modules/cloud-connectors](../../modules/cloud-connectors/README.md)) -
  required in the zone for AD-domain-joined machine catalogs.
- **Citrix DaaS objects**: resource location, zone, hypervisor, resource
  pool, image versioning, machine catalogs, and three delivery groups - Dev,
  Test/QA, and Prod, each independently promoted off one shared golden image
  (see [modules/citrix](../../modules/citrix/README.md)), created via the
  `citrix/citrix` Terraform provider. Machine identity is `ActiveDirectory`
  (traditional AD domain-joined). Every machine catalog build gets its own
  dedicated resource group for its MCS-provisioned VDA VMs/NICs/disks, so
  different environments/rotation generations never share one.
- **Image build artifacts**: a private storage account + blob container (see
  [modules/artifact-storage](../../modules/artifact-storage/README.md)) that
  holds the Citrix VDA installer and Citrix Optimizer zip Packer downloads
  from.
- **Monthly image rotation**: after each Patch Tuesday, a new golden image is
  built once and then cut into a new machine catalog, phased into the
  delivery group, and the old catalog/image decommissioned - independently
  per environment (dev first, then test, then prod) - see
  [modules/citrix's rotation section](../../modules/citrix/README.md#monthly-image-catalog-rotation)
  and [.github/workflows/citrix-image-rotation.yml](../../.github/workflows/citrix-image-rotation.yml).
- **Temporary demo environment, cost-guarded by default**: every
  Terraform-managed VM (domain controllers, Cloud Connectors, the GitHub
  runner) gets Azure's native auto-shutdown at 7:00 PM Eastern
  (`enable_scheduled_shutdown` - see `terraform.tfvars.example`). For ad-hoc
  control on top of that (stop everything after a working session, start it
  back up before the next one), see
  [`scripts/manage-demo-vms.ps1`](../../scripts/manage-demo-vms.ps1) - it
  discovers VMs across the main resource group and every per-catalog VDA
  resource group, so it covers VDAs too, not just Terraform-managed VMs.

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
  rotation state (`catalog_rotation`), nested per environment
  (dev/test/prod) - see
  [modules/citrix's rotation section](../../modules/citrix/README.md#monthly-image-catalog-rotation-per-environment).
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
   - Active Directory/domain controller/Cloud Connector passwords and a
     dedicated Cloud Connector API client (see the tfvars.example comments)
   - Upload the Cloud Connector installer to artifact-storage and generate a
     SAS URL for `cloud_connector_installer_url` (see
     [modules/cloud-connectors](../../modules/cloud-connectors/README.md))
3. Export `CITRIX_CLIENT_SECRET` (and Azure credentials, e.g. via `az login`
   or `ARM_*` env vars) in your shell - do not put secrets in tfvars files.
4. `terraform init && terraform plan`. The AD forest, Cloud Connector
   domain-join/install, and machine catalogs are all fully scripted (no
   manual runbook) - see
   [modules/domain-controllers](../../modules/domain-controllers/README.md)'s
   README for exactly what that automates and its real, documented risk.
5. Once applied, run `bootstrap-github-runner-commands.txt`'s steps to bring
   up the self-hosted runner - this is a fresh subscription with no
   Bastion/VPN, so that file's first step temporarily opens a source-IP-scoped
   path in (`enable_runner_temporary_ssh_access` / `admin_source_ip_cidr`)
   just for the one-time registration, then closes it again.

See the top-level README's secrets/variables list for what
`.github/workflows/citrix-image-rotation.yml` needs configured in the GitHub
repo before it can run.
