/**
 * # Role Assignments
 *
 * This file consolidates all role assignments for the SiL module including:
 * - AKS kubelet identity AcrPull role for container registry access
 */

// ============================================================
// Container Registry Role Assignments
// ============================================================

// Grant AKS kubelet identity AcrPull role
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
