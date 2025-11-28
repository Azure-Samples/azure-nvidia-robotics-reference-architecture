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

  tags = merge(var.tags, {
    module      = "platform"
    environment = var.environment
  })
}
