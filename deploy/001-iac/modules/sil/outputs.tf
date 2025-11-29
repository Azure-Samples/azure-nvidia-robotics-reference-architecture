/**
 * # SiL Module Outputs
 *
 * This file exports AKS and ML extension resources created by the SiL module.
 * Shared infrastructure outputs (networking, security, observability, etc.) are
 * provided by the platform module.
 */

// ============================================================
// AKS Networking Outputs
// ============================================================

output "aks_subnets" {
  description = "AKS subnets created by the module."
  value = {
    aks = {
      id   = azurerm_subnet.aks.id
      name = azurerm_subnet.aks.name
    }
    aks_pod = {
      id   = azurerm_subnet.aks_pod.id
      name = azurerm_subnet.aks_pod.name
    }
  }
}

// ============================================================
// AKS Cluster Outputs
// ============================================================

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

output "gpu_node_pool_subnets" {
  description = "GPU node pool subnets created by the module."
  value = {
    for key, subnet in azurerm_subnet.gpu_node_pool : key => {
      id   = subnet.id
      name = subnet.name
    }
  }
}

// ============================================================
// Machine Learning Extension Outputs
// ============================================================

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
