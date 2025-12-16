/**
 * # Robotics Blueprint Variables
 *
 * Input variables for robotics infrastructure deployment.
 * Variables are organized by functional grouping with required variables first.
 */

/*
 * Core Variables - Required
 */

variable "environment" {
  type        = string
  description = "Environment for all resources in this module: dev, test, or prod"
}

variable "location" {
  type        = string
  description = "Location for all resources in this module"
}

variable "resource_prefix" {
  type        = string
  description = "Prefix for all resources in this module"
}

/*
 * Core Variables - Optional
 */

variable "instance" {
  type        = string
  description = "Instance identifier for naming resources: 001, 002, etc"
  default     = "001"
}

/*
 * Infrastructure Creation Flags - Optional
 */

variable "should_create_resource_group" {
  type        = bool
  description = "Whether to create the resource group for the robotics infrastructure"
  default     = true
}

variable "should_add_current_user_key_vault_admin" {
  type        = bool
  description = "Whether to add the current user as Key Vault Secrets Officer"
  default     = true
}

variable "should_add_current_user_storage_blob" {
  type        = bool
  description = "Whether to add the current user as Storage Blob Data Contributor"
  default     = true
}

variable "should_enable_purge_protection" {
  type        = bool
  description = "Whether to enable purge protection on Key Vault. Set to false for dev/test to allow easy cleanup. WARNING: Once enabled, purge protection cannot be disabled"
  default     = false
}

/*
 * PostgreSQL Configuration
 */

variable "should_deploy_postgresql" {
  type        = bool
  description = "Whether to deploy PostgreSQL Flexible Server component"
  default     = true
}

variable "postgresql_databases" {
  type = map(object({
    collation = string
    charset   = string
  }))
  description = "Map of databases to create with collation and charset"
  default = {
    osmo = {
      collation = "en_US.utf8"
      charset   = "utf8"
    }
  }
}

variable "postgresql_subnet_address_prefixes" {
  type        = list(string)
  description = "Address prefixes for the PostgreSQL delegated subnet."
  default     = ["10.0.12.0/24"]
}

variable "postgresql_sku_name" {
  type        = string
  description = "SKU name for PostgreSQL server"
  default     = "GP_Standard_D2s_v3"
}

variable "postgresql_storage_mb" {
  type        = number
  description = "Storage size in megabytes for PostgreSQL"
  default     = 32768
}

variable "postgresql_version" {
  type        = string
  description = "PostgreSQL server version"
  default     = "16"
}

/*
 * Azure Managed Redis Configuration - Optional
 */

variable "should_deploy_redis" {
  type        = bool
  description = "Whether to deploy Azure Managed Redis component"
  default     = true
}

variable "redis_sku_name" {
  type        = string
  description = "SKU name for Azure Managed Redis cache. Format: {Tier}_{Size} (e.g., Balanced_B10, Memory_M20, Compute_X10)"
  default     = "Balanced_B10"
}

variable "redis_clustering_policy" {
  type        = string
  description = "Clustering policy for Redis cache (OSSCluster or EnterpriseCluster). EnterpriseCluster recommended for clients that don't support Redis Cluster MOVED redirects"
  default     = "EnterpriseCluster"

  validation {
    condition     = contains(["OSSCluster", "EnterpriseCluster"], var.redis_clustering_policy)
    error_message = "Clustering policy must be either OSSCluster or EnterpriseCluster."
  }
}

/*
 * OSMO Workload Identity Configuration
 */

variable "osmo_config" {
  description = "OSMO configuration including workload identity settings"
  type = object({
    should_enable_identity   = bool
    should_federate_identity = bool
    control_plane_namespace  = string
    operator_namespace       = string
    workflows_namespace      = string
  })
  default = {
    should_enable_identity   = true
    should_federate_identity = true
    control_plane_namespace  = "osmo-control-plane"
    operator_namespace       = "osmo-operator"
    workflows_namespace      = "osmo-workflows"
  }
}

/*
 * Resource Name Overrides - Optional
 */

variable "resource_group_name" {
  type        = string
  description = "Existing resource group name containing foundational and ML resources (Otherwise 'rg-{resource_prefix}-{environment}-{instance}')"
  default     = null
}

/*
 * Networking Configuration - Optional
 */

variable "virtual_network_config" {
  type = object({
    address_space                  = string
    subnet_address_prefix          = string
    subnet_address_prefix_pe       = optional(string, "10.0.2.0/24")
    subnet_address_prefix_resolver = optional(string, "10.0.9.0/28")
  })
  description = "Configuration for the virtual network including address space and subnet prefixes. PE subnet prefix is required when private endpoints are enabled. Resolver subnet enables DNS resolution for VPN clients and on-premises networks"
  default = {
    address_space                  = "10.0.0.0/16"
    subnet_address_prefix          = "10.0.1.0/24"
    subnet_address_prefix_pe       = "10.0.2.0/24"
    subnet_address_prefix_resolver = "10.0.9.0/28"
  }
  validation {
    condition     = can(cidrhost(var.virtual_network_config.address_space, 0)) && can(cidrhost(var.virtual_network_config.subnet_address_prefix, 0))
    error_message = "Both address_space and subnet_address_prefix must be valid CIDR blocks."
  }
}

variable "subnet_address_prefixes_aks" {
  type        = list(string)
  description = "Address prefixes for the AKS subnet"
  default     = ["10.0.5.0/24"]
}

variable "subnet_address_prefixes_aks_pod" {
  type        = list(string)
  description = "Address prefixes for the AKS pod subnet"
  default     = ["10.0.6.0/24"]
}

/*
 * AKS Cluster Configuration - Optional
 */

variable "node_vm_size" {
  type        = string
  description = "VM size for the agent pool in the AKS cluster. Default is Standard_D8ds_v5"
  default     = "Standard_D8ds_v5"
}

variable "node_count" {
  type        = number
  description = "Number of nodes for the agent pool in the AKS cluster"
  default     = 1
}

variable "enable_auto_scaling" {
  type        = bool
  description = "Should enable auto-scaler for the default node pool"
  default     = false
}

variable "min_count" {
  type        = number
  description = "The minimum number of nodes which should exist in the default node pool. Valid values are between 0 and 1000"
  default     = null
}

variable "max_count" {
  type        = number
  description = "The maximum number of nodes which should exist in the default node pool. Valid values are between 0 and 1000"
  default     = null
}

/*
 * GPU Node Pool Configuration - Optional
 */

variable "node_pools" {
  type = map(object({
    node_count              = optional(number, null)
    vm_size                 = string
    subnet_address_prefixes = list(string)
    node_taints             = optional(list(string), [])
    enable_auto_scaling     = optional(bool, false)
    min_count               = optional(number, null)
    max_count               = optional(number, null)
    priority                = optional(string, "Regular")
    zones                   = optional(list(string), null)
    eviction_policy         = optional(string, "Deallocate")
    gpu_driver              = optional(string, null)
  }))
  description = "Additional node pools for the AKS cluster. Map key is used as the node pool name. Note: Pod subnets are not used with Azure CNI Overlay mode"
  default = {
    gpu = {
      vm_size                 = "Standard_NV36ads_A10_v5"
      subnet_address_prefixes = ["10.0.7.0/24"]
      node_taints             = ["nvidia.com/gpu:NoSchedule", "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"]
      gpu_driver              = "Install"
      priority                = "Spot"
      enable_auto_scaling     = true
      min_count               = 1
      max_count               = 1
      zones                   = []
      eviction_policy         = "Delete"
    }
  }
}

/*
 * AKS Integration Configuration - Optional
 */

variable "should_integrate_aks_cluster" {
  type        = bool
  description = "Whether to integrate an AKS cluster as a compute target with the workspace"
  default     = true
}

variable "aks_cluster_purpose" {
  type        = string
  description = "Purpose of AKS cluster: DevTest, DenseProd, or FastProd"
  default     = "DevTest"
  validation {
    condition     = contains(["DevTest", "DenseProd", "FastProd"], var.aks_cluster_purpose)
    error_message = "aks_cluster_purpose must be one of: DevTest, DenseProd, or FastProd."
  }
}

variable "workload_tolerations" {
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))
  description = "Tolerations for AzureML workloads (training/inference) to schedule on nodes with taints"
  default = [
    {
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    },
    {
      key      = "kubernetes.azure.com/scalesetpriority"
      operator = "Equal"
      value    = "spot"
      effect   = "NoSchedule"
    }
  ]
}

variable "cluster_integration_instance_types" {
  type = map(object({
    nodeSelector = optional(map(string))
    resources = optional(object({
      requests = optional(map(any))
      limits   = optional(map(any))
    }))
  }))
  description = "Instance types configuration for Kubernetes compute. Key is the instance type name, value contains nodeSelector and resource specifications"
  default = {
    gpuinstancetype = {
      nodeSelector = null
      resources = {
        limits = {
          cpu              = "8"
          memory           = "32Gi"
          "nvidia.com/gpu" = 1
        }
        requests = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
  }
}

/*
 * Private Endpoints Configuration - Optional
 */

variable "should_enable_private_endpoint" {
  type        = bool
  description = "Whether to enable private endpoints across resources for secure connectivity"
  default     = true
}

/*
 *  Public Network Access Configuration - Optional
 */

variable "should_enable_public_network_access" {
  type        = bool
  description = "Whether to enable public network access to the Azure ML workspace"
  default     = true
}

/*
 * Inference Router Configuration - Optional
 */

variable "inference_router_service_type" {
  type        = string
  description = "Service type for inference router: LoadBalancer, NodePort, or ClusterIP"
  default     = "NodePort"
  validation {
    condition     = contains(["LoadBalancer", "NodePort", "ClusterIP"], var.inference_router_service_type)
    error_message = "inference_router_service_type must be one of: LoadBalancer, NodePort, or ClusterIP."
  }
}

/*
 * HIL Cluster External Access
 */

variable "hil_cluster_cidrs" {
  type        = list(string)
  description = <<-EOT
    CIDR blocks of HIL clusters allowed to access Azure services and OSMO control plane.
    Configures firewall rules on Storage Account, ACR, Key Vault, and enables external
    LoadBalancer with loadBalancerSourceRanges during 002-setup.
    Use NAT gateway or firewall egress IPs (post-NAT), not internal IPs.
    Example: ["203.0.113.0/24", "198.51.100.0/24"]
  EOT
  default     = []
}

variable "should_get_wan_ip_for_hil" {
  type        = bool
  description = <<-EOT
    Include the current machine's public IP in hil_cluster_cidrs.
    Useful for development and testing scenarios.
    WARNING: IP may change between terraform applies.
  EOT
  default     = false
}
