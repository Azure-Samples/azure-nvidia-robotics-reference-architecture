/**
 * # Azure Machine Learning Resources
 *
 * This file creates the Azure ML infrastructure for the SiL module including:
 * - Azure Machine Learning Workspace linked to Key Vault, Storage, ACR, App Insights
 * - ML Extension on AKS cluster for training and inference
 * - Kubernetes compute target registered in ML workspace (via azapi)
 * - Federated identity credentials for workload identity
 * - Private endpoint for ML workspace
 */

// ============================================================
// Azure Machine Learning Workspace
// ============================================================

resource "azurerm_machine_learning_workspace" "main" {
  name                          = "mlw-${local.resource_name_suffix}"
  location                      = var.resource_group.location
  resource_group_name           = var.resource_group.name
  key_vault_id                  = azurerm_key_vault.main.id
  storage_account_id            = azurerm_storage_account.main.id
  container_registry_id         = azurerm_container_registry.main.id
  application_insights_id       = azurerm_application_insights.main.id
  public_network_access_enabled = var.should_enable_public_network_access
  image_build_compute_name      = null
  sku_name                      = "Basic"
  v1_legacy_mode_enabled        = false
  tags                          = local.tags

  managed_network {
    isolation_mode = var.should_enable_private_endpoints ? "AllowOnlyApprovedOutbound" : "Disabled"
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.ml.id]
  }

  primary_user_assigned_identity = azurerm_user_assigned_identity.ml.id

  depends_on = [
    azurerm_role_assignment.ml_kv_user,
    azurerm_role_assignment.ml_storage_blob,
    azurerm_role_assignment.ml_storage_file,
    azurerm_role_assignment.ml_acr_push,
  ]
}

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
  parent_id = azurerm_machine_learning_workspace.main.id

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
  parent_id           = azurerm_user_assigned_identity.ml.id
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:azureml:default"
  audience            = ["api://AzureADTokenExchange"]
}

// Federated credential for training workloads
resource "azurerm_federated_identity_credential" "azureml_training" {
  count = var.azureml_config.should_integrate_aks ? 1 : 0

  name                = "aml-training-fic"
  resource_group_name = var.resource_group.name
  parent_id           = azurerm_user_assigned_identity.ml.id
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:azureml:training"
  audience            = ["api://AzureADTokenExchange"]
}

// ============================================================
// ML Workspace Private Endpoints
// ============================================================

resource "azurerm_private_endpoint" "azureml_api" {
  count = local.pe_enabled ? 1 : 0

  name                = "pe-ml-api-${local.resource_name_suffix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-ml-api-${local.resource_name_suffix}"
    private_connection_resource_id = azurerm_machine_learning_workspace.main.id
    subresource_names              = ["amlworkspace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "pdz-ml-${local.resource_name_suffix}"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.core["azureml_api"].id,
      azurerm_private_dns_zone.core["azureml_notebooks"].id,
    ]
  }
}
