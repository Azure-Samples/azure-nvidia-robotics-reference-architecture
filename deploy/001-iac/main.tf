/**
 * # Robotics Blueprint
 *
 * Deploys robotics infrastructure with NVIDIA GPU support, KAI Scheduler,
 * and optional Azure Machine Learning integration.
 *
 * Architecture:
 * - Platform Module: Shared services (networking, security, observability, ACR, storage, ML workspace)
 * - SiL Module: AKS cluster with GPU node pools and ML extension integration
 */

locals {
  resource_group_name = coalesce(var.resource_group_name, "rg-${var.resource_prefix}-${var.environment}-${var.instance}")
}

resource "azurerm_resource_group" "this" {
  count    = var.should_create_resource_group ? 1 : 0
  name     = local.resource_group_name
  location = var.location
}

// Defer resource group data source to support build systems without plan-time permissions
resource "terraform_data" "defer_resource_group" {
  count = var.should_create_resource_group ? 0 : 1
  input = {
    name = local.resource_group_name
  }
}

data "azurerm_resource_group" "existing" {
  count = var.should_create_resource_group ? 0 : 1
  name  = terraform_data.defer_resource_group[0].output.name
}

locals {
  // Resolve resource group to either created or existing
  resource_group = var.should_create_resource_group ? {
    id       = azurerm_resource_group.this[0].id
    name     = azurerm_resource_group.this[0].name
    location = azurerm_resource_group.this[0].location
    } : {
    id       = data.azurerm_resource_group.existing[0].id
    name     = data.azurerm_resource_group.existing[0].name
    location = data.azurerm_resource_group.existing[0].location
  }
}

// ============================================================
// Platform Module - Shared Services
// ============================================================

module "platform" {
  source = "./modules/platform"

  depends_on = [azurerm_resource_group.this]

  // Core variables
  environment     = var.environment
  resource_prefix = var.resource_prefix
  location        = var.location
  instance        = var.instance
  tags            = {}
  resource_group  = local.resource_group

  // Networking configuration
  virtual_network_config = {
    address_space              = var.virtual_network_config.address_space
    subnet_address_prefix_main = var.virtual_network_config.subnet_address_prefix
  }

  // Feature flags
  should_enable_private_endpoints         = var.should_enable_private_endpoints
  should_enable_public_network_access     = var.should_enable_public_network_access
  should_use_current_user_key_vault_admin = var.should_use_current_user_key_vault_admin

  // OSMO optional services
  should_deploy_postgresql = var.should_deploy_postgresql
  should_deploy_redis      = var.should_deploy_redis
  postgresql_config = {
    sku_name        = var.postgresql_sku_name
    storage_mb      = var.postgresql_storage_mb
    version         = var.postgresql_version
    subnet_prefixes = var.postgresql_subnet_address_prefixes
    databases       = var.postgresql_databases
  }
  redis_config = {
    sku_name          = var.redis_sku_name
    clustering_policy = var.redis_clustering_policy
  }
}

// ============================================================
// SiL Module - AKS + AzureML Extension
// ============================================================

module "sil" {
  source = "./modules/sil"

  depends_on = [module.platform]

  // Core variables
  environment     = var.environment
  resource_prefix = var.resource_prefix
  location        = var.location
  instance        = var.instance
  tags            = {}
  resource_group  = local.resource_group

  // Dependencies from platform module (passed as typed objects)
  virtual_network          = module.platform.virtual_network
  subnets                  = module.platform.subnets
  network_security_group   = module.platform.network_security_group
  nat_gateway              = module.platform.nat_gateway
  log_analytics_workspace  = module.platform.log_analytics_workspace
  monitor_workspace        = module.platform.monitor_workspace
  data_collection_endpoint = module.platform.data_collection_endpoint
  container_registry       = module.platform.container_registry
  azureml_workspace        = module.platform.azureml_workspace
  ml_workload_identity     = module.platform.ml_workload_identity
  private_dns_zones        = module.platform.private_dns_zones

  // AKS subnet configuration - uses module defaults when null
  aks_subnet_config = {
    subnet_address_prefix_aks     = try(var.subnet_address_prefixes_aks[0], null)
    subnet_address_prefix_aks_pod = try(var.subnet_address_prefixes_aks_pod[0], null)
  }

  // AKS configuration
  aks_config = {
    node_vm_size        = var.node_vm_size
    node_count          = var.node_count
    enable_auto_scaling = var.enable_auto_scaling
    min_count           = var.min_count
    max_count           = var.max_count
    is_private_cluster  = var.should_enable_private_endpoints
  }

  node_pools = var.node_pools

  // AzureML extension configuration
  azureml_config = {
    should_integrate_aks               = var.should_integrate_aks_cluster
    aks_cluster_purpose                = var.aks_cluster_purpose
    inference_router_service_type      = var.inference_router_service_type
    workload_tolerations               = var.workload_tolerations
    cluster_integration_instance_types = var.cluster_integration_instance_types
  }

  // Feature flags
  should_enable_private_endpoints = var.should_enable_private_endpoints
}
