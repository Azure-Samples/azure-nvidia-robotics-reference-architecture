/*
 * Dependencies from Platform Module
 */

variable "virtual_network" {
  type = object({
    id   = string
    name = string
  })
  description = "Virtual network from platform module"
}

variable "subnets" {
  type = object({
    main = object({
      id   = string
      name = string
    })
    private_endpoints = object({
      id   = string
      name = string
    })
  })
  description = "Subnets from platform module"
}

variable "network_security_group" {
  type = object({
    id = string
  })
  description = "NSG from platform module"
}

variable "nat_gateway" {
  type = object({
    id = string
  })
  description = "NAT Gateway from platform module"
}

variable "log_analytics_workspace" {
  type = object({
    id           = string
    workspace_id = string
  })
  description = "Log Analytics from platform module"
}

variable "monitor_workspace" {
  type = object({
    id = string
  })
  description = "Azure Monitor workspace from platform module"
}

variable "data_collection_endpoint" {
  type = object({
    id = string
  })
  description = "Data Collection Endpoint from platform module"
}

variable "container_registry" {
  type = object({
    id           = string
    name         = string
    login_server = string
  })
  description = "ACR from platform module"
}

variable "azureml_workspace" {
  type = object({
    id           = string
    name         = string
    workspace_id = string
  })
  description = "ML workspace from platform module"
}

variable "ml_workload_identity" {
  type = object({
    id           = string
    principal_id = string
    client_id    = string
    tenant_id    = string
  })
  description = "ML identity from platform module"
}

variable "private_dns_zones" {
  type = map(object({
    id   = string
    name = string
  }))
  description = "Private DNS zones from platform module"
  default     = {}
}
