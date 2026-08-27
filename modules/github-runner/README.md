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
