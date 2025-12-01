/*
 * Networking Variables
 */

variable "virtual_network_config" {
  type = object({
    address_space              = string
    subnet_address_prefix_main = string
    subnet_address_prefix_pe   = optional(string)
  })
  description = "Virtual network address configuration including address space and subnet prefixes. PE subnet prefix is only required when should_enable_private_endpoints is true"
  default = {
    address_space              = "10.0.0.0/16"
    subnet_address_prefix_main = "10.0.1.0/24"
    subnet_address_prefix_pe   = "10.0.2.0/24"
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

variable "should_enable_purge_protection" {
  type        = bool
  description = "Whether to enable purge protection on Key Vault. Set to false for dev/test to allow easy cleanup. WARNING: Once enabled, purge protection cannot be disabled"
  default     = false
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
 * Storage Variables
 */

variable "should_enable_storage_shared_access_key" {
  type        = bool
  description = "Whether to enable Shared Key (SAS token) authorization for the storage account. When false, all requests must use Azure AD authentication"
  default     = false
}
