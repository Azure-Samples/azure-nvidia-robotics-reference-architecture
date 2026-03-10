/**
 * # Dataviewer Module
 *
 * Deploys the dataviewer application on Azure Container Apps including:
 * - Container Apps Environment with optional VNet integration
 * - Backend (FastAPI) and Frontend (nginx + React) container apps
 * - User-assigned managed identity for ACR and Storage access
 * - Optional Entra ID app registration for public access mode
 *
 * Supports internal (VNet/VPN) and external (public) deployment modes.
 */

// ============================================================
// Locals
// ============================================================

locals {
  resource_name_suffix = "${var.resource_prefix}-${var.environment}-${var.instance}"
}

// ============================================================
// Container Apps Environment
// ============================================================

resource "azurerm_container_app_environment" "main" {
  name                           = "cae-${local.resource_name_suffix}"
  location                       = var.resource_group.location
  resource_group_name            = var.resource_group.name
  infrastructure_subnet_id       = azurerm_subnet.container_apps.id
  internal_load_balancer_enabled = var.should_enable_internal
  logs_destination               = "log-analytics"
  log_analytics_workspace_id     = var.log_analytics_workspace.id

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}
