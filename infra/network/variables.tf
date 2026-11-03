variable "tenant_id" {
  description = "Entra ID tenant."
  type        = string
  default     = "972afa9f-85f2-4581-81c4-a126c475a06d"
}

variable "subscription_id" {
  description = "The single Azure for Students subscription."
  type        = string
  default     = "42146134-9464-4c2d-86b0-afe414704284"
}

variable "location" {
  description = "Region for the hub and the spoke."
  type        = string
  default     = "francecentral"
}

variable "hub_resource_group" {
  description = "Platform (hub) resource group, created by the bootstrap."
  type        = string
  default     = "bastion-hub-rg"
}

variable "spoke_resource_group" {
  description = "Workload (spoke) resource group, created by the bootstrap."
  type        = string
  default     = "bastion-spoke-app-rg"
}

variable "hub_address_space" {
  description = "Hub VNet address space."
  type        = string
  default     = "10.10.0.0/16"
}

variable "spoke_address_space" {
  description = "Spoke VNet address space."
  type        = string
  default     = "10.20.0.0/16"
}

variable "owner_tag" {
  description = "Owner tag value."
  type        = string
  default     = "MarwenOnGit"
}
