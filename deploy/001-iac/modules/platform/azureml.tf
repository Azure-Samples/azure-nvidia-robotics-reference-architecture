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
