/*
 * Robotics Blueprint Outputs
 */

output "aks_cluster" {
  description = "AKS cluster for robotics workloads"
  value       = module.robotics.aks_cluster
  sensitive   = true
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity"
  value       = module.robotics.aks_oidc_issuer_url
}

output "acr_network_posture" {
  description = "Container registry network posture"
  value       = module.robotics.acr_network_posture
}

output "azureml_workspace" {
  description = "Azure ML workspace when AzureML charts are enabled"
  value       = module.robotics.azureml_workspace
}

output "resource_group" {
  description = "Resource group for robotics infrastructure"
  value       = module.robotics.resource_group
}

output "key_vault_name" {
  description = "Name of the Key Vault storing robotics secrets"
  value       = try(module.robotics.key_vault.name, null)
}

output "virtual_network" {
  description = "Virtual network for robotics infrastructure"
  value       = module.robotics.virtual_network
}

output "storage_account" {
  description = "Storage account for robotics data services"
  value       = module.robotics.storage_account
}

/*
 * Azure Managed Redis Outputs
 */

output "managed_redis" {
  description = "Azure Managed Redis cache object."
  value       = module.robotics.managed_redis
}

output "managed_redis_connection_info" {
  description = "Azure Managed Redis connection information."
  sensitive   = true
  value       = module.robotics.managed_redis_connection_info
}

/*
 * PostgreSQL Outputs
 */

output "postgresql_connection_info" {
  description = "PostgreSQL connection information."
  sensitive   = true
  value       = module.robotics.postgresql_connection_info
}
