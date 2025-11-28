/**
 * # AKS Cluster Resources
 *
 * This file creates the Azure Kubernetes Service cluster for the SiL module including:
 * - AKS cluster with Azure CNI Overlay networking
 * - System node pool for core workloads
 * - GPU node pools via for_each (configurable)
 * - Integration with NAT Gateway for outbound connectivity
 * - Workload identity and OIDC issuer enabled
 * - Data Collection Rule associations for observability
 */

// ============================================================
// AKS Cluster
// ============================================================

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "aks-${local.resource_name_suffix}"
  location                          = var.resource_group.location
  resource_group_name               = var.resource_group.name
  dns_prefix                        = "aks-${var.resource_prefix}-${var.environment}"
  kubernetes_version                = null // Use latest stable version
  automatic_upgrade_channel         = "patch"
  sku_tier                          = "Standard"
  private_cluster_enabled           = var.aks_config.is_private_cluster
  local_account_disabled            = true
  azure_policy_enabled              = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  role_based_access_control_enabled = true
  node_os_upgrade_channel           = "NodeImage"
  tags                              = local.tags

  default_node_pool {
    name                        = "system"
    vm_size                     = var.aks_config.node_vm_size
    node_count                  = var.aks_config.enable_auto_scaling ? null : var.aks_config.node_count
    auto_scaling_enabled        = var.aks_config.enable_auto_scaling
    min_count                   = var.aks_config.enable_auto_scaling ? var.aks_config.min_count : null
    max_count                   = var.aks_config.enable_auto_scaling ? var.aks_config.max_count : null
    vnet_subnet_id              = azurerm_subnet.aks.id
    pod_subnet_id               = azurerm_subnet.aks_pod.id
    os_disk_size_gb             = 128
    os_disk_type                = "Ephemeral"
    temporary_name_for_rotation = "systemtemp"
    zones                       = ["1", "2", "3"]

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    outbound_type       = "userAssignedNATGateway"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    pod_cidr            = "10.244.0.0/16"
    load_balancer_sku   = "standard"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = []
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.main.id
    msi_auth_for_monitoring_enabled = true
  }

  monitor_metrics {
    annotations_allowed = null
    labels_allowed      = null
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.aks,
  ]
}

// ============================================================
// GPU Node Pools
// ============================================================

resource "azurerm_subnet" "gpu_node_pool" {
  for_each = var.node_pools

  name                 = "snet-aks-${each.key}-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = each.value.subnet_address_prefixes
}

resource "azurerm_subnet" "gpu_node_pool_pod" {
  for_each = var.node_pools

  name                 = "snet-aks-${each.key}-pod-${local.resource_name_suffix}"
  resource_group_name  = var.resource_group.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = each.value.pod_subnet_address_prefixes
}

resource "azurerm_subnet_network_security_group_association" "gpu_node_pool" {
  for_each = var.node_pools

  subnet_id                 = azurerm_subnet.gpu_node_pool[each.key].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_network_security_group_association" "gpu_node_pool_pod" {
  for_each = var.node_pools

  subnet_id                 = azurerm_subnet.gpu_node_pool_pod[each.key].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_nat_gateway_association" "gpu_node_pool" {
  for_each = var.node_pools

  subnet_id      = azurerm_subnet.gpu_node_pool[each.key].id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  for_each = var.node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  node_count            = each.value.enable_auto_scaling ? null : each.value.node_count
  auto_scaling_enabled  = each.value.enable_auto_scaling
  min_count             = each.value.enable_auto_scaling ? each.value.min_count : null
  max_count             = each.value.enable_auto_scaling ? each.value.max_count : null
  vnet_subnet_id        = azurerm_subnet.gpu_node_pool[each.key].id
  pod_subnet_id         = azurerm_subnet.gpu_node_pool_pod[each.key].id
  os_disk_size_gb       = 128
  os_disk_type          = "Ephemeral"
  priority              = each.value.priority
  eviction_policy       = each.value.priority == "Spot" ? each.value.eviction_policy : null
  spot_max_price        = each.value.priority == "Spot" ? -1 : null
  node_taints           = each.value.node_taints
  zones                 = each.value.zones
  gpu_instance          = each.value.gpu_driver
  tags                  = local.tags

  upgrade_settings {
    max_surge                     = "10%"
    drain_timeout_in_minutes      = 0
    node_soak_duration_in_minutes = 0
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.gpu_node_pool,
  ]
}

// ============================================================
// Data Collection Rule Associations
// ============================================================

// Associate Container Insights logs DCR with AKS
resource "azurerm_monitor_data_collection_rule_association" "logs" {
  name                    = "dcra-logs-${local.resource_name_suffix}"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.logs.id
}

// Associate Prometheus metrics DCR with AKS
resource "azurerm_monitor_data_collection_rule_association" "metrics" {
  name                    = "dcra-metrics-${local.resource_name_suffix}"
  target_resource_id      = azurerm_kubernetes_cluster.main.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.metrics.id
}

// ============================================================
// AKS Private Endpoint (for private clusters)
// ============================================================

resource "azurerm_private_endpoint" "aks" {
  count = var.aks_config.is_private_cluster && local.pe_enabled ? 1 : 0

  name                = "pe-aks-${local.resource_name_suffix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-aks-${local.resource_name_suffix}"
    private_connection_resource_id = azurerm_kubernetes_cluster.main.id
    subresource_names              = ["management"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdz-aks-${local.resource_name_suffix}"
    private_dns_zone_ids = [azurerm_private_dns_zone.core["aks"].id]
  }
}
