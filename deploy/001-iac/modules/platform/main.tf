/**
 * # Platform Module
 *
 * Deploys shared Azure infrastructure services for robotics ML workloads.
 * Resources include: networking, DNS zones, security, observability, ACR, storage, ML workspace.
 * Optional: PostgreSQL and Redis for OSMO workloads.
 */

// ============================================================
// Data Sources
// ============================================================

data "azurerm_client_config" "current" {}

// ============================================================
// Locals
// ============================================================

locals {
  resource_name_suffix = "${var.resource_prefix}-${var.environment}-${var.instance}"
  pe_enabled           = var.should_enable_private_endpoints

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

  tags = merge(var.tags, {
    module      = "platform"
    environment = var.environment
  })
}
