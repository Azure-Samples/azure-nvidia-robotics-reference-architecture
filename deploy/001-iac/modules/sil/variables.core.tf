/*
 * Core Variables
 * Standard variables consistent across all modules
 */

variable "environment" {
  type        = string
  description = "Environment for all resources in this module: dev, test, or prod"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be one of: dev, test, prod"
  }
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

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}
