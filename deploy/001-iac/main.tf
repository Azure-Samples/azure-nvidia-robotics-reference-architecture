/**
 * # Robotics Blueprint
 *
 * Deploys robotics infrastructure with NVIDIA GPU support, KAI Scheduler,
 * and optional Azure Machine Learning integration.
 */

resource "azurerm_resource_group" "this" {
  count    = var.should_create_resource_group ? 1 : 0
  name     = coalesce(var.resource_group_name, "rg-${var.resource_prefix}-${var.environment}-${var.instance}")
  location = var.location
}

module "robotics" {
  source = "git::https://ai-at-the-edge-flagship-accelerator@dev.azure.com/ai-at-the-edge-flagship-accelerator/edge-ai/_git/edge-ai//blueprints/modules/robotics/terraform?ref=c43d1f622c869a8e5a2723b3df41e227c7430f5f"

  depends_on = [azurerm_resource_group.this]

  /**
   * Core Variables
   */

  environment     = var.environment
  location        = var.location
  resource_prefix = var.resource_prefix
  instance        = var.instance

  /**
   * Control Plane
   */

  should_create_networking        = true
  should_create_acr               = true
  should_create_aks_cluster       = true
  should_create_security_identity = true
  should_create_observability     = true
  should_create_storage           = true

  // Resource Group configuration
  resource_group_name = var.resource_group_name

  // Key Vault configuration
  should_use_current_user_key_vault_admin = var.should_use_current_user_key_vault_admin

  // PostgreSQL configuration
  should_deploy_postgresql                         = var.should_deploy_postgresql
  postgresql_sku_name                              = var.postgresql_sku_name
  postgresql_storage_mb                            = var.postgresql_storage_mb
  postgresql_version                               = var.postgresql_version
  postgresql_subnet_address_prefixes               = var.postgresql_subnet_address_prefixes
  postgresql_databases                             = var.postgresql_databases
  postgresql_delegated_subnet_id                   = var.postgresql_delegated_subnet_id
  postgresql_should_generate_admin_password        = true
  postgresql_should_store_credentials_in_key_vault = true
  postgresql_should_enable_extensions              = true
  postgresql_should_enable_geo_redundant_backup    = false

  // Azure Managed Redis configuration
  should_deploy_redis                      = var.should_deploy_redis
  redis_sku_name                           = var.redis_sku_name
  redis_clustering_policy                  = var.redis_clustering_policy
  redis_access_keys_authentication_enabled = var.redis_access_keys_authentication_enabled
  redis_should_enable_high_availability    = false

  // Network configuration
  should_enable_private_endpoints     = var.should_enable_private_endpoints
  should_enable_public_network_access = var.should_enable_public_network_access
  should_enable_vpn_gateway           = var.should_enable_vpn_gateway
  virtual_network_name                = var.virtual_network_name
  virtual_network_config              = var.virtual_network_config
  vpn_site_connections                = var.vpn_site_connections
  vpn_site_default_ipsec_policy       = var.vpn_site_default_ipsec_policy
  vpn_site_shared_keys                = var.vpn_site_shared_keys

  /**
   * Software-in-the-Loop (SiL) (Re-using cluster for Control Plane)
   */

  // Azure Kubernetes Service configuration
  aks_cluster_name                = var.aks_cluster_name
  subnet_address_prefixes_aks     = var.subnet_address_prefixes_aks
  subnet_address_prefixes_aks_pod = var.subnet_address_prefixes_aks_pod
  enable_auto_scaling             = var.enable_auto_scaling
  node_vm_size                    = var.node_vm_size
  node_count                      = var.node_count
  min_count                       = var.min_count
  max_count                       = var.max_count
  node_pools                      = var.node_pools
  should_install_robotics_charts  = var.should_install_robotics_charts
  should_install_azureml_charts   = var.should_install_azureml_charts

  // AzureML configuration
  should_integrate_aks_cluster          = var.should_integrate_aks_cluster
  should_create_ml_workload_identity    = true
  should_create_compute_cluster         = false
  should_install_nvidia_device_plugin   = false
  should_install_dcgm_exporter          = false
  should_install_volcano                = false
  azureml_workspace_name                = var.azureml_workspace_name
  aks_cluster_purpose                   = var.aks_cluster_purpose
  inference_router_service_type         = var.inference_router_service_type
  should_enable_managed_outbound_access = var.should_enable_managed_outbound_access

  // Workload scheduling configuration
  workload_tolerations               = var.workload_tolerations
  cluster_integration_instance_types = var.cluster_integration_instance_types

  // VM host configuration
  should_create_vm_host               = var.should_create_vm_host
  vm_host_count                       = var.vm_host_count
  vm_sku_size                         = var.vm_sku_size
  vm_priority                         = var.vm_priority
  vm_eviction_policy                  = var.vm_eviction_policy
  vm_max_bid_price                    = var.vm_max_bid_price
  should_assign_current_user_vm_admin = var.should_assign_current_user_vm_admin
  should_use_vm_password_auth         = var.should_use_vm_password_auth
  should_create_vm_ssh_key            = var.should_create_vm_ssh_key

  /**
   * Hardware-in-the-Loop (HiL)
   */

  // AzureML configuration - Edge
  should_deploy_edge_extension = var.should_deploy_edge_extension
}
