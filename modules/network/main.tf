resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "vda" {
  name                 = var.vda_subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.vda_subnet_address_prefixes

  # A route table applied outside this repo's Terraform (a corporate Cato
  # SD-WAN UDR) force-tunnels this subnet's internet-bound traffic off-box,
  # which breaks in-guest calls to Azure Storage (e.g. the CustomScriptExtension
  # blob download in modules/cloud-connectors) regardless of the NAT Gateway
  # below. The Microsoft.Storage service endpoint adds a more specific system
  # route (next hop VirtualNetwork) for Storage's prefixes that wins over the
  # UDR's 0.0.0.0/0, keeping that traffic on the Microsoft backbone instead of
  # through Cato. Doesn't require any change on the storage account's own
  # firewall here since modules/artifact-storage leaves it at the default
  # "Allow all networks".
  service_endpoints = ["Microsoft.Storage"]
}

# The Citrix Cloud Gateway service brokers all inbound ICA/HDX sessions, so this
# resource location does not need a NetScaler ADC or any inbound NSG rules -
# Cloud Connectors and VDAs only need outbound access to Citrix Cloud and Azure.
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

# Explicit outbound internet path for the subnet. Azure no longer grants new
# deployments implicit "default outbound access" - without this, Cloud
# Connectors and VDAs have no route out at all, which breaks anything that
# needs it (VM extensions like ConfigureRemotingForAnsible, Windows Update,
# Citrix Cloud connectivity). See
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
