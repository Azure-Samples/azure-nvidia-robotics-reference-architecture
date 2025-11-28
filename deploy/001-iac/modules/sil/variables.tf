/*
 * Core Variables - Required
 */

variable "environment" {
  type        = string
  description = "Environment for all resources in this module: dev, test, or prod"
}

variable "instance" {
  type        = string
  description = "Instance identifier for naming resources: 001, 002, etc"
  default     = "001"
}

variable "location" {
  type        = string
  description = "Location for all resources in this module"
}

variable "resource_group" {
  type = object({
    id       = string
    name     = string
    location = string
  })
  description = "Resource group object containing name, id, and location"
}

variable "resource_prefix" {
  type        = string
  description = "Prefix for all resources in this module"
}

/*
 * Networking Variables
 */

variable "virtual_network_config" {
  type = object({
    address_space                 = string
    subnet_address_prefix_main    = string
    subnet_address_prefix_pe      = string
    subnet_address_prefix_aks     = string
    subnet_address_prefix_aks_pod = string
  })
  description = "Virtual network address configuration including address space and subnet prefixes"
  default = {
    address_space                 = "10.0.0.0/16"
    subnet_address_prefix_main    = "10.0.1.0/24"
    subnet_address_prefix_pe      = "10.0.2.0/24"
    subnet_address_prefix_aks     = "10.0.5.0/23"
    subnet_address_prefix_aks_pod = "10.0.8.0/22"
  }
}

/*
 * Private Endpoint Variables
 */

variable "should_enable_private_endpoints" {
  type        = bool
  description = "Whether to enable private endpoints for all services"
  default     = true
}

variable "should_enable_public_network_access" {
  type        = bool
  description = "Whether to allow public network access (set to true for dev/test)"
  default     = false
}

/*
 * Security Variables
 */

variable "should_use_current_user_key_vault_admin" {
  type        = bool
  description = "Whether to grant current user Key Vault Secrets Officer role"
  default     = true
}

/*
 * AKS Cluster Variables
 */

variable "aks_config" {
  type = object({
    node_vm_size        = string
    node_count          = number
    enable_auto_scaling = bool
    min_count           = optional(number)
    max_count           = optional(number)
    is_private_cluster  = bool
  })
  description = "AKS cluster configuration for the system node pool"
  default = {
    node_vm_size        = "Standard_D8ds_v5"
    node_count          = 2
    enable_auto_scaling = false
    min_count           = null
    max_count           = null
    is_private_cluster  = true
  }
}

variable "node_pools" {
  type = map(object({
    vm_size                     = string
    node_count                  = optional(number, null)
    subnet_address_prefixes     = list(string)
    pod_subnet_address_prefixes = list(string)
    node_taints                 = optional(list(string), [])
    gpu_driver                  = optional(string)
    priority                    = optional(string, "Regular")
    enable_auto_scaling         = optional(bool, false)
    min_count                   = optional(number, null)
    max_count                   = optional(number, null)
    zones                       = optional(list(string), null)
    eviction_policy             = optional(string, "Deallocate")
  }))
  description = "Additional AKS node pools configuration. Map key is used as the node pool name"
  default = {
    gpu = {
      vm_size                     = "Standard_NV36ads_A10_v5"
      node_count                  = null
      subnet_address_prefixes     = ["10.0.16.0/24"]
      pod_subnet_address_prefixes = ["10.0.20.0/22"]
      node_taints                 = ["nvidia.com/gpu:NoSchedule", "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
      gpu_driver                  = "Install"
      priority                    = "Spot"
      enable_auto_scaling         = true
      min_count                   = 0
      max_count                   = 3
      zones                       = []
      eviction_policy             = "Delete"
    }
  }
}

/*
 * AzureML Variables
 */

variable "azureml_config" {
  type = object({
    should_integrate_aks          = bool
    aks_cluster_purpose           = string
    inference_router_service_type = string
    workload_tolerations = list(object({
      key      = string
      operator = string
      value    = optional(string)
      effect   = string
    }))
    cluster_integration_instance_types = optional(map(object({
      nodeSelector = optional(map(string))
      resources = object({
        limits   = object({ cpu = string, memory = string, gpu = optional(string) })
        requests = object({ cpu = string, memory = string, gpu = optional(string) })
      })
    })))
  })
  description = "Azure Machine Learning configuration including AKS integration settings"
  default = {
    should_integrate_aks          = true
    aks_cluster_purpose           = "DevTest"
    inference_router_service_type = "NodePort"
    workload_tolerations = [
      { key = "nvidia.com/gpu", operator = "Exists", value = null, effect = "NoSchedule" },
      { key = "kubernetes.azure.com/scalesetpriority", operator = "Equal", value = "spot", effect = "NoSchedule" }
    ]
    cluster_integration_instance_types = null
  }
}

/*
 * OSMO Variables - PostgreSQL
 */

variable "should_deploy_postgresql" {
  type        = bool
  description = "Whether to deploy PostgreSQL for OSMO backend"
  default     = false
}

variable "postgresql_config" {
  type = object({
    sku_name        = string
    storage_mb      = number
    version         = string
    subnet_prefixes = list(string)
    databases       = map(object({ collation = string, charset = string }))
  })
  description = "PostgreSQL configuration for OSMO including SKU, storage, and database definitions"
  default = {
    sku_name        = "GP_Standard_D2s_v3"
    storage_mb      = 32768
    version         = "16"
    subnet_prefixes = ["10.0.30.0/24"]
    databases       = { osmo = { collation = "en_US.utf8", charset = "utf8" } }
  }
}

/*
 * OSMO Variables - Redis
 */

variable "should_deploy_redis" {
  type        = bool
  description = "Whether to deploy Azure Managed Redis for OSMO"
  default     = false
}

variable "redis_config" {
  type = object({
    sku_name          = string
    clustering_policy = string
  })
  description = "Redis configuration for OSMO including SKU and clustering policy"
  default = {
    sku_name          = "Balanced_B10"
    clustering_policy = "OSSCluster"
  }
}

/*
 * Tags Variable
 */

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}
