/*
 * Private Endpoint Variables
 */

variable "should_enable_private_endpoints" {
  type        = bool
  description = "Whether to enable private endpoints for AKS cluster"
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
 * AzureML Extension Variables
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
