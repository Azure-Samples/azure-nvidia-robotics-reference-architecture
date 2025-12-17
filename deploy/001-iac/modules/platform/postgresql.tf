/**
 * # PostgreSQL Resources (Optional OSMO Service)
 *
 * This file creates the optional PostgreSQL Flexible Server for OSMO including:
 * - Delegated subnet for VNet integration (NOT private endpoint)
 * - PostgreSQL Flexible Server with TimescaleDB extension
 * - Database definitions per configuration
 * - Password stored securely in Key Vault
 *
 * Note: PostgreSQL uses VNet integration via delegated subnet, not private endpoints.
 */

// ============================================================
// PostgreSQL Delegated Subnet
// ============================================================

resource "azurerm_subnet" "postgresql" {
  count = var.should_deploy_postgresql ? 1 : 0

  name                            = "snet-psql-${local.resource_name_suffix}"
  resource_group_name             = var.resource_group.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = var.postgresql_config.subnet_prefixes
  service_endpoints               = ["Microsoft.Storage"]
  default_outbound_access_enabled = !var.should_enable_nat_gateway

  delegation {
    name = "postgresql-delegation"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

// ============================================================
// PostgreSQL Private DNS Zone Link
// ============================================================

// Note: DNS zone is created in private-dns-zones.tf

// ============================================================
// PostgreSQL Admin Password
// ============================================================

resource "random_password" "postgresql" {
  count = var.should_deploy_postgresql ? 1 : 0

  length           = 32
  special          = true
  override_special = "!@#$%&*()-_=+[]{}|;:,.<>?"
  min_lower        = 4
  min_upper        = 4
  min_numeric      = 4
  min_special      = 2
}

resource "azurerm_key_vault_secret" "postgresql_password" {
  count = var.should_deploy_postgresql ? 1 : 0

  name         = "psql-admin-password"
  value        = random_password.postgresql[0].result
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.tags

  depends_on = [azurerm_role_assignment.user_kv_officer]
}

// ============================================================
// PostgreSQL Flexible Server
// ============================================================

resource "azurerm_postgresql_flexible_server" "main" {
  count = var.should_deploy_postgresql ? 1 : 0

  name                          = "psql-${local.resource_name_suffix}"
  location                      = var.resource_group.location
  resource_group_name           = var.resource_group.name
  version                       = var.postgresql_config.version
  sku_name                      = var.postgresql_config.sku_name
  storage_mb                    = var.postgresql_config.storage_mb
  delegated_subnet_id           = azurerm_subnet.postgresql[0].id
  private_dns_zone_id           = azurerm_private_dns_zone.postgresql[0].id
  administrator_login           = "psqladmin"
  administrator_password        = random_password.postgresql[0].result
  zone                          = "1"
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = false
  tags                          = local.tags

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

// ============================================================
// PostgreSQL Configuration - Required Extensions
// ============================================================

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  count = var.should_deploy_postgresql ? 1 : 0

  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.main[0].id
  value     = "HSTORE,UUID-OSSP,PG_STAT_STATEMENTS"
}

// ============================================================
// PostgreSQL Databases
// ============================================================

resource "azurerm_postgresql_flexible_server_database" "databases" {
  for_each = var.should_deploy_postgresql ? var.postgresql_config.databases : {}

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.main[0].id
  collation = each.value.collation
  charset   = each.value.charset
}
