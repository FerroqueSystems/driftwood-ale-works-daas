# Driftwood Ale Works - Citrix DaaS Infrastructure

Infrastructure-as-code for Driftwood Ale Works' (fictional) Citrix DaaS
deployment on Azure, built following the
[Citrix Automation Handbook, Part 5](https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/).

> This repo is the companion example for **"EUC as a Product: Turning
> Infrastructure Automation into a 'Paved Road' for Delivery Teams"** (World
> of EUC Amplify, Milwaukee). Driftwood Ale Works is a fictional brewing
> company used to illustrate what config drift looks like before GitOps/CI-CD,
> and what a paved road looks like after - real Terraform modules, a gated,
> GitFlow-driven CI/CD pipeline (plan/apply approval gates, automatic
> build/promote/drain on push), and the kinds of provider quirks you
> actually hit running Citrix DaaS on Azure.

## Architecture decisions

- **Session brokering via Citrix Cloud Gateway service** - no NetScaler ADC is
  part of this design.
- **Control plane**: Citrix Cloud (DaaS), managed via the
  [`citrix/citrix`](https://github.com/citrix/terraform-provider-citrix)
  Terraform provider.
- **Resource location**: Azure (VNet/subnet for domain controllers, Cloud
  Connectors, and VDAs), managed via `azurerm`.
- **Hosting connection identity**: an Azure AD app registration/service
  principal, managed via `azuread` - this is ARM API authentication for the
  hosting connection, unrelated to the on-prem AD domain identity below.
- **Traditional Active Directory + Cloud Connectors** - two domain
  controllers run a new AD DS forest, two Cloud Connectors broker
  communication between Citrix Cloud and this on-prem-AD-joined resource
  location, and VDAs join the same domain (`identity_type = "ActiveDirectory"`
  machine catalogs). Fully scripted end-to-end - see
  [modules/domain-controllers](modules/domain-controllers/README.md) for
  exactly what that automates and its real, documented risk. This replaced
  an earlier Entra ID-joined/Rendezvous-only design after real device-join
  issues in production with no time to chase down before a deadline.
- **Golden image pipeline**: Packer builds the Windows VDA master image and
  publishes it to an Azure Shared Image Gallery, which the machine catalog
  references.
- **GitFlow-driven rotation**: Dev is always manual - build a new image and
  cut Dev over to it by hand (`workflow_dispatch`), as many times as needed
  before merging anywhere; merging into `develop` promotes whatever's live
  in Dev to Test automatically; merging into `main` promotes it to Prod and
  drains the outgoing catalog (maintenance mode -> bounded wait -> power
  off, not deleted). Manual `workflow_dispatch` actions also remain for
  other out-of-band operations and for actually decommissioning a drained
  catalog. See [modules/citrix's rotation section](modules/citrix/README.md#image-catalog-rotation-per-environment)
  for the full model.

## Layout

- [`environments/citrix-azure`](environments/citrix-azure/README.md) - the
  root Terraform environment (providers, variables, module wiring)
- [`modules/network`](modules/network/README.md) - VNet/subnet for the
  resource location
- [`modules/identity`](modules/identity/README.md) - Azure AD hosting
  connection app registration
- [`modules/domain-controllers`](modules/domain-controllers/README.md) - two
  domain controllers, fully scripted forest creation
- [`modules/cloud-connectors`](modules/cloud-connectors/README.md) - two
  Cloud Connector VMs, domain-joined and registered against Citrix Cloud,
  fully scripted
- [`modules/citrix`](modules/citrix/README.md) - Citrix Cloud resource
  location, zone, hypervisor, resource pool, image versioning, machine
  catalogs, and three delivery groups (Dev/Test/Prod). Each machine catalog
  build gets its own dedicated Azure resource group so different
  environments/rotation generations' VDA VMs/NICs/disks never share one.
- [`modules/image-gallery`](modules/image-gallery/README.md) - Azure Shared
  Image Gallery + image definition for VDA master images
- [`modules/artifact-storage`](modules/artifact-storage/README.md) - private
  storage account + blob container for Packer image build artifacts (VDA
  installer, Citrix Optimizer zip, Cloud Connector installer)
- [`modules/github-runner`](modules/github-runner/README.md) - self-hosted
  GitHub Actions runner VM (network access to the private VDA subnet)
- [`packer`](packer/README.md) - Packer template that builds the VDA master
  image and publishes it into the image gallery
- [`scripts/rotate_image_versions.py`](scripts/rotate_image_versions.py) -
  edits the golden image/machine catalog rotation state
- [`scripts/manage-demo-vms.ps1`](scripts/manage-demo-vms.ps1) - ad-hoc
  start/stop/status for every VM in this temporary demo environment
  (domain controllers, Cloud Connectors, the runner, and any Citrix
  MCS-provisioned VDAs) - on top of the auto-shutdown schedule every
  Terraform-managed VM already has (see
  [environments/citrix-azure](environments/citrix-azure/README.md))
- `.github/workflows/terraform.yml` - `terraform fmt`/`validate` on PRs
- `.github/workflows/packer.yml` - `packer fmt`/`validate` on PRs
- `.github/workflows/citrix-image-rotation.yml` - the GitFlow-driven
  build/promote/drain pipeline (push-triggered) plus manual
  build/cutover/decommission/apply actions (`workflow_dispatch`)

## Status / next steps

Scaffolding is in place for the full pipeline described in the
[Citrix Automation Handbook, Part 5](https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/):
network, identity, a new AD DS forest, Cloud Connectors, image gallery,
artifact storage, Citrix DaaS objects (including machine catalogs and three
delivery groups - Dev/Test/Prod), a self-hosted runner, and the GitFlow-driven
rotation workflow. Before any of it can actually run against real
infrastructure, it needs:

- [ ] Azure subscription ID + tenant ID for the **Lab** subscription this
      demo deploys into (Azure application piece)
- [ ] Citrix Cloud customer ID + API client ID/secret (Citrix Cloud auth),
      plus a **second**, dedicated API client for Cloud Connector
      registration (see `modules/cloud-connectors/README.md`) and a
      **third** for the Prod drain/maintenance-mode script (see
      `scripts/citrix_daas_maintenance.py` and the secrets table below)
- [ ] Remote state backend details (`environments/citrix-azure/backend.tf`)
- [ ] Naming/addressing decisions in `terraform.tfvars` (copy from
      `terraform.tfvars.example`) - AD domain/service-account/safe-mode
      passwords, domain controller and Cloud Connector local admin
      passwords, and the Cloud Connector installer's SAS URL
- [ ] VDA installer + Citrix Optimizer download locations, and the
      version-matched scripts from `citrix-packer-tools` (see
      `packer/scripts/README.md`)
- [ ] `environments/citrix-azure/rotation.auto.tfvars.json` is seeded with
      demo machine counts (Dev 3, Test 5, Prod 20) - adjust if the real
      numbers for the talk differ
- [ ] The GitHub repo secrets/variables listed below
- [ ] Run `bootstrap-github-runner-commands.txt`'s one-time registration
      steps - this repo has no Bastion/VPN (nothing pre-exists in the Lab
      subscription), so that file's step 0 temporarily opens a source-IP-scoped
      public path in via `enable_runner_temporary_ssh_access` /
      `admin_source_ip_cidr`, then closes it again once the runner is registered
- [ ] **A dry run of the AD forest/Cloud Connector automation against the
      Lab subscription, well before the conference** - see
      `modules/domain-controllers/README.md`'s "Automation, and its real
      risk" section. This is scripted end-to-end with no manual fallback and
      hasn't been exercised against real Azure/Citrix Cloud from this repo.
- [ ] **Verify `scripts/citrix_daas_maintenance.py`'s Citrix DaaS REST API
      calls against a real tenant** (or at least a non-prod catalog) before
      the conference - the maintenance-mode/list-machines/power-action
      endpoints could not be confirmed against live API reference docs when
      this script was written; see the module docstring for exactly which
      calls are lower-confidence.

Remote PC / app publishing beyond desktops aren't in scope yet.

## GitHub repo secrets/variables

Configure these under repo Settings before running `citrix-image-rotation.yml`
manually (`build`/`cutover`/`decommission`/`apply`, on any branch), or before
pushing to `develop`/`main` (which trigger promotion automatically).
`terraform.yml` and `packer.yml`'s existing `fmt`/`validate`-only jobs need
none of these.

Every real config value is its own named GitHub secret or variable -
`.github/actions/write-citrix-tfvars` and `.github/actions/write-packer-vars`
(two local composite actions) assemble them into the gitignored
`ci.auto.tfvars.json`/`ci.auto.pkrvars.json` files each job needs at
runtime. Almost everything below is **repo-level** (Settings > Secrets and
variables > Actions), since one Lab subscription/Citrix Cloud tenant backs
every environment - only the Prod drain credentials are scoped to a single
GitHub Environment (see the last table).

**Repo-level variables** (Settings > Secrets and variables > Actions >
Variables tab - not sensitive, but still only relevant to CI):

| Variable | Purpose |
|---|---|
| `LOCATION` | Azure region for all resources |
| `RESOURCE_GROUP_NAME` | Resource group for the whole environment |
| `TAGS_JSON` | JSON map of tags applied to Azure resources |
| `ENABLE_SCHEDULED_SHUTDOWN` / `SCHEDULED_SHUTDOWN_TIME` / `SCHEDULED_SHUTDOWN_TIMEZONE` | Native Azure auto-shutdown schedule applied to every Terraform-managed VM (see "Status / next steps" above) |
| `ENABLE_BOOT_DIAGNOSTICS` | Console screenshot + serial log on every Terraform-managed VM - on by default while the environment's being stood up/validated, doesn't cover Citrix MCS-provisioned VDAs |
| `VNET_NAME` / `VNET_ADDRESS_SPACE_JSON` / `VDA_SUBNET_ADDRESS_PREFIXES_JSON` | Networking (JSON-encoded lists for the address-space/prefix values) |
| `HOSTING_CONNECTION_APP_NAME` | Display name for the Azure AD app registration behind Citrix's hosting connection |
| `CITRIX_ENVIRONMENT` / `CITRIX_RESOURCE_LOCATION_NAME` / `CITRIX_ZONE_DESCRIPTION` / `CITRIX_HYPERVISOR_NAME` / `CITRIX_RESOURCE_POOL_NAME` | Citrix Cloud environment + DaaS object naming |
| `CITRIX_ADMIN_FOLDER_NAME` | Citrix Studio/Web Studio admin folder this environment's machine catalogs and delivery groups are placed in, alongside other environments/customers' own folders |
| `CITRIX_ALLOCATION_TYPE` / `CITRIX_VDA_SERVICE_OFFERING` / `CITRIX_VDA_STORAGE_TYPE` | MCS provisioning settings for VDA machines |
| `DELIVERY_GROUP_DEV_CONFIG_JSON` / `DELIVERY_GROUP_TEST_CONFIG_JSON` / `DELIVERY_GROUP_PROD_CONFIG_JSON` | One environment's slice of `delivery_groups` each (name, published desktop, access allow-list, autoscale `power_time_schemes`, catalog-naming conventions), as a JSON object matching `terraform.tfvars.example`'s `delivery_groups.dev`/`.test`/`.prod` shape. **All three are read on every job regardless of which single environment it's cutting over** - `write-citrix-tfvars` always reassembles the complete `{dev, test, prod}` map, because Terraform's `for_each` over `delivery_groups` would destroy whichever environments are missing from a partial map |
| `ACTIVE_DIRECTORY_DOMAIN_FQDN` / `ACTIVE_DIRECTORY_DOMAIN_NETBIOS_NAME` | New AD DS forest/domain identity |
| `ACTIVE_DIRECTORY_SERVICE_ACCOUNT_NAME` / `ACTIVE_DIRECTORY_BASE_OU_NAME` / `ACTIVE_DIRECTORY_VDA_OU_NAME` / `ACTIVE_DIRECTORY_CONNECTOR_OU_NAME` | AD object naming (service account, OU structure) |
| `ACTIVE_DIRECTORY_DEV_DESKTOP_GROUP_NAME` / `ACTIVE_DIRECTORY_TEST_DESKTOP_GROUP_NAME` / `ACTIVE_DIRECTORY_PROD_DESKTOP_GROUP_NAME` | AD security groups referenced by each delivery group's access allow-list |
| `DOMAIN_CONTROLLER_ADMIN_USERNAME` / `DOMAIN_CONTROLLER_SCRIPTS_STORAGE_ACCOUNT_NAME` | Domain controller VM admin username + their bootstrap-script storage account name |
| `CLOUD_CONNECTOR_ADMIN_USERNAME` / `CLOUD_CONNECTOR_SCRIPTS_STORAGE_ACCOUNT_NAME` | Cloud Connector VM admin username + their bootstrap-script storage account name |
| `RUNNER_NAME` / `RUNNER_VM_SIZE` / `RUNNER_ADMIN_USERNAME` | Self-hosted runner VM identity/sizing (not `GITHUB_*` - GitHub reserves that prefix for its own automatic secrets/variables and rejects any repo secret/variable name starting with it) |
| `ENABLE_RUNNER_TEMPORARY_SSH_ACCESS` | Whether the one-time public-IP+NSG SSH path for runner registration is open (leave `false` outside that registration step) |
| `GALLERY_NAME` / `IMAGE_DEFINITION_NAME` / `IMAGE_SKU` | Shared Image Gallery / VDA image definition naming |
| `ARTIFACT_STORAGE_ACCOUNT_NAME` / `ARTIFACT_STORAGE_CONTAINER_NAME` | Storage account/container holding Packer build artifacts (VDA installer, Citrix Optimizer zip) |
| `DEV_TOTAL_MACHINES` / `TEST_TOTAL_MACHINES` / `PROD_TOTAL_MACHINES` | Machine-catalog size for the automatic push-triggered jobs (default 3/5/20 if unset) |
| `OUTSTANDING_IMAGE_LABEL_THRESHOLD` | Outstanding-image-count that triggers a (non-blocking) warning (default 5 if unset) |
| `AZURE_IMGPUBLISHER` / `AZURE_IMGOFFER` / `AZURE_IMGSKU` / `AZURE_IMGVERSION` | Base Azure Marketplace image Packer builds from |
| `INSTALL_CHOCOLATEY_PACKAGES` / `CHOCOLATEY_PACKAGES_JSON` | Optional Chocolatey package install during the image build |
| `INSTALL_M365_APPS` / `M365_APPS_ODT_URL` | Optional Microsoft 365 Apps install |
| `INSTALL_CITRIX_VDA` / `CITRIX_VDA_INSTALLER_ARGS` | VDA install toggle + silent-install args (the installer URL itself is a secret, below) |
| `INSTALL_CLOUDPAGING_PLAYER` / `CLOUDPAGING_PLAYER_INSTALLER_ARGS` | Optional Cloudpaging Player install toggle + silent-install args |
| `RUN_CITRIX_OPTIMIZER` / `CITRIX_OPTIMIZER_TEMPLATE_NAME` | Optional Citrix Optimizer pass + template name |
| `PREPARE_FOR_CITRIX_MCS` | Whether Packer runs MCS image-prep steps (sysprep, etc.) |
| `MANAGED_IMAGE_TAGS_JSON` | JSON map of tags applied to the published gallery image version |

**Repo-level secrets** (Settings > Secrets and variables > Actions >
Secrets tab):

| Secret | Purpose |
|---|---|
| `ARM_CLIENT_ID` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID` | OIDC federated login (`azure/login`) for the `azurerm`/`azuread` providers and the Terraform state backend; also fed straight through as the `azure_subscription_id`/`azure_tenant_id` Terraform variables. For this demo these must point at the **Lab** Azure subscription/tenant, not production - the whole environment (including the self-hosted runner VM) is provisioned there |
| `CITRIX_CUSTOMER_ID` / `CITRIX_CLIENT_ID` / `CITRIX_CLIENT_SECRET` | Citrix Cloud API credentials for the Terraform provider itself (`providers.tf` reads `CITRIX_CLIENT_SECRET` directly as an env var) |
| `ACTIVE_DIRECTORY_SAFE_MODE_PASSWORD` / `ACTIVE_DIRECTORY_SERVICE_ACCOUNT_PASSWORD` | DSRM safe-mode password + the MCS/Cloud-Connector-domain-join service account's password |
| `DOMAIN_CONTROLLER_ADMIN_PASSWORD` | Local admin password for the domain controller VMs |
| `CLOUD_CONNECTOR_ADMIN_PASSWORD` | Local admin password for the Cloud Connector VMs |
| `CLOUD_CONNECTOR_CLIENT_ID` / `CLOUD_CONNECTOR_CLIENT_SECRET` | A **second**, dedicated Citrix Cloud API client for Cloud Connector registration - deliberately separate from `CITRIX_CLIENT_ID`/`_SECRET` |
| `CLOUD_CONNECTOR_INSTALLER_URL` | Read-only SAS URL to the Cloud Connector installer (`CWCConnector.exe`) in artifact storage |
| `RUNNER_ADMIN_SSH_PUBLIC_KEY` | SSH public key for the self-hosted runner VM's admin user (not secret in principle, kept as a Secret to avoid it sitting in a Variable for no benefit; not `GITHUB_*` for the same reserved-prefix reason as above) |
| `ADMIN_SOURCE_IP_CIDR` | CIDR allowed to SSH into the runner VM while `ENABLE_RUNNER_TEMPORARY_SSH_ACCESS` is true (only needed during registration) |
| `VDA_LOCAL_ADMIN_USERNAME` / `VDA_LOCAL_ADMIN_PASSWORD` | Local admin credentials Packer sets on the VDA master image during the build |
| `CITRIX_VDA_INSTALLER_URL` / `CLOUDPAGING_PLAYER_INSTALLER_URL` / `CITRIX_OPTIMIZER_ZIP_URL` | Read-only SAS URLs to the respective installers/zip in artifact storage |

**Environment-scoped secrets** (Settings > Environments >
`citrix-cutover-approval-prod` > environment secrets - not repo-level):

| Secret | Used by | Purpose |
|---|---|---|
| `CITRIX_MAINTENANCE_CLIENT_ID` / `CITRIX_MAINTENANCE_CLIENT_SECRET` | `citrix-image-rotation.yml` (`promote-to-prod-and-drain` job) | A **third**, dedicated Citrix Cloud API client for `scripts/citrix_daas_maintenance.py`'s maintenance-mode/drain/power-off calls - deliberately separate from both `CITRIX_CLIENT_SECRET` (the Terraform provider's) and the Cloud Connector registration client, since this one can drain and power off live production VDAs. Scoped to just this one environment (rather than repo-level, like everything else above) since it's a script argument, not part of any Terraform map, and only this one job ever needs it |

**Also required (not a GitHub secret/variable):** a required-reviewer rule on
each of the following environments (repo Settings > Environments) - **six**
total, one pair per delivery-group environment, so Dev/Test can be
lighter-gated or ungated while Prod requires a named reviewer:

- `citrix-cutover-approval-dev`, `citrix-cutover-approval-test`, `citrix-cutover-approval-prod`
- `citrix-decommission-approval-dev`, `citrix-decommission-approval-test`, `citrix-decommission-approval-prod`

(`citrix-cutover-approval-prod` also gates the `apply` action and the
automatic `promote-to-prod-and-drain` job, since either can touch Prod - a
push to `main` starts that job, but it still pauses for the environment's
required reviewer before actually running.)

The `build` job (manual image builds) runs under a seventh environment,
`techops-monthly-daas` - gate it however TechOps wants monthly golden-image
builds reviewed. None of these seven environments exist yet in this repo
(confirmed via `gh api repos/{owner}/{repo}/environments`) - create each one
(Settings > Environments > New environment, or `gh api .../environments/<name> -X PUT`)
before setting `CITRIX_MAINTENANCE_CLIENT_ID`/`_SECRET` on
`citrix-cutover-approval-prod` or adding required-reviewer rules.
