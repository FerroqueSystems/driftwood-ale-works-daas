# Driftwood Ale Works - Citrix DaaS Infrastructure

Infrastructure-as-code for Driftwood Ale Works' (fictional) Citrix DaaS
deployment on Azure, built following the
[Citrix Automation Handbook, Part 5](https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/).

> This repo is the companion example for **"EUC as a Product: Turning
> Infrastructure Automation into a 'Paved Road' for Delivery Teams"** (World
> of EUC Amplify, Milwaukee). Driftwood Ale Works is a fictional brewing
> company used to illustrate what config drift looks like before GitOps/CI-CD,
> and what a paved road looks like after - real Terraform modules, a gated
> CI/CD pipeline (plan/apply approval gates, monthly image rotation), and the
> kinds of provider quirks you actually hit running Citrix DaaS on Azure.

## Architecture decisions

- **Session brokering via Citrix Cloud Gateway service** - no NetScaler ADC is
  part of this design.
- **Control plane**: Citrix Cloud (DaaS), managed via the
  [`citrix/citrix`](https://github.com/citrix/terraform-provider-citrix)
  Terraform provider.
- **Resource location**: Azure (VNet/subnet for VDAs), managed via `azurerm`.
- **Hosting connection identity**: an Azure AD app registration/service
  principal, managed via `azuread`.
- **No Cloud Connectors, no traditional AD domain** - VDAs are Microsoft
  Entra ID-joined only and register with Citrix Cloud directly via
  [Rendezvous Protocol](https://docs.citrix.com/en-us/citrix-daas/hdx-transport/rendezvous-protocol.html)
  (bypassing Cloud Connectors for VDA control/HDX traffic). The Azure hosting
  connection also talks to Azure's ARM API directly, so MCS provisioning
  never needed Cloud Connectors either. Enabling Rendezvous itself is a
  Citrix policy setting (`citrix_policy_set` in the `citrix` Terraform
  provider) - not yet wired up here, see Status below.
- **Golden image pipeline**: Packer builds the Windows VDA master image and
  publishes it to an Azure Shared Image Gallery, which the machine catalog
  references.

## Layout

- [`environments/citrix-azure`](environments/citrix-azure/README.md) - the
  root Terraform environment (providers, variables, module wiring)
- [`modules/network`](modules/network/README.md) - VNet/subnet for the
  resource location
- [`modules/identity`](modules/identity/README.md) - Azure AD hosting
  connection app registration
- [`modules/citrix`](modules/citrix/README.md) - Citrix Cloud resource
  location, zone, hypervisor, resource pool, image versioning, machine
  catalogs, and three delivery groups (Dev/Test/Prod). Each machine catalog
  build gets its own dedicated Azure resource group so different
  environments/rotation generations' VDA VMs/NICs/disks never share one.
- [`modules/image-gallery`](modules/image-gallery/README.md) - Azure Shared
  Image Gallery + image definition for VDA master images
- [`modules/artifact-storage`](modules/artifact-storage/README.md) - private
  storage account + blob container for Packer image build artifacts (VDA
  installer, Citrix Optimizer zip)
- [`modules/github-runner`](modules/github-runner/README.md) - self-hosted
  GitHub Actions runner VM (network access to the private VDA subnet)
- [`packer`](packer/README.md) - Packer template that builds the VDA master
  image and publishes it into the image gallery
- [`scripts/rotate_image_versions.py`](scripts/rotate_image_versions.py) -
  edits the golden image/machine catalog rotation state
- `.github/workflows/terraform.yml` - `terraform fmt`/`validate` on PRs
- `.github/workflows/packer.yml` - `packer fmt`/`validate` on PRs
- `.github/workflows/citrix-image-rotation.yml` - the monthly Patch-Tuesday
  build/cutover/decommission pipeline

`modules/cloud-connectors` (Terraform) still exists in the repo but is no
longer wired into `environments/citrix-azure` - kept in case a future
resource location needs traditional Cloud Connectors, not because this one
does.

## Status / next steps

Scaffolding is in place for the full pipeline described in the
[Citrix Automation Handbook, Part 5](https://community.citrix.com/tech-zone/automation/automation-handbook-2601-part5/):
network, identity, image gallery, artifact storage, Citrix DaaS objects
(including machine catalogs and three delivery groups - Dev/Test/Prod), a
self-hosted runner, and the monthly rotation workflow. Before any of it can
actually run against real infrastructure, it needs:

- [ ] Azure subscription ID + tenant ID for the **Lab** subscription this
      demo deploys into (Azure application piece)
- [ ] Citrix Cloud customer ID + API client ID/secret (Citrix Cloud auth)
- [ ] Remote state backend details (`environments/citrix-azure/backend.tf`)
- [ ] Naming/addressing decisions in `terraform.tfvars` (copy from
      `terraform.tfvars.example`) - real Entra ID access group object IDs
      for each of Dev/Test/Prod's `desktop_restricted_access_allow_list`
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
- [ ] Enable Rendezvous Protocol so VDAs register directly with Citrix Cloud
      (`citrix_policy_set` in the `citrix` Terraform provider, or a manual
      Citrix Cloud console policy) - not yet wired up

Remote PC / app publishing beyond desktops aren't in scope yet.

## GitHub repo secrets/variables

Configure these under repo Settings before running
`citrix-image-rotation.yml` manually. `terraform.yml` and `packer.yml`'s
existing `fmt`/`validate`-only jobs need none of these.

**Secrets:**

| Secret | Used by | Purpose |
|---|---|---|
| `ARM_CLIENT_ID` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID` | `citrix-image-rotation.yml` | OIDC federated login (`azure/login`) for the `azurerm`/`azuread` providers and the Terraform state backend. For this demo, `ARM_SUBSCRIPTION_ID` (and the federated credential on the Entra ID app behind `ARM_CLIENT_ID`) must point at the **Lab** Azure subscription, not a production one - the whole environment (including the self-hosted runner VM) is provisioned there. |
| `CITRIX_CLIENT_SECRET` | `citrix-image-rotation.yml` | Citrix Cloud API secret, read directly as an env var by `providers.tf` |
| `TERRAFORM_TFVARS_JSON` | `citrix-image-rotation.yml` | Full JSON of everything in `terraform.tfvars.example` (this file is gitignored/local-only, so CI needs its own copy) - now includes the `delivery_groups` map (Dev/Test/Prod names, published desktops, access lists, autoscale schedules) |
| `PACKER_BUILD_VARS_JSON` | `citrix-image-rotation.yml` | Full JSON of everything in `packer/images/win11-azure.pkrvars.hcl.example` (same reasoning) |
| `VDA_LOCAL_ADMIN_USERNAME` / `VDA_LOCAL_ADMIN_PASSWORD` | `citrix-image-rotation.yml` (`build` job) | Local admin credentials Packer sets on the VDA master image during the build |

**Also required (not a GitHub secret/variable):** a required-reviewer rule on
each of the following environments (repo Settings > Environments) - **six**
total, one pair per delivery-group environment, so Dev/Test can be
lighter-gated or ungated while Prod requires a named reviewer:

- `citrix-cutover-approval-dev`, `citrix-cutover-approval-test`, `citrix-cutover-approval-prod`
- `citrix-decommission-approval-dev`, `citrix-decommission-approval-test`, `citrix-decommission-approval-prod`

(`citrix-cutover-approval-prod` also gates the `apply` action, since an
untargeted `terraform apply` can touch any environment's delivery-group
config in one pass.)
