/**
 * # Networking Resources
 *
 * This file creates the networking infrastructure for the Platform module including:
 * - Network Security Group for traffic filtering
 * - Virtual Network with address space
 * - Subnets for main workloads, private endpoints, AKS nodes, and AKS pods
 * - NAT Gateway with public IP for outbound connectivity
 */

// Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${local.resource_name_suffix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  tags                = local.tags
}

// Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.resource_name_suffix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  address_space       = [var.virtual_network_config.address_space]
  tags                = local.tags
}

// Main Subnet - General workloads
resource "azurerm_subnet" "main" {
  name                 = "snet-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.virtual_network_config.subnet_address_prefix_main]
}

// Private Endpoints Subnet
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-pe-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.virtual_network_config.subnet_address_prefix_pe]
}

// NSG Associations
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.main.id
}

// NAT Gateway Public IP
resource "azurerm_public_ip" "nat_gateway" {
  name                = "pip-ng-${local.resource_name_suffix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

// NAT Gateway
resource "azurerm_nat_gateway" "main" {
  name                    = "ng-${local.resource_name_suffix}"
  location                = var.resource_group.location
  resource_group_name     = var.resource_group.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = ["1"]
  tags                    = local.tags
}

// NAT Gateway Public IP Association
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat_gateway.id
}

// NAT Gateway Subnet Associations
resource "azurerm_subnet_nat_gateway_association" "main" {
  subnet_id      = azurerm_subnet.main.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
