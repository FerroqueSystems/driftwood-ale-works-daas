# Cloud Connectors Module

Provisions the Azure VMs that host Citrix Cloud Connectors - the software
that brokers communication between Citrix Cloud and this Azure resource
location (hypervisor connection, Entra ID, and VDA registration). Defaults to
2 VMs, Citrix's recommended minimum for high availability.

This module only creates the VMs (Windows Server, Entra ID-joined via the
`AADLoginForWindows` extension, no traditional AD domain, no public IP). It
does **not** install or register the Cloud Connector software - that's a
manual, operator-run step using the Ansible playbook in
[../../ansible](../../ansible/README.md), executed from the self-hosted
GitHub Actions runner in [../github-runner](../github-runner/README.md) since
these VMs have no public network path.

One of these VMs' name/resource group is also used as the `machine_profile`
reference for the AzureAD-identity machine catalog in
[modules/citrix](../citrix/README.md) - see that module's `machine_profile_vm_name`
variable.

## WinRM bootstrap

Each VM also gets a `ConfigureRemotingForAnsible` custom script extension
that enables the WinRM HTTPS listener the Ansible playbook in
[../../ansible](../../ansible/README.md) needs. It runs the vendored copy of
Ansible's own bootstrap script at
[../../ansible/files/ConfigureRemotingForAnsible.ps1](../../ansible/files/ConfigureRemotingForAnsible.ps1)
rather than fetching it live from GitHub at apply time - that removes a
runtime dependency on an outside, unpinned third-party URL (and on this
subnet having outbound internet access at all, see
[modules/network](../network/README.md)).

Before applying this module:

1. Upload `ansible/files/ConfigureRemotingForAnsible.ps1` to the private
   artifact-storage container (see
   [modules/artifact-storage](../artifact-storage/README.md)) with Azure CLI
   or AzCopy - the same pattern used for the VDA installer/Optimizer zip in
   [packer/images/README.md](../../packer/images/README.md).
2. Generate a read-only SAS URL for that blob and pass it as this module's
   `winrm_bootstrap_script_url` variable (sensitive - supply via the
   `TF_VAR_winrm_bootstrap_script_url`-style environment variable at the
   environment level, never commit it to a tfvars file).

Since this extension only ever needs to run once at VM creation, use a
long-lived SAS token (e.g. a multi-year expiry) - if the URL value changes on
a later `terraform apply` where the VM already exists, Terraform will detect
a diff and re-run the extension unnecessarily.
