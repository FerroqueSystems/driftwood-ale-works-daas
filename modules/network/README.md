# Network Module

Azure virtual network and subnet for the Citrix resource location - hosts the
domain controllers, Cloud Connectors, and VDAs.

No NetScaler ADC or inbound gateway rules are provisioned here: session traffic
is brokered by the Citrix Cloud Gateway service, so the subnet's NSG only needs
to allow outbound access to Citrix Cloud and Azure (plus the temporary SSH
rule below).

A NAT Gateway is attached to the subnet to provide that outbound path
explicitly. Azure no longer grants new deployments implicit "default outbound
access" - without an explicit NAT Gateway (or public IP/load balancer),
domain controllers, Cloud Connectors, and VDAs have no route to the internet
at all, which breaks Custom Script Extension downloads, Windows Update, and
Citrix Cloud connectivity. See
[Default outbound access in Azure](https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access).

## Temporary SSH access (`admin_ssh_source_cidr`)

This subscription has no pre-existing Bastion/VPN/jump host, so there's
normally no way to reach anything in the VDA subnet from outside the VNet -
by design, the NSG above has no inbound rules. When
`var.admin_ssh_source_cidr` is set (non-null), this module adds a single
inbound-allow rule for TCP/22 scoped to that CIDR, for the one-time
[self-hosted GitHub runner](../github-runner/README.md) registration step -
see [`bootstrap-github-runner-commands.txt`](../../environments/citrix-azure/bootstrap-github-runner-commands.txt).
Leave it unset otherwise. Note that Azure evaluates subnet-level and
NIC-level NSGs independently, so a NIC-level rule alone (without this one)
would still be blocked by this subnet's default deny.

See `variables.tf` / `outputs.tf` for inputs and outputs, and
[environments/citrix-azure](../../environments/citrix-azure/README.md) for how
this module is wired up.
