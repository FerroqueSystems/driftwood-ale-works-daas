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
  cutover/decommission.

## Image/catalog rotation, per environment

`var.catalog_rotation` is a map keyed by environment (`"dev"`/`"test"`/`"prod"`),
each holding a map keyed by a build label - each `(environment, label)` pair
gets its own `citrix_machine_catalog`, assigned to that environment's
delivery group with its own `machine_count`. Every environment's rotation
state is fully independent - dev can be on a different label than prod, cut
over on its own schedule - even though the same label always means the same
underlying `gallery_image_version` everywhere it's staged (enforced by a
`validation` block on `var.catalog_rotation`), since one shared Packer
build feeds all three. There's no technical limit on how many entries can
coexist per environment - `citrix_machine_catalog` is `for_each`-driven off
the flattened map, and each delivery group's `associated_machine_catalogs`
already filters to `machine_count > 0` regardless of total count. There's
also no hard *cap* on entry count anymore (a per-environment `--max-entries`
hard block used to exist in `scripts/rotate_image_versions.py`'s `build`
command - retired once builds moved from ~1/month to potentially many/day,
see below - a hard block would have just broken iterative dev work).
`rotate_image_versions.py check-outstanding` instead warns (never blocks)
once more than 5 distinct labels are outstanding across all three
environments combined, as a nudge to decommission drained builds.

Every build label is `"YYMM-N"` (e.g. `"2607-1"` for the first 2026-07
build), just an opaque string key as far as `catalog_rotation` is
concerned - supplied as a `workflow_dispatch` input to the manual `build`
action, since that's the only path that ever creates a new label. The
Azure Compute Gallery version is a **separate**, purely numeric value
recorded alongside the label (`gallery_image_version`), derived from it
(`"YYMM-N"` -> `"YYMM.N.0"`). `cmd_decommission` in
`rotate_image_versions.py` reads this value back out of the recorded
rotation state rather than re-deriving it from the label string, so it
stays correct even for an older label predating this convention.

This is driven end-to-end by
[.github/workflows/citrix-image-rotation.yml](../../.github/workflows/citrix-image-rotation.yml)
and [scripts/rotate_image_versions.py](../../scripts/rotate_image_versions.py),
both editing
[environments/citrix-azure/rotation.auto.tfvars.json](../../environments/citrix-azure/rotation.auto.tfvars.json)
(the git-tracked source of `var.catalog_rotation`). Two trigger models:

**GitFlow (automatic, `push` triggers)** - promotion only, never a new build:
1. Push to `develop` (a working branch's approved changes merged in) ->
   whatever's currently live in Dev (`machine_count > 0` there) is promoted
   into Test - no new Packer build, just staging + cutover against the
   already-published image.
2. Push to `main` (develop merged in) -> same promotion pattern, Test into
   Prod, then the outgoing Prod catalog is drained (maintenance mode ->
   bounded wait for sessions to clear -> power off - see
   `scripts/citrix_daas_maintenance.py`) rather than deleted immediately.
   `citrix-cutover-approval-prod`'s required reviewer still applies here -
   the push starts the job, but it pauses for approval before actually
   cutting Prod over and draining the old catalog.

Dev itself is never pushed into automatically, not even by pushing to a
`feature/**`/`release/**`/`hotfix/**` branch - building and cutting Dev
over is always the manual step below, run by hand as many times as needed
before a change is considered ready to merge into `develop`.

Because both jobs 1-2 stage (`machine_count = 0`) and cut over
(`machine_count = N`) entirely within the JSON file before Terraform ever
runs once, a single **untargeted** `terraform apply` is safe for both -
there's no observable intermediate state where a delivery group would be
asked to associate a catalog at `machine_count = 0` (Citrix's actual
rejection case, see below).

**Manual (`workflow_dispatch`)** - for out-of-band operations (rebuilding
one environment in isolation, or a deliberate "stage now, cut over later"
flow with a real time gap for human review):

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
   of decommission) simply isn't in the list. Because this is a genuinely
   separate CI job from cutover (with a real time gap for approval), its
   `terraform apply` is scoped with `-target` to just that
   `(environment, label)` pair's `citrix_machine_catalog` (and the shared
   `citrix_image_version`, keyed by label only), so it doesn't even attempt a
   delivery-group update while staging.
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
   own tracking, and destroys are idempotent. This is the only path that
   ever actually deletes a Prod catalog - the automatic push-triggered flow
   only drains/powers it off (step 3 above), leaving decommission as a
   later, deliberate, manual action.

## Machine identity

Machine identity is `ActiveDirectory` - VDAs join the traditional AD domain
[modules/domain-controllers](../domain-controllers/README.md) creates, and
brokering goes through the Cloud Connectors in
[modules/cloud-connectors](../cloud-connectors/README.md) (required in the
zone for AD-domain-joined machine catalogs - Citrix Cloud has no other path
to reach them). This replaced an earlier Entra ID-joined
(`identity_type = "AzureAD"`) design after real device-join issues in
production with no time to chase down before a deadline.

`identity_type = "ActiveDirectory"` needs a `machine_domain_identity` block
(`domain`, `domain_ou`, `service_account`, `service_account_password` - see
`main.tf`) instead of a `machine_profile`. Confirmed against the
`citrix/citrix` provider's own schema docs: `machine_profile` is only
required when `identity_type` is `AzureAD` (or `provisioning_type` is
`PVSStreaming`, not applicable here) - so this module no longer sets it at
all, which also removes the out-of-band Azure Template Spec creation step
(`az ts create`) the previous Entra ID-joined design required. `azure_master_image`
(direct gallery/definition/version reference, not `prepared_image`) is kept
as-is - no identity-specific quirk applies to that choice either way.

The domain, OU, and service account referenced here are created by
`modules/domain-controllers`' bootstrap scripts, not by this module - see
that module's README for exactly how (including a deliberate demo-only
simplification: the service account is a Domain Admin, not a
least-privilege OU delegation).
