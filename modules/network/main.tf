resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags

  # Points at the two domain controllers (modules/domain-controllers) once
  # var.dns_servers is set - the only mechanism Citrix MCS-provisioned VDA
  # NICs can pick up AD domain DNS through (no per-catalog DNS override
  # exists in the citrix/citrix provider). Domain controllers themselves
  # don't depend on this: dc-0 self-reconfigures via Install-ADDSForest
  # -InstallDns, dc-1 and Cloud Connectors get an explicit NIC-level
  # override instead (see those modules) - so there's no circular
  # dependency even though this list's values come from resources created
  # after this vnet.
  dns_servers = length(var.dns_servers) > 0 ? var.dns_servers : null
}

resource "azurerm_subnet" "vda" {
  name                 = var.vda_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.vda_subnet_address_prefixes

  # No external route table applies to this subnet - this environment's own
  # NAT Gateway below is the sole egress path. The Microsoft.Storage service
  # endpoint keeps in-guest Azure Storage traffic (e.g. artifact downloads)
  # on the Microsoft backbone rather than through the NAT Gateway.
  service_endpoints = ["Microsoft.Storage"]
}

# The Citrix Cloud Gateway service brokers all inbound ICA/HDX sessions, so this
# resource location does not need a NetScaler ADC or any inbound NSG rules -
# Cloud Connectors and VDAs only need outbound access to Citrix Cloud and Azure.
# The one exception is the temporary SSH rule below, for reaching the
# self-hosted GitHub runner VM (modules/github-runner) in a subscription with
# no other pre-existing connectivity (Bastion/VPN/jump host).
resource "azurerm_network_security_group" "vda" {
  name                = "${var.vda_subnet_name}-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "vda" {
  subnet_id                 = azurerm_subnet.vda.id
  network_security_group_id = azurerm_network_security_group.vda.id
}

# Temporary, source-IP-scoped inbound SSH allow - only present while
# var.admin_ssh_source_cidr is set (see environments/citrix-azure/main.tf and
# bootstrap-github-runner-commands.txt). Subnet-level and NIC-level NSGs are
# evaluated independently by Azure, so this has to live here (the subnet's
# NSG) rather than solely on the runner's NIC, since the subnet NSG's
# implicit deny-all-inbound would otherwise still block it.
resource "azurerm_network_security_rule" "runner_temp_ssh" {
  count                       = var.admin_ssh_source_cidr != null ? 1 : 0
  name                        = "AllowTemporarySSHFromAdmin"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.admin_ssh_source_cidr
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vda.name
}

# Explicit outbound internet path for the subnet. Azure no longer grants new
# deployments implicit "default outbound access" - without this, domain
# controllers, Cloud Connectors, and VDAs have no route out at all, which
# breaks anything that needs it (Custom Script Extension downloads, Windows
# Update, Citrix Cloud connectivity). See
# https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access.
resource "azurerm_public_ip" "nat" {
  name                = "${var.vnet_name}-nat-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "${var.vnet_name}-natgw"
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway_idle_timeout_minutes
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "vda" {
  subnet_id      = azurerm_subnet.vda.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
