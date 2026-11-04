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
  description = "Region for the workload."
  type        = string
  default     = "francecentral"
}

variable "spoke_resource_group" {
  description = "Workload resource group, created by the bootstrap."
  type        = string
  default     = "bastion-spoke-app-rg"
}

variable "hub_resource_group" {
  description = "Hub resource group that holds the private DNS zones."
  type        = string
  default     = "bastion-hub-rg"
}

variable "owner_tag" {
  description = "Owner tag value."
  type        = string
  default     = "MarwenOnGit"
}
