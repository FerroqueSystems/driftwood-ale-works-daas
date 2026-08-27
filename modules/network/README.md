# Network Module

Azure virtual network and subnet for the Citrix resource location - hosts the
Cloud Connectors and VDAs.

No NetScaler ADC or inbound gateway rules are provisioned here: session traffic
is brokered by the Citrix Cloud Gateway service, so the subnet's NSG only needs
to allow outbound access to Citrix Cloud and Azure.

A NAT Gateway is attached to the subnet to provide that outbound path
explicitly. Azure no longer grants new deployments implicit "default outbound
access" - without an explicit NAT Gateway (or public IP/load balancer), Cloud
Connectors and VDAs have no route to the internet at all, which breaks VM
extensions (e.g. `ConfigureRemotingForAnsible` in
[modules/cloud-connectors](../cloud-connectors/README.md)), Windows Update, and
Citrix Cloud connectivity. See
[Default outbound access in Azure](https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access).

## Route table caveat (Cato SD-WAN)

In this environment the subnet also has a route table applied outside this
repo's Terraform - a corporate Cato SD-WAN UDR that force-tunnels the
subnet's internet-bound traffic through Cato instead of straight out to the
internet. That silently defeats the NAT Gateway above for anything routed by
the UDR's default (`0.0.0.0/0`) route, even though the NAT Gateway is
correctly attached - VM extension *control-plane* traffic (e.g.
`AADLoginForWindows`) still works because it goes over Azure's
`168.63.129.16` wireserver path, which bypasses subnet UDRs by design, but a
real in-guest HTTPS call (e.g. `CustomScriptExtension` downloading a blob)
does not.

The subnet enables the `Microsoft.Storage` service endpoint to work around
this for Azure Storage traffic specifically: it adds a more specific system
route for Storage's prefixes (next hop `VirtualNetwork`) that wins over the
UDR's `0.0.0.0/0`, keeping that traffic on the Microsoft backbone regardless
of Cato. This is what lets the `ConfigureRemotingForAnsible` extension in
[modules/cloud-connectors](../cloud-connectors/README.md) reach the
artifact-storage blob. It does **not** fix connectivity for anything else the
Cato UDR still force-tunnels (Windows Update, Citrix Cloud control-plane
calls, etc.) - those need an explicit allow rule from whoever manages the
Cato policy, which this repo has no visibility into or control over.

See `variables.tf` / `outputs.tf` for inputs and outputs, and
[environments/citrix-azure](../../environments/citrix-azure/README.md) for how
this module is wired up.
