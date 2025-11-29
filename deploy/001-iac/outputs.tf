/*
 * Robotics Blueprint Outputs
 *
 * Platform module outputs: Shared infrastructure (networking, security, observability, etc.)
 * SiL module outputs: AKS cluster and ML extension resources
 */

// ============================================================
// Core Outputs
// ============================================================

output "resource_group" {
  description = "Resource group for robotics infrastructure."
  value       = local.resource_group
}

// ============================================================
// Platform Module Outputs - Networking
// ============================================================

output "virtual_network" {
  description = "Virtual network for robotics infrastructure."
  value       = module.platform.virtual_network
}

output "subnets" {
  description = "Subnet details from platform module."
  value       = module.platform.subnets
}

// ============================================================
// Platform Module Outputs - Security
// ============================================================

output "key_vault" {
  description = "Key Vault storing robotics secrets."
  value       = module.platform.key_vault
}

// ============================================================
// Platform Module Outputs - Compute Resources
// ============================================================

output "container_registry" {
  description = "Azure Container Registry for container images."
  value       = module.platform.container_registry
}

output "storage_account" {
  description = "Storage account for ML workspace and general storage."
  value       = module.platform.storage_account
}

// ============================================================
// Platform Module Outputs - ML Workspace
// ============================================================

output "azureml_workspace" {
  description = "Azure ML workspace for ML workloads."
  value       = module.platform.azureml_workspace
}

output "ml_workload_identity" {
  description = "ML workload identity for federated credentials."
  value       = module.platform.ml_workload_identity
}

// ============================================================
// Platform Module Outputs - Observability
// ============================================================

output "log_analytics_workspace" {
  description = "Log Analytics Workspace for centralized logging."
  value       = module.platform.log_analytics_workspace
}

output "application_insights" {
  description = "Application Insights for application telemetry."
  value       = module.platform.application_insights
  sensitive   = true
}

output "grafana" {
  description = "Azure Managed Grafana for dashboards."
  value       = module.platform.grafana
}

// ============================================================
// Platform Module Outputs - OSMO Services (Optional)
// ============================================================

output "postgresql" {
  description = "PostgreSQL Flexible Server object."
  value       = module.platform.postgresql
}

output "redis" {
  description = "Azure Redis Cache object."
  value       = module.platform.redis
}

// ============================================================
// SiL Module Outputs - AKS Cluster
// ============================================================

output "aks_cluster" {
  description = "AKS cluster for robotics workloads."
  value       = module.sil.aks_cluster
  sensitive   = true
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity."
  value       = module.sil.aks_oidc_issuer_url
}

output "gpu_node_pool_subnets" {
  description = "GPU node pool subnets created by SiL module."
  value       = module.sil.gpu_node_pool_subnets
}

// ============================================================
// SiL Module Outputs - ML Extension
// ============================================================

output "ml_extension" {
  description = "Azure ML Extension on AKS."
  value       = module.sil.ml_extension
}

output "kubernetes_compute" {
  description = "Kubernetes compute target registered in ML workspace."
  value       = module.sil.kubernetes_compute
}
