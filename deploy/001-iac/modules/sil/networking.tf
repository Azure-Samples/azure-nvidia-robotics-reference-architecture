/**
 * # AKS Networking Resources
 *
 * This file creates the AKS-specific networking infrastructure for the SiL module including:
 * - AKS system node pool subnets (nodes and pods)
 * - GPU node pool subnets (nodes and pods)
 * - NSG associations for all AKS subnets
 * - NAT Gateway associations for outbound connectivity
 *
 * Note: Shared networking resources (VNet, NSG, NAT Gateway) are provided by the platform module.
 */

// ============================================================
// AKS System Node Pool Subnets
// ============================================================

// AKS Nodes Subnet
resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = var.virtual_network.name
  address_prefixes     = [var.aks_subnet_config.subnet_address_prefix_aks]
}

// AKS Pods Subnet
resource "azurerm_subnet" "aks_pod" {
  name                 = "snet-aks-pod-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = var.virtual_network.name
  address_prefixes     = [var.aks_subnet_config.subnet_address_prefix_aks_pod]
}

// ============================================================
// GPU Node Pool Subnets
// ============================================================

resource "azurerm_subnet" "gpu_node_pool" {
  for_each = var.node_pools

  name                 = "snet-aks-${each.key}-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = var.virtual_network.name
  address_prefixes     = each.value.subnet_address_prefixes
}

resource "azurerm_subnet" "gpu_node_pool_pod" {
  for_each = var.node_pools

  name                 = "snet-aks-${each.key}-pod-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = var.virtual_network.name
  address_prefixes     = each.value.pod_subnet_address_prefixes
}

// ============================================================
// NSG Associations
// ============================================================

// NSG Associations for AKS system subnets
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = var.network_security_group.id
}

resource "azurerm_subnet_network_security_group_association" "aks_pod" {
  subnet_id                 = azurerm_subnet.aks_pod.id
  network_security_group_id = var.network_security_group.id
}

// NSG Associations for GPU node pool subnets
resource "azurerm_subnet_network_security_group_association" "gpu_node_pool" {
  for_each = var.node_pools

  subnet_id                 = azurerm_subnet.gpu_node_pool[each.key].id
  network_security_group_id = var.network_security_group.id
}

resource "azurerm_subnet_network_security_group_association" "gpu_node_pool_pod" {
  for_each = var.node_pools

  subnet_id                 = azurerm_subnet.gpu_node_pool_pod[each.key].id
  network_security_group_id = var.network_security_group.id
}

// ============================================================
// NAT Gateway Associations
// ============================================================

// NAT Gateway Association for AKS system subnet
resource "azurerm_subnet_nat_gateway_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = var.nat_gateway.id
}

// NAT Gateway Associations for GPU node pool subnets
resource "azurerm_subnet_nat_gateway_association" "gpu_node_pool" {
  for_each = var.node_pools

  subnet_id      = azurerm_subnet.gpu_node_pool[each.key].id
  nat_gateway_id = var.nat_gateway.id
}
