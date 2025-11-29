/**
 * # Platform Module Outputs
 *
 * Typed object outputs for consumption by the SiL module.
 * All outputs are structured as objects with selected fields for type safety.
 */

/*
 * Networking Outputs
 */

output "virtual_network" {
  description = "Virtual network for SiL AKS cluster"
  value = {
    id   = azurerm_virtual_network.main.id
    name = azurerm_virtual_network.main.name
  }
}

output "subnets" {
  description = "Subnets for SiL resources. Private endpoints subnet is null when private endpoints are disabled"
  value = {
    main = {
      id   = azurerm_subnet.main.id
      name = azurerm_subnet.main.name
    }
    private_endpoints = try({
      id   = azurerm_subnet.private_endpoints[0].id
      name = azurerm_subnet.private_endpoints[0].name
    }, null)
  }
}

output "network_security_group" {
  description = "NSG for SiL subnets"
  value = {
    id = azurerm_network_security_group.main.id
  }
}

output "nat_gateway" {
  description = "NAT Gateway for outbound connectivity"
  value = {
    id = azurerm_nat_gateway.main.id
  }
}

/*
 * Observability Outputs
 */

output "log_analytics_workspace" {
  description = "Log Analytics workspace for AKS monitoring"
  value = {
    id           = azurerm_log_analytics_workspace.main.id
    workspace_id = azurerm_log_analytics_workspace.main.workspace_id
  }
}

output "monitor_workspace" {
  description = "Azure Monitor workspace for Prometheus metrics"
  value = {
    id = azurerm_monitor_workspace.main.id
  }
}

output "data_collection_endpoint" {
  description = "Data Collection Endpoint for observability"
  value = {
    id = azurerm_monitor_data_collection_endpoint.main.id
  }
}

output "application_insights" {
  description = "Application Insights for telemetry"
  value = {
    id                  = azurerm_application_insights.main.id
    connection_string   = azurerm_application_insights.main.connection_string
    instrumentation_key = azurerm_application_insights.main.instrumentation_key
  }
  sensitive = true
}

output "grafana" {
  description = "Azure Managed Grafana dashboard"
  value = {
    id       = azurerm_dashboard_grafana.main.id
    endpoint = azurerm_dashboard_grafana.main.endpoint
  }
}

/*
 * Security Outputs
 */

output "key_vault" {
  description = "Key Vault for secrets management"
  value = {
    id        = azurerm_key_vault.main.id
    name      = azurerm_key_vault.main.name
    vault_uri = azurerm_key_vault.main.vault_uri
  }
}

/*
 * ACR Output
 */

output "container_registry" {
  description = "Container registry for SiL workloads"
  value = {
    id           = azurerm_container_registry.main.id
    name         = azurerm_container_registry.main.name
    login_server = azurerm_container_registry.main.login_server
  }
}

/*
 * Storage Output
 */

output "storage_account" {
  description = "Storage account for ML workspace"
  value = {
    id   = azurerm_storage_account.main.id
    name = azurerm_storage_account.main.name
  }
}

output "storage_account_access" {
  description = "Storage account access credentials. Only populated when shared_access_key_enabled is true"
  value = {
    primary_blob_endpoint = azurerm_storage_account.main.primary_blob_endpoint
    primary_access_key    = azurerm_storage_account.main.primary_access_key
  }
  sensitive = true
}

/*
 * AzureML Outputs
 */

output "azureml_workspace" {
  description = "ML workspace for AKS extension"
  value = {
    id           = azurerm_machine_learning_workspace.main.id
    name         = azurerm_machine_learning_workspace.main.name
    workspace_id = azurerm_machine_learning_workspace.main.workspace_id
  }
}

output "ml_workload_identity" {
  description = "ML workload identity for FICs"
  value = {
    id           = azurerm_user_assigned_identity.ml.id
    principal_id = azurerm_user_assigned_identity.ml.principal_id
    client_id    = azurerm_user_assigned_identity.ml.client_id
    tenant_id    = azurerm_user_assigned_identity.ml.tenant_id
  }
}

/*
 * DNS Zones Output
 */

output "private_dns_zones" {
  description = "Private DNS zones for private endpoints"
  value = try({
    for key, zone in azurerm_private_dns_zone.core : key => {
      id   = zone.id
      name = zone.name
    }
  }, {})
}

/*
 * OSMO Outputs (Optional)
 */

output "postgresql" {
  description = "PostgreSQL Flexible Server for OSMO (if deployed)"
  value = try({
    id   = azurerm_postgresql_flexible_server.main[0].id
    fqdn = azurerm_postgresql_flexible_server.main[0].fqdn
    name = azurerm_postgresql_flexible_server.main[0].name
  }, null)
}

output "redis" {
  description = "Azure Redis Cache for OSMO (if deployed)"
  value = try({
    id       = azurerm_redis_cache.main[0].id
    hostname = azurerm_redis_cache.main[0].hostname
    name     = azurerm_redis_cache.main[0].name
  }, null)
}
