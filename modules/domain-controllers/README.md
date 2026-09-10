# Domain Controllers Module

Provisions two Windows Server domain controllers: `dc-0` promotes a brand-new
AD DS forest, `dc-1` joins it as an additional DC for redundancy. Exists
because this environment switched from Entra ID-joined VDAs to traditional
AD-domain-joined VDAs + Cloud Connectors (see
[modules/cloud-connectors](../cloud-connectors/README.md) and
[modules/citrix](../citrix/README.md)) - the previous design had no AD domain
at all.

## Automation, and its real risk

This is **fully scripted end-to-end** - no manual runbook fallback. That's a
deliberate choice given a tight timeline, but it's worth being direct about
what "fully scripted" means here: there is no first-class Azure extension
for creating an AD forest (unlike domain *join*, which has one - see
`JsonADDomainExtension` in `modules/cloud-connectors`). Forest promotion is
hand-rolled via `CustomScriptExtension` plus a deliberately delayed reboot
(`Install-ADDSForest -NoRebootOnCompletion` followed by
`shutdown.exe /r /t 90`, so the extension reports success *before* the VM
actually goes down - otherwise Azure sees the VM disappear mid-extension and
reports a false failure). This is a well-documented pattern, not a novel
hack, but it - and the wait-loops in `dc-1`'s and the Cloud Connectors'
scripts - has not been exercised against real Azure/Citrix Cloud from this
repo. **Run a full end-to-end `terraform apply` in the Lab subscription well
before the conference**, not just before demo day.

## What happens, in order

1. **`dc-0`** (`scripts/promote-forest.ps1`): installs AD-DS, registers a
   run-once-at-startup scheduled task pointing at `post-promotion-setup.ps1`
   (already downloaded alongside this script, since none of AD DS is
   reliably queryable until after the reboot), then runs
   `Install-ADDSForest` and schedules the delayed reboot. Idempotent - checks
   `Win32_ComputerSystem.DomainRole` first and skips if already a DC, so a
   re-applied extension is safe.
2. **After `dc-0` reboots**, the scheduled task runs
   `scripts/post-promotion-setup.ps1` automatically, as `SYSTEM` (no domain
   credential needed - it's running locally on the now-live DC): creates the
   OU structure (`OU=Driftwood`, with `OU=VDAs` and `OU=Cloud Connectors`
   underneath), a service account (`svc-mcs` by default) used both for MCS
   provisioning (`modules/citrix`) and Cloud Connector domain join
   (`modules/cloud-connectors`), and three AD security groups
   (`Driftwood Dev/QA/Prod Desktop Users`) for the delivery groups' access
   lists. Idempotent via a marker file; unregisters its own scheduled task
   once done.
3. **`dc-1`** (`scripts/promote-additional-dc.ps1`): its NIC has an explicit
   `dns_servers` override pointing at `dc-0`'s static IP (set by the
   environment, not this module - see `environments/citrix-azure/main.tf`).
   Waits (up to 20 minutes, retrying every 30s) for the `svc-mcs` service
   account to actually be queryable on `dc-0` before doing anything - a real
   race, not a formality, since `dc-0`'s own extension reports success
   *before* `dc-0` has even rebooted. Then runs `Install-ADDSDomainController`
   using `svc-mcs`'s credentials (not a "default domain Administrator"
   account - deliberately avoids relying on untested
   built-in-Administrator-carries-over-to-domain-admin behavior, which may
   not even hold the way it would on-prem given how Azure provisions the
   local admin account). Same idempotency/delayed-reboot pattern as `dc-0`.

## Demo-only simplification: `svc-mcs` is a Domain Admin

`post-promotion-setup.ps1` adds the service account straight to **Domain
Admins**, rather than delegating the specific, narrower
`Create/Delete/Manage Computer Objects` rights Citrix's own docs recommend
for MCS provisioning (typically via `dsacls` ACEs on the target OU). This is
a deliberate demo-only shortcut - full Domain Admin avoids a multi-line ACL
delegation script running unattended and untested; it is **not** what you'd
want in a real production AD environment. If reusing this module beyond the
conference demo, replace this with proper least-privilege delegation.

## Static IPs

Both domain controllers get **static** (not Dynamic) private IPs, computed
via `cidrhost(var.subnet_address_prefix, 4)` / `cidrhost(..., 5)` - the first
two usable addresses in the subnet, known at Terraform plan time. This is
what lets `modules/network`'s VNet-level `dns_servers` and
`modules/cloud-connectors`' NIC-level `dns_servers` override reference these
IPs directly with no create-order dependency on the DC resources themselves.

## Bootstrap scripts storage

This module creates its own small storage account (public blob read) purely
to host its three PowerShell scripts at a stable HTTPS URL Custom Script
Extensions can fetch. The scripts themselves carry no secrets - every
sensitive value (passwords) is passed in as a Custom Script Extension or
Scheduled Task *argument* instead (see `main.tf`'s `protected_settings`
blocks), so public blob read access here is fine and avoids the SAS-token
expiry/diffing complexity a private container would otherwise need.
