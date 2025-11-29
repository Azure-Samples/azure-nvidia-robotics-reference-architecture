/**
 * # Azure Machine Learning Extension Resources
 *
 * This file creates the AKS-dependent ML resources for the SiL module including:
 * - ML Extension on AKS cluster for training and inference
 * - Kubernetes compute target registered in ML workspace (via azapi)
 * - Federated identity credentials for workload identity
 *
 * Note: ML Workspace and identity are created in the platform module.
 */

// ============================================================
// ML Extension on AKS
// ============================================================

resource "azurerm_kubernetes_cluster_extension" "azureml" {
  count = var.azureml_config.should_integrate_aks ? 1 : 0

  name              = "azureml-${local.resource_name_suffix}"
  cluster_id        = azurerm_kubernetes_cluster.main.id
  extension_type    = "Microsoft.AzureML.Kubernetes"
  release_namespace = "azureml"
  release_train     = "stable"

  configuration_settings = {
    "enableTraining"               = "true"
    "enableInference"              = "true"
    "inferenceRouterServiceType"   = var.azureml_config.inference_router_service_type
    "internalLoadBalancerProvider" = "azure"
    "installNvidiaDevicePlugin"    = "false"
    "installDcgmExporter"          = "false"
    "installVolcano"               = "false"
    "installPromOp"                = "false"
    "allowInsecureConnections"     = "true"
    "inferenceRouterHA"            = "false"
    "cluster_name"                 = azurerm_kubernetes_cluster.main.name
    "cluster_name_friendly"        = azurerm_kubernetes_cluster.main.name
    "domain"                       = "${var.location}.cloudapp.azure.com"
    "location"                     = var.location
    "jobSchedulerLocation"         = var.location
    "clusterPurpose"               = var.azureml_config.aks_cluster_purpose
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

// ============================================================
// Kubernetes Compute Target (via azapi)
// ============================================================

resource "azapi_resource" "kubernetes_compute" {
  count = var.azureml_config.should_integrate_aks ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/computes@2024-10-01"
  name      = "aks-ml${var.resource_prefix}${var.environment}${var.instance}"
  parent_id = var.azureml_workspace.id

  body = {
    properties = {
      computeType = "Kubernetes"
      resourceId  = azurerm_kubernetes_cluster.main.id
      properties = {
        namespace            = "azureml"
        defaultInstanceType  = "defaultinstancetype"
        instanceTypes        = local.instance_types
        extensionPrincipalId = try(azurerm_kubernetes_cluster_extension.azureml[0].aks_assigned_identity[0].principal_id, null)
      }
    }
  }

  depends_on = [azurerm_kubernetes_cluster_extension.azureml]
}

locals {
  // Default instance types for ML compute target
  default_instance_types = {
    defaultinstancetype = {
      nodeSelector = {}
      resources = {
        limits   = { cpu = "2", memory = "8Gi", "nvidia.com/gpu" = null }
        requests = { cpu = "1", memory = "4Gi", "nvidia.com/gpu" = null }
      }
    }
    gpuinstancetype = {
      nodeSelector = {}
      resources = {
        limits   = { cpu = "4", memory = "16Gi", "nvidia.com/gpu" = "1" }
        requests = { cpu = "2", memory = "8Gi", "nvidia.com/gpu" = "1" }
      }
    }
  }

  // Merge with user-provided instance types
  instance_types = try(
    coalesce(var.azureml_config.cluster_integration_instance_types, local.default_instance_types),
    local.default_instance_types
  )
}

// ============================================================
// Federated Identity Credentials
// ============================================================

// Federated credential for default service account in azureml namespace
resource "azurerm_federated_identity_credential" "azureml_default" {
  count = var.azureml_config.should_integrate_aks ? 1 : 0

  name                = "aml-default-fic"
  resource_group_name = var.resource_group.name
  parent_id           = var.ml_workload_identity.id
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:azureml:default"
  audience            = ["api://AzureADTokenExchange"]
}

// Federated credential for training workloads
resource "azurerm_federated_identity_credential" "azureml_training" {
  count = var.azureml_config.should_integrate_aks ? 1 : 0

  name                = "aml-training-fic"
  resource_group_name = var.resource_group.name
  parent_id           = var.ml_workload_identity.id
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:azureml:training"
  audience            = ["api://AzureADTokenExchange"]
}
