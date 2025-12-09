/**
 * # Azure Machine Learning Workspace
 *
 * This file creates the Azure ML Workspace for the Platform module including:
 * - Azure Machine Learning Workspace linked to Key Vault, Storage, ACR, App Insights
 * - Private endpoint for ML workspace
 *
 * Note: ML Extension, Kubernetes Compute, and FICs are in the SiL module (require AKS cluster)
 */

// ============================================================
// Azure Machine Learning Workspace (via azapi)
// ============================================================
// Using azapi_resource because azurerm does not expose systemDatastoresAuthMode.
// This property is required when storage account has shared_access_key_enabled = false.

resource "azapi_resource" "ml_workspace" {
  type      = "Microsoft.MachineLearningServices/workspaces@2024-04-01"
  name      = "mlw-${local.resource_name_suffix}"
  location  = var.resource_group.location
  parent_id = var.resource_group.id
  tags      = local.tags

  // Disable schema validation because azapi provider schema doesn't include
  // systemDatastoresAuthMode property, but it's valid per Microsoft ARM docs.
  schema_validation_enabled = false

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name = "Basic"
      tier = "Basic"
    }
    kind = "Default"
    properties = {
      friendlyName             = "mlw-${local.resource_name_suffix}"
      keyVault                 = azurerm_key_vault.main.id
      storageAccount           = azurerm_storage_account.main.id
      containerRegistry        = azurerm_container_registry.main.id
      applicationInsights      = azurerm_application_insights.main.id
      publicNetworkAccess      = var.should_enable_public_network_access ? "Enabled" : "Disabled"
      v1LegacyMode             = false
      systemDatastoresAuthMode = var.should_enable_storage_shared_access_key ? "accessKey" : "identity"
      managedNetwork = {
        isolationMode = var.should_enable_private_endpoint ? "AllowOnlyApprovedOutbound" : "Disabled"
      }
    }
  }

  response_export_values = ["properties.workspaceId", "identity.principalId"]
}

// ============================================================
// ML Workspace Private Endpoints
// ============================================================

resource "azurerm_private_endpoint" "azureml_api" {
  count = local.pe_enabled ? 1 : 0

  name                = "pe-ml-api-${local.resource_name_suffix}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-ml-api-${local.resource_name_suffix}"
    private_connection_resource_id = azapi_resource.ml_workspace.id
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
