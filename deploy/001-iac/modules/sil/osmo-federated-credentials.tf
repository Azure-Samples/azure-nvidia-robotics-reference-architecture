/**
 * # OSMO Federated Identity Credentials
 *
 * Links Kubernetes ServiceAccounts to the OSMO managed identity,
 * enabling workload identity authentication for Azure Blob Storage.
 *
 * ServiceAccounts federated:
 * - osmo-service (control plane namespace)
 * - osmo-router (control plane namespace)
 * - osmo-backend-listener (operator namespace)
 * - osmo-backend-worker (operator namespace)
 */

// ============================================================
// OSMO Federated Identity Credentials
// ============================================================

locals {
  // Build map of ServiceAccounts requiring federated credentials
  osmo_federated_credentials = var.osmo_workload_identity != null && var.osmo_config.should_federate_identity ? {
    // Control plane namespace ServiceAccounts
    "osmo-service" = {
      namespace = var.osmo_config.control_plane_namespace
      sa_name   = "osmo-service"
    }
    "osmo-router" = {
      namespace = var.osmo_config.control_plane_namespace
      sa_name   = "osmo-router"
    }
    // Operator namespace ServiceAccounts
    "osmo-backend-listener" = {
      namespace = var.osmo_config.operator_namespace
      sa_name   = "osmo-backend-listener"
    }
    "osmo-backend-worker" = {
      namespace = var.osmo_config.operator_namespace
      sa_name   = "osmo-backend-worker"
    }
  } : {}
}

resource "azurerm_federated_identity_credential" "osmo" {
  for_each = local.osmo_federated_credentials

  name                = "osmo-${each.key}-fic"
  resource_group_name = var.resource_group.name
  parent_id           = var.osmo_workload_identity.id
  issuer              = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject             = "system:serviceaccount:${each.value.namespace}:${each.value.sa_name}"
  audience            = ["api://AzureADTokenExchange"]
}
