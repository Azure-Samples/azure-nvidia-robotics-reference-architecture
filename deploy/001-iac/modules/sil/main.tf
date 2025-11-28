/**
 * # SiL Module (Software-in-the-Loop)
 *
 * This module deploys cloud infrastructure for robotics ML workloads including:
 * - Networking with VNet, subnets, NSG, and NAT Gateway
 * - Centralized private DNS zone management for all services
 * - Security with Key Vault and workload identities
 * - Observability with Log Analytics, App Insights, Grafana, and AMPLS
 * - Container Registry with private endpoint
 * - Storage Account with private endpoints
 * - AKS Cluster with GPU node pools
 * - Azure Machine Learning with AKS integration
 * - Optional PostgreSQL and Redis for OSMO services
 */

locals {
  // Naming convention components
  resource_name_suffix = "${var.resource_prefix}-${var.environment}-${var.instance}"

  // Private endpoint configuration
  pe_enabled = var.should_enable_private_endpoints

  // Core DNS zones required for all services (11 zones)
  // Note: storage_blob is SHARED between Storage Account and AMPLS
  core_dns_zones = {
    key_vault         = "privatelink.vaultcore.azure.net"
    storage_blob      = "privatelink.blob.core.windows.net"
    storage_file      = "privatelink.file.core.windows.net"
    acr               = "privatelink.azurecr.io"
    azureml_api       = "privatelink.api.azureml.ms"
    azureml_notebooks = "privatelink.notebooks.azure.net"
    aks               = "privatelink.${var.location}.azmk8s.io"
    monitor           = "privatelink.monitor.azure.com"
    monitor_oms       = "privatelink.oms.opinsights.azure.com"
    monitor_ods       = "privatelink.ods.opinsights.azure.com"
    monitor_agent     = "privatelink.agentsvc.azure-automation.net"
  }

  // OSMO DNS zones (conditional based on deployment flags)
  osmo_dns_zones = merge(
    var.should_deploy_postgresql ? { postgresql = "privatelink.postgres.database.azure.com" } : {},
    var.should_deploy_redis && local.pe_enabled ? { redis = "privatelink.redis.cache.windows.net" } : {}
  )

  // Combined resource tags
  tags = merge(var.tags, {
    module      = "sil"
    environment = var.environment
  })
}

// Get current client configuration for role assignments
data "azurerm_client_config" "current" {}
