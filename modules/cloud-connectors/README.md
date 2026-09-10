# Cloud Connectors Module

Provisions the Azure VMs that host Citrix Cloud Connectors - the software
that brokers communication between Citrix Cloud and this Azure resource
location (hypervisor connection, domain-joined VDA registration and
brokering). Defaults to 2 VMs, Citrix's recommended minimum for high
availability. Required in the zone for AD-domain-joined machine catalogs
(see [modules/citrix](../citrix/README.md)) - Citrix Cloud won't otherwise
have a way to reach on-prem-AD-joined VDAs.

Domain-joined against the forest [modules/domain-controllers](../domain-controllers/README.md)
creates, then the Cloud Connector software itself is installed and
registered against Citrix Cloud - all via Custom Script Extensions/Azure's
built-in domain-join extension, fully automated, no manual step.

## What happens, in order, per connector VM

1. NIC gets an explicit `dns_servers` override (the two domain controllers'
   static IPs) - not relying on VNet-level DNS propagation timing.
2. `WaitForDomain` (`scripts/wait-for-domain.ps1`) - polls the AD domain's
   Netlogon SRV record via both domain controllers until it resolves (up to
   20 minutes). Needed because `modules/domain-controllers`' own extensions
   report success *before* their post-promotion reboots complete - a real
   race without this, not just a formality.
3. `DomainJoin` - the standard Azure `JsonADDomainExtension` (unlike domain
   *promotion*, domain *join* has proper, well-tested first-class Azure
   support), using the service account `modules/domain-controllers` creates.
4. `InstallCloudConnector` (`scripts/install-cloud-connector.ps1`) -
   downloads the Cloud Connector installer and silently installs/registers
   it against Citrix Cloud. Silent-install mechanism and JSON parameter
   schema confirmed directly against Citrix's own docs
   (`CWCConnector.exe /q /ParametersFilePath:<json>`, with
   `customerName`/`clientId`/`clientSecret`/`resourceLocationId`/`acceptTermsOfService`).
   Exit code `0` = success; the script treats anything else as a failure
   (`2` = prerequisite check failed, `1603` = unexpected error - see
   `%ProgramData%\Citrix\WorkspaceCloud\InstallLogs` on the VM).

Each step's Terraform resource `depends_on`s the previous one.

## Credentials: a separate Citrix Cloud API client

Cloud Connector registration uses its own `cloud_connector_client_id`/
`cloud_connector_client_secret` - deliberately **not** the same
`citrix_client_id`/`CITRIX_CLIENT_SECRET` the Terraform provider itself uses
(see `environments/citrix-azure/providers.tf`). Both are technically the
same kind of Citrix Cloud "Secure Client" object, so reuse would likely work,
but it would couple two otherwise-unrelated secrets' blast radius (rotating
one breaks both paths) for no real benefit - mint a second API client in the
Citrix Cloud console instead.

## Before applying: upload the Cloud Connector installer

Unlike this module's own helper scripts (Terraform-managed, uploaded
automatically to a small public-blob-read storage account this module
creates), the actual Cloud Connector installer (`CWCConnector.exe`) is a
Citrix-licensed binary tied to your Citrix Cloud account and can't be
fetched automatically:

1. Download the installer from the Citrix Cloud console (Resource Locations
   \> your resource location \> Cloud Connector download).
2. Upload it to the private artifact-storage container (see
   [modules/artifact-storage](../artifact-storage/README.md)) - same pattern
   as the Packer VDA installer/Optimizer zip in
   [packer/images/README.md](../../packer/images/README.md).
3. Generate a read-only SAS URL for that blob and pass it as this module's
   `cloud_connector_installer_url` variable (sensitive).

## First-apply race with `module.citrix`

`CWCConnector.exe` exiting `0` means the install succeeded, not that the
connector has completed its first heartbeat/registration with Citrix Cloud.
`module.citrix` (which needs a healthy connector in the zone for
AD-domain-joined machine catalogs) `depends_on`s this module, but that only
orders the resource-creation calls, not that functional registration. If the
very first `terraform apply` from scratch hits a transient zone/connector
error on `module.citrix`, that's an expected race - re-running `apply` a few
minutes later is the fix (same "safe to retry" pattern used elsewhere in
this repo, e.g. the per-catalog resource-group decommission caveat in
[modules/citrix/README.md](../citrix/README.md)).
