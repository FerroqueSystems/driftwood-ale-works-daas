# GitHub Runner Module

Provisions a single Linux VM (Ubuntu 22.04 LTS, SSH key auth only, no public
IP) inside the shared VDA subnet, to act as a self-hosted GitHub Actions
runner for [.github/workflows/citrix-image-rotation.yml](../../.github/workflows/citrix-image-rotation.yml).
GitHub-hosted runners have no network path into this private VNet, so
anything that needs to reach VMs in it directly has to run from inside it.

This module only creates the bare VM - it does not install/register the
GitHub Actions runner agent. That's a manual, one-time step (runner
registration tokens are short-lived and deliberately kept out of Terraform
state, the same reasoning as `CITRIX_CLIENT_SECRET` in
[../../environments/citrix-azure/providers.tf](../../environments/citrix-azure/providers.tf))
- see
[../../environments/citrix-azure/bootstrap-github-runner-commands.txt](../../environments/citrix-azure/bootstrap-github-runner-commands.txt).

## Reaching the VM for registration

A fresh subscription has no Bastion/VPN/jump host, so there's normally no
way to reach this VM's private IP at all. Set `enable_temporary_public_access`
to `true` to attach a temporary public IP to its NIC for the one-time SSH
registration step - this only actually admits traffic once paired with a
matching NSG allow rule ([modules/network](../network/README.md)'s
`admin_ssh_source_cidr`), since Azure evaluates subnet-level and NIC-level
NSGs independently. Set it back to `false` and re-apply once the runner is
registered - see `bootstrap-github-runner-commands.txt` for the full
step-by-step.
