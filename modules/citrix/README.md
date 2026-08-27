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
  provisions from (see below)
- `citrix_machine_catalog` / `citrix_delivery_group` - one machine catalog per
  entry in `var.image_versions`, all assigned to a single delivery group

## Monthly image/catalog rotation

`var.image_versions` is a map keyed by a `"YYMM-N"` build label (e.g.
`"2607-1"` for the first 2026-07 build) - each entry gets its own
`citrix_image_version` + `citrix_machine_catalog`, and is assigned to the
delivery group with its own `machine_count`. There's no technical limit on
how many entries can coexist - `citrix_machine_catalog`/`citrix_image_version`
are `for_each`-driven, and `associated_machine_catalogs` already filters to
`machine_count > 0` regardless of total count. `scripts/rotate_image_versions.py`'s
`build` command applies a soft cap (`--max-entries`, default 5) against
unbounded catalog sprawl when staging a *brand new* label - `cutover` and
`decommission` aren't limited by it and can target any already-staged label
at any time, which matters when multiple people are staging builds in
parallel.

This is driven end-to-end by
[.github/workflows/citrix-image-rotation.yml](../../.github/workflows/citrix-image-rotation.yml)
and [scripts/rotate_image_versions.py](../../scripts/rotate_image_versions.py),
which edit [environments/citrix-azure/rotation.auto.tfvars.json](../../environments/citrix-azure/rotation.auto.tfvars.json)
(the git-tracked source of `var.image_versions`):

1. **build** (unattended) - Packer publishes a new golden image version,
   then a new machine catalog is staged with `machine_count = 0` (provisioned,
   not yet serving sessions). Citrix rejects **any** entry in a delivery
   group's `associated_machine_catalogs` with `machine_count = 0` ("machine_count
   of the associated catalog cannot be less than 1") - not just a newly-added
   catalog, but an existing one whose count has been drained to 0 too. So
   `modules/citrix/main.tf` filters `associated_machine_catalogs` down to
   only catalogs with `machine_count > 0`; a label at 0 (freshly staged, or
   drained ahead of decommission) simply isn't in the list. On top of that,
   the build step's `terraform apply` is scoped with `-target` to just that
   label's `citrix_image_version`/`citrix_machine_catalog`, so it doesn't
   even attempt a delivery-group update while staging. **Exception: the very
   first catalog ever** - there's no existing delivery group to attach a
   catalog to and no outgoing catalog to cut over from, so bootstrap it with
   `machine_count` equal to `total_machines` directly in
   `rotation.auto.tfvars.json` instead of going through the normal
   0-then-cutover flow.
2. **cutover** (gated behind the `citrix-cutover-approval` environment,
   requires a manual approval) - the delivery group is reassigned: the new
   catalog's `machine_count` ramps up (added to `associated_machine_catalogs`
   for the first time), the outgoing catalog's drops to 0 (removed from
   `associated_machine_catalogs`, per the filter above).
3. **decommission** (gated behind `citrix-decommission-approval`) - once the
   outgoing catalog is fully drained (`machine_count = 0`, already excluded
   from the delivery group), its `citrix_machine_catalog`/`citrix_image_version`
   are deleted.

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
