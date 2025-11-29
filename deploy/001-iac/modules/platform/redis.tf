/**
 * # Redis Resources (Optional OSMO Service)
 *
 * This file creates the optional Azure Managed Redis for OSMO including:
 * - Azure Managed Redis with configurable SKU
 * - Private endpoint for secure access (when PE enabled)
 */

// ============================================================
// Azure Managed Redis
// ============================================================

resource "azurerm_redis_cache" "main" {
  count = var.should_deploy_redis ? 1 : 0

  name                          = "redis-${local.resource_name_suffix}"
  location                      = var.resource_group.location
  resource_group_name           = var.resource_group.name
  capacity                      = 1
  family                        = "P"
  sku_name                      = "Premium"
  non_ssl_port_enabled          = false
  minimum_tls_version           = "1.2"
  public_network_access_enabled = var.should_enable_public_network_access
  tags                          = local.tags

  redis_configuration {
    maxmemory_policy = "volatile-lru"
  }
}

// ============================================================
// Redis Access Key in Key Vault
// ============================================================

resource "azurerm_key_vault_secret" "redis_primary_key" {
  count = var.should_deploy_redis ? 1 : 0

  name         = "redis-primary-key"
  value        = azurerm_redis_cache.main[0].primary_access_key
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.tags

  depends_on = [azurerm_role_assignment.user_kv_officer]
}

// ============================================================
// Redis Private Endpoint
// ============================================================

resource "azurerm_private_endpoint" "redis" {
  count = var.should_deploy_redis && local.pe_enabled ? 1 : 0

  name                = "pe-redis-${local.resource_name_suffix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-redis-${local.resource_name_suffix}"
    private_connection_resource_id = azurerm_redis_cache.main[0].id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdz-redis-${local.resource_name_suffix}"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis[0].id]
  }
}
