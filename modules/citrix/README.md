# Citrix Module

Citrix DaaS control-plane resources for the Azure resource location, using the
[`citrix/citrix`](https://github.com/citrix/terraform-provider-citrix)
Terraform provider:

- `citrix_cloud_resource_location` - the Citrix Cloud resource location
- `citrix_zone` - the DaaS zone tied to that resource location
- `citrix_azure_hypervisor` - the Azure hosting connection (uses the service
  principal from [modules/identity](../identity/README.md))
- `citrix_azure_hypervisor_resource_pool` - the network/region config VDAs are
  provisioned into (uses the VNet/subnet from [modules/network](../network/README.md))
- `citrix_image_definition` / `citrix_image_version` - the Citrix Image
  Management Service objects wrapping the Azure Compute Gallery image
  Packer publishes into (see [modules/image-gallery](../image-gallery/README.md)
  and [../../packer](../../packer/README.md)) - created for Citrix Cloud's
  Image Management visibility, but **not** what the machine catalog actually
  provisions from (see below). Shared across every environment - one golden
  image lineage feeds dev/test/prod alike, so `citrix_image_version` is
  deduped down to one resource per unique build label even when multiple
  environments have staged it (see `local.unique_image_versions` in `main.tf`)
- `citrix_machine_catalog` / `citrix_delivery_group` - **three** delivery
  groups (dev/test/prod, `for_each = var.delivery_groups`), each with its own
  independent set of machine catalogs (`for_each`-flattened from
  `var.catalog_rotation`, keyed `"<environment>-<label>"`)
- `azurerm_resource_group.vda` - one dedicated resource group per machine
  catalog build (same `"<environment>-<label>"` keying, named
  `"rg-vda-<environment>-<label>"`), holding that build's MCS-provisioned
  VDA VMs/NICs/disks (`azure_machine_config.vda_resource_group`). This is
  the only `azurerm` resource this module creates - deliberately per-build
  rather than one resource group shared by every catalog/environment, so
  different rotation generations (or different environments) never share
  VMs/NICs/disks and can't collide or bleed into each other during
  cutover/decommission. The Template Spec machine profile
  (`var.machine_profile_resource_group_name`) is a separate, manually-created
  shared asset and intentionally stays in one resource group across every
  build - see "Machine identity and machine profile" below.

## Monthly image/catalog rotation, per environment

`var.catalog_rotation` is a map keyed by environment (`"dev"`/`"test"`/`"prod"`),
each holding a map keyed by `"YYMM-N"` build label (e.g. `"2607-1"` for the
first 2026-07 build) - each `(environment, label)` pair gets its own
`citrix_machine_catalog`, assigned to that environment's delivery group with
its own `machine_count`. Every environment's rotation state is fully
independent - dev can be on a different label than prod, cut over on its own
schedule - even though the same label always means the same underlying
`gallery_image_version` everywhere it's staged (enforced by a `validation`
block on `var.catalog_rotation`), since one shared Packer build feeds all
three. There's no technical limit on how many entries can coexist per
environment - `citrix_machine_catalog` is `for_each`-driven off the flattened
map, and each delivery group's `associated_machine_catalogs` already filters
to `machine_count > 0` regardless of total count.
`scripts/rotate_image_versions.py`'s `build` command applies a soft cap
(`--max-entries`, default 5, scoped per environment) against unbounded
catalog sprawl when staging a *brand new* label in one environment -
`cutover` and `decommission` aren't limited by it and can target any
already-staged label in any environment at any time, which matters when
multiple people are staging builds in parallel.

This is driven end-to-end by
[.github/workflows/citrix-image-rotation.yml](../../.github/workflows/citrix-image-rotation.yml)
(which takes an `environment` input alongside `action`) and
[scripts/rotate_image_versions.py](../../scripts/rotate_image_versions.py)
(which takes a matching `--env`), both editing
[environments/citrix-azure/rotation.auto.tfvars.json](../../environments/citrix-azure/rotation.auto.tfvars.json)
(the git-tracked source of `var.catalog_rotation`):

1. **build** (unattended) - Packer publishes a new golden image version (or
   this step is skipped if another environment already published this exact
   version - it's shared), then a new machine catalog is staged in the
   chosen environment with `machine_count = 0` (provisioned, not yet serving
   sessions). Citrix rejects **any** entry in a delivery group's
   `associated_machine_catalogs` with `machine_count = 0` ("machine_count of
   the associated catalog cannot be less than 1") - not just a newly-added
   catalog, but an existing one whose count has been drained to 0 too. So
   `modules/citrix/main.tf` filters each delivery group's
   `associated_machine_catalogs` down to only that environment's catalogs
   with `machine_count > 0`; a label at 0 (freshly staged, or drained ahead
   of decommission) simply isn't in the list. On top of that, the build
   step's `terraform apply` is scoped with `-target` to just that
   `(environment, label)` pair's `citrix_machine_catalog` (and the shared
   `citrix_image_version`, keyed by label only), so it doesn't even attempt a
   delivery-group update while staging. **Exception: the very first catalog
   in a brand new environment** - there's no existing delivery group
   association to attach a catalog to and no outgoing catalog to cut over
   from, so bootstrap it with `machine_count` equal to `total_machines`
   directly in `rotation.auto.tfvars.json` instead of going through the
   normal 0-then-cutover flow. This applies independently the first time
   each of dev/test/prod is stood up.
2. **cutover** (gated behind the `citrix-cutover-approval-<environment>`
   environment - e.g. `citrix-cutover-approval-prod` - requires a manual
   approval, tunable per environment) - that environment's delivery group is
   reassigned: the new catalog's `machine_count` ramps up (added to
   `associated_machine_catalogs` for the first time), the outgoing catalog's
   drops to 0 (removed from `associated_machine_catalogs`, per the filter
   above). Other environments are untouched.
3. **decommission** (gated behind `citrix-decommission-approval-<environment>`)
   - once the outgoing catalog is fully drained (`machine_count = 0`,
   already excluded from the delivery group) **in that environment**, its
   `citrix_machine_catalog` and dedicated `azurerm_resource_group.vda` entry
   are both deleted (Terraform's dependency graph destroys the catalog
   before the resource group automatically, since the catalog references it).
   The underlying `citrix_image_version` and Azure Compute Gallery image
   version are only deleted if **no other environment** still references
   that build label - since the image version is shared/deduped across
   environments, deleting it out from under an environment still live on it
   would break that environment. The workflow checks this before calling
   `az sig image-version delete`. If a decommission apply hits a transient
   conflict deleting the resource group (e.g. Citrix's own MCS cleanup still
   finishing in the background), it's safe to just re-run - resource group
   deletion cascades over anything left inside it regardless of Terraform's
   own tracking, and destroys are idempotent.

## Machine identity and machine profile

Machine identity is `AzureAD` (Entra ID-joined) - no traditional AD domain.
`identity_type = "AzureAD"` requires a `machine_profile` (Citrix derives
machine defaults - size, boot diagnostics, OS disk caching, accelerated
networking - from it, since it can't infer them from an AD OU). Two things
that aren't obvious from Citrix's docs, found by testing directly against
the API (`citrix/citrix` provider v1.0.38):

- **`machine_profile` must be an Azure Template Spec, not a VM reference,
  when the catalog also has `machine_profile` set alongside a gallery-image
  source.** A VM-based profile fails with an unhelpful "machine_profile
  cannot be specified when using prepared image without a machine profile"
  error - regardless of `machine_profile`'s form.
- **The machine catalog uses `azure_master_image` (direct
  gallery/definition/version reference), not `prepared_image`** (which
  references the `citrix_image_version` resource by ID). `prepared_image` +
  `machine_profile` + `identity_type = "AzureAD"` hits that same validation
  error no matter what form `machine_profile` takes - this looks like an
  unresolved provider bug specific to that three-way combination.
  `citrix_image_version` is still created (for Image Management visibility
  in the Citrix Cloud console), it's just not referenced by the catalog.

### Creating the machine profile Template Spec

Not Terraform-managed - created once, out-of-band, via `az ts create`. It
must contain **only** generic hardware properties, not VM/OS-instance-specific
ones (no `osProfile`, no `imageReference`, no `securityProfile` - `Standard`
is explicitly rejected):

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "resources": [
    {
      "type": "Microsoft.Network/networkInterfaces",
      "apiVersion": "2023-09-01",
      "name": "<profile-nic-name>",
      "location": "<region>",
      "properties": {
        "enableAcceleratedNetworking": false,
        "ipConfigurations": [{
          "name": "internal",
          "properties": {
            "primary": true,
            "privateIPAllocationMethod": "Dynamic",
            "subnet": { "id": "<vda-subnet-resource-id>" }
          }
        }]
      }
    },
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2023-09-01",
      "name": "<profile-vm-name>",
      "location": "<region>",
      "dependsOn": ["[resourceId('Microsoft.Network/networkInterfaces', '<profile-nic-name>')]"],
      "properties": {
        "hardwareProfile": { "vmSize": "<same SKU as citrix_vda_service_offering>" },
        "diagnosticsProfile": { "bootDiagnostics": { "enabled": false } },
        "storageProfile": { "osDisk": { "caching": "ReadWrite", "osType": "Windows" } },
        "networkProfile": {
          "networkInterfaces": [{
            "id": "[resourceId('Microsoft.Network/networkInterfaces', '<profile-nic-name>')]",
            "properties": { "primary": true }
          }]
        }
      }
    }
  ]
}
```

`osDisk.osType` is required and must match the VDA image's OS ("Windows"
here) - omitting it or leaving it as the OS of some unrelated VM you exported
the template from (e.g. a Linux self-hosted runner) fails with "Invalid OS
type setting" or a deployment-time "Changing property 'osDisk.osType' is not
allowed" error respectively.

```bash
az ts create --name <name> --version <version> \
  --resource-group <rg> --location <region> \
  --template-file <path-to-template-above>
```

Then set `machine_profile_template_spec_name` / `_version` /
`_resource_group_name` in `environments/citrix-azure/terraform.tfvars` to
match.
