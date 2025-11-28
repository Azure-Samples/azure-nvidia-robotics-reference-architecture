/**
 * # Module Outputs
 *
 * This file exports all resources created by the SiL module.
 * Outputs are grouped by functionality and use try() for optional resources.
 */

// ============================================================
// Networking Outputs
// ============================================================

output "virtual_network" {
  description = "The Virtual Network resource."
  value = {
    id       = azurerm_virtual_network.main.id
    name     = azurerm_virtual_network.main.name
    location = azurerm_virtual_network.main.location
  }
}

output "subnets" {
  description = "All subnet resources created by the module."
  value = {
    main              = { id = azurerm_subnet.main.id, name = azurerm_subnet.main.name }
    private_endpoints = { id = azurerm_subnet.private_endpoints.id, name = azurerm_subnet.private_endpoints.name }
    aks               = { id = azurerm_subnet.aks.id, name = azurerm_subnet.aks.name }
    aks_pod           = { id = azurerm_subnet.aks_pod.id, name = azurerm_subnet.aks_pod.name }
  }
}

output "nat_gateway" {
  description = "The NAT Gateway resource."
  value = {
    id           = azurerm_nat_gateway.main.id
    name         = azurerm_nat_gateway.main.name
    public_ip_id = azurerm_public_ip.nat_gateway.id
  }
}

// ============================================================
// Security Outputs
// ============================================================

output "key_vault" {
  description = "The Key Vault resource."
  value = {
    id        = azurerm_key_vault.main.id
    name      = azurerm_key_vault.main.name
    vault_uri = azurerm_key_vault.main.vault_uri
  }
}

output "ml_workload_identity" {
  description = "The User Assigned Managed Identity for ML workloads."
  value = {
    id           = azurerm_user_assigned_identity.ml.id
    name         = azurerm_user_assigned_identity.ml.name
    principal_id = azurerm_user_assigned_identity.ml.principal_id
    client_id    = azurerm_user_assigned_identity.ml.client_id
    tenant_id    = azurerm_user_assigned_identity.ml.tenant_id
  }
}

// ============================================================
// Observability Outputs
// ============================================================

output "log_analytics_workspace" {
  description = "The Log Analytics Workspace resource."
  value = {
    id                 = azurerm_log_analytics_workspace.main.id
    name               = azurerm_log_analytics_workspace.main.name
    workspace_id       = azurerm_log_analytics_workspace.main.workspace_id
    primary_shared_key = azurerm_log_analytics_workspace.main.primary_shared_key
  }
  sensitive = true
}

output "application_insights" {
  description = "The Application Insights resource."
  value = {
    id                  = azurerm_application_insights.main.id
    name                = azurerm_application_insights.main.name
    instrumentation_key = azurerm_application_insights.main.instrumentation_key
    connection_string   = azurerm_application_insights.main.connection_string
  }
  sensitive = true
}

output "grafana" {
  description = "The Azure Managed Grafana resource."
  value = {
    id          = azurerm_dashboard_grafana.main.id
    name        = azurerm_dashboard_grafana.main.name
    endpoint    = azurerm_dashboard_grafana.main.endpoint
    grafana_url = "https://${azurerm_dashboard_grafana.main.endpoint}"
  }
}

output "monitor_workspace" {
  description = "The Azure Monitor Workspace for Prometheus metrics."
  value = {
    id   = azurerm_monitor_workspace.main.id
    name = azurerm_monitor_workspace.main.name
  }
}

// ============================================================
// Compute Outputs
// ============================================================

output "container_registry" {
  description = "The Azure Container Registry resource."
  value = {
    id           = azurerm_container_registry.main.id
    name         = azurerm_container_registry.main.name
    login_server = azurerm_container_registry.main.login_server
  }
}

output "storage_account" {
  description = "The Storage Account resource."
  value = {
    id                    = azurerm_storage_account.main.id
    name                  = azurerm_storage_account.main.name
    primary_blob_endpoint = azurerm_storage_account.main.primary_blob_endpoint
  }
}

output "aks_cluster" {
  description = "The AKS Cluster resource."
  value = {
    id                  = azurerm_kubernetes_cluster.main.id
    name                = azurerm_kubernetes_cluster.main.name
    fqdn                = azurerm_kubernetes_cluster.main.fqdn
    kube_config         = azurerm_kubernetes_cluster.main.kube_config_raw
    kubelet_identity    = azurerm_kubernetes_cluster.main.kubelet_identity[0]
    node_resource_group = azurerm_kubernetes_cluster.main.node_resource_group
  }
  sensitive = true
}

output "aks_oidc_issuer_url" {
  description = "The OIDC issuer URL for the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

// ============================================================
// Machine Learning Outputs
// ============================================================

output "azureml_workspace" {
  description = "The Azure Machine Learning Workspace resource."
  value = {
    id            = azurerm_machine_learning_workspace.main.id
    name          = azurerm_machine_learning_workspace.main.name
    discovery_url = azurerm_machine_learning_workspace.main.discovery_url
    workspace_id  = azurerm_machine_learning_workspace.main.workspace_id
  }
}

output "ml_extension" {
  description = "The Azure ML Extension on AKS."
  value = try({
    id                 = azurerm_kubernetes_cluster_extension.azureml[0].id
    name               = azurerm_kubernetes_cluster_extension.azureml[0].name
    release_namespace  = azurerm_kubernetes_cluster_extension.azureml[0].release_namespace
    extension_identity = azurerm_kubernetes_cluster_extension.azureml[0].aks_assigned_identity
  }, null)
}

output "kubernetes_compute" {
  description = "The Kubernetes Compute Target registered in ML workspace."
  value = try({
    id   = azapi_resource.kubernetes_compute[0].id
    name = azapi_resource.kubernetes_compute[0].name
  }, null)
}

// ============================================================
// OSMO Service Outputs
// ============================================================

output "postgresql" {
  description = "The PostgreSQL Flexible Server resource."
  value = try({
    id   = azurerm_postgresql_flexible_server.main[0].id
    name = azurerm_postgresql_flexible_server.main[0].name
    fqdn = azurerm_postgresql_flexible_server.main[0].fqdn
  }, null)
}

output "postgresql_connection_info" {
  description = "PostgreSQL connection information for applications."
  value = try({
    host     = azurerm_postgresql_flexible_server.main[0].fqdn
    port     = 5432
    username = "psqladmin"
    database = keys(var.postgresql_config.databases)[0]
  }, null)
  sensitive = true
}

output "redis" {
  description = "The Azure Managed Redis resource."
  value = try({
    id       = azurerm_redis_cache.main[0].id
    name     = azurerm_redis_cache.main[0].name
    hostname = azurerm_redis_cache.main[0].hostname
    port     = azurerm_redis_cache.main[0].ssl_port
  }, null)
}

output "redis_connection_info" {
  description = "Redis connection information for applications."
  value = try({
    hostname    = azurerm_redis_cache.main[0].hostname
    port        = azurerm_redis_cache.main[0].ssl_port
    primary_key = azurerm_redis_cache.main[0].primary_access_key
  }, null)
  sensitive = true
}

// ============================================================
// Private DNS Zone Outputs
// ============================================================

output "private_dns_zones" {
  description = "All private DNS zones created by the module."
  value = merge(
    { for k, v in azurerm_private_dns_zone.core : k => { id = v.id, name = v.name } },
    var.should_deploy_postgresql ? { postgresql = { id = azurerm_private_dns_zone.postgresql[0].id, name = azurerm_private_dns_zone.postgresql[0].name } } : {},
    var.should_deploy_redis && local.pe_enabled ? { redis = { id = azurerm_private_dns_zone.redis[0].id, name = azurerm_private_dns_zone.redis[0].name } } : {}
  )
}
