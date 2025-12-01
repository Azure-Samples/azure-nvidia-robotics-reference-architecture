/*
 * Private Endpoint Variables
 */

variable "should_enable_private_endpoints" {
  type        = bool
  description = "Whether to enable private endpoints for AKS cluster"
  default     = true
}

/*
 * AKS Networking Variables
 */

variable "aks_subnet_config" {
  type = object({
    subnet_address_prefix_aks = optional(string, "10.0.5.0/24")
  })
  description = "AKS subnet address configuration for system node pool. When properties are null, defaults are used. Note: Pod subnets are not used with Azure CNI Overlay mode"
  default     = {}
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
    vm_size                 = string
    node_count              = optional(number, null)
    subnet_address_prefixes = list(string)
    node_taints             = optional(list(string), [])
    gpu_driver              = optional(string)
    priority                = optional(string, "Regular")
    enable_auto_scaling     = optional(bool, false)
    min_count               = optional(number, null)
    max_count               = optional(number, null)
    zones                   = optional(list(string), null)
    eviction_policy         = optional(string, "Deallocate")
  }))
  description = "Additional AKS node pools configuration. Map key is used as the node pool name. Note: Pod subnets are not used with Azure CNI Overlay mode"
  default = {
    gpu = {
      vm_size                 = "Standard_NV36ads_A10_v5"
      node_count              = null
      subnet_address_prefixes = ["10.0.16.0/24"]
      node_taints             = ["nvidia.com/gpu:NoSchedule", "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
      gpu_driver              = "Install"
      priority                = "Spot"
      enable_auto_scaling     = true
      min_count               = 0
      max_count               = 1
      zones                   = []
      eviction_policy         = "Delete"
    }
  }
}

/*
 * AzureML Extension Variables
 */

variable "azureml_config" {
  type = object({
    // Core integration toggles
    should_integrate_aks        = bool
    should_install_extension    = optional(bool, false)
    should_federate_ml_identity = optional(bool, true)

    // Training and inference settings
    enable_training               = optional(bool, true)
    enable_inference              = optional(bool, true)
    inference_router_service_type = optional(string, "LoadBalancer")
    inference_router_ha           = optional(bool, false)
    allow_insecure_connections    = optional(bool, true)
    cluster_purpose               = optional(string, "DevTest")

    // Component installation toggles
    // Set to true: Extension installs and manages the component
    // Set to false: Use existing component already installed on cluster
    install_nvidia_device_plugin = optional(bool, false)
    install_dcgm_exporter        = optional(bool, false)
    install_volcano              = optional(bool, true)
    install_prom_op              = optional(bool, true)

    // Workload scheduling tolerations
    workload_tolerations = optional(list(object({
      key      = optional(string)
      operator = string
      value    = optional(string)
      effect   = optional(string)
      })), [
      { key = "nvidia.com/gpu", operator = "Exists", value = null, effect = "NoSchedule" },
      { key = "kubernetes.azure.com/scalesetpriority", operator = "Equal", value = "spot", effect = "NoSchedule" }
    ])

    // Instance types for compute target
    cluster_integration_instance_types = optional(map(object({
      nodeSelector = optional(map(string))
      resources = object({
        limits   = object({ cpu = string, memory = string, gpu = optional(string) })
        requests = object({ cpu = string, memory = string, gpu = optional(string) })
      })
    })))
  })
  description = "Azure Machine Learning AKS extension configuration including training, inference, and component settings"
  default = {
    should_integrate_aks          = true
    should_install_extension      = true
    should_federate_ml_identity   = true
    enable_training               = true
    enable_inference              = true
    inference_router_service_type = "LoadBalancer"
    inference_router_ha           = false
    allow_insecure_connections    = true
    cluster_purpose               = "DevTest"
    install_nvidia_device_plugin  = false
    install_dcgm_exporter         = false
    install_volcano               = true
    install_prom_op               = true
    workload_tolerations = [
      { key = "nvidia.com/gpu", operator = "Exists", value = null, effect = "NoSchedule" },
      { key = "kubernetes.azure.com/scalesetpriority", operator = "Equal", value = "spot", effect = "NoSchedule" }
    ]
    cluster_integration_instance_types = null
  }
}
