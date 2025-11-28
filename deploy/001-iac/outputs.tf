/*
 * Robotics Blueprint Outputs
 */

output "aks_cluster" {
  description = "AKS cluster for robotics workloads."
  value       = module.sil.aks_cluster
  sensitive   = true
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity."
  value       = module.sil.aks_oidc_issuer_url
}

output "container_registry" {
  description = "Azure Container Registry for container images."
  value       = module.sil.container_registry
}

output "azureml_workspace" {
  description = "Azure ML workspace for ML workloads."
  value       = module.sil.azureml_workspace
}

output "resource_group" {
  description = "Resource group for robotics infrastructure."
  value       = local.resource_group
}

output "key_vault" {
  description = "Key Vault storing robotics secrets."
  value       = module.sil.key_vault
}

output "virtual_network" {
  description = "Virtual network for robotics infrastructure."
  value       = module.sil.virtual_network
}

output "storage_account" {
  description = "Storage account for ML workspace and general storage."
  value       = module.sil.storage_account
}

/*
 * Observability Outputs
 */

output "log_analytics_workspace" {
  description = "Log Analytics Workspace for centralized logging."
  value       = module.sil.log_analytics_workspace
  sensitive   = true
}

output "application_insights" {
  description = "Application Insights for application telemetry."
  value       = module.sil.application_insights
  sensitive   = true
}

output "grafana" {
  description = "Azure Managed Grafana for dashboards."
  value       = module.sil.grafana
}

/*
 * Azure Managed Redis Outputs
 */

output "redis" {
  description = "Azure Managed Redis cache object."
  value       = module.sil.redis
}

output "redis_connection_info" {
  description = "Azure Managed Redis connection information."
  sensitive   = true
  value       = module.sil.redis_connection_info
}

/*
 * PostgreSQL Outputs
 */

output "postgresql" {
  description = "PostgreSQL Flexible Server object."
  value       = module.sil.postgresql
}

output "postgresql_connection_info" {
  description = "PostgreSQL connection information."
  sensitive   = true
  value       = module.sil.postgresql_connection_info
}
