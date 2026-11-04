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
  description = "Region of the policy assignments' managed identity reference and of every Bastion resource."
  type        = string
  default     = "francecentral"
}

variable "allowed_locations" {
  description = "Regions the Allowed locations control accepts. Matches the subscription's own region policy."
  type        = list(string)
  default     = ["francecentral", "italynorth", "swedencentral", "polandcentral", "switzerlandnorth"]
}

variable "denied_resource_types" {
  description = "Resource types the denied_resource_types control blocks in the Bastion groups: paid network appliances (docs/adr/0007), public IPs, and VMs (no VM in the always-on design)."
  type        = list(string)
  default = [
    "Microsoft.Network/azureFirewalls",
    "Microsoft.Network/firewallPolicies",
    "Microsoft.Network/bastionHosts",
    "Microsoft.Network/virtualNetworkGateways",
    "Microsoft.Network/vpnGateways",
    "Microsoft.Network/expressRouteCircuits",
    "Microsoft.Network/expressRouteGateways",
    "Microsoft.Network/ddosProtectionPlans",
    "Microsoft.Network/applicationGateways",
    "Microsoft.Network/natGateways",
    "Microsoft.Network/virtualHubs",
    "Microsoft.Network/publicIPAddresses",
    "Microsoft.Network/publicIPPrefixes",
    "Microsoft.Compute/virtualMachines",
    "Microsoft.Compute/virtualMachineScaleSets",
  ]
}

variable "assignment_resource_groups" {
  description = "Bastion resource groups that receive bastion-baseline with its real effects. Never add a protected group here."
  type        = list(string)
  default     = ["bastion-hub-rg", "bastion-spoke-app-rg", "bastion-test-rg"]

  validation {
    condition     = alltrue([for rg in var.assignment_resource_groups : startswith(rg, "bastion-")])
    error_message = "bastion-baseline may only be assigned with real effects to resource groups whose name starts with bastion-."
  }
}

variable "protected_resource_groups" {
  description = "Groups Bastion never modifies. Excluded from every subscription-scope assignment."
  type        = list(string)
  default     = ["huginn-lab-rg", "huginn-sentinel-rg", "huginn-tfstate-rg", "fenrir-lab-prod-rg"]
}

variable "existing_prefixed_protected_groups" {
  description = "Existing groups that match protected_resource_group_prefixes (for example every ctf- group). Azure Policy not_scopes has no wildcards, so each one must be listed by name to be excluded from the subscription-scope audit."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for rg in var.existing_prefixed_protected_groups : anytrue([for p in ["ctf-"] : startswith(rg, p)])
    ])
    error_message = "Only list groups that start with a protected prefix (ctf-)."
  }
}

variable "enable_subscription_audit" {
  description = "Also assign bastion-baseline at subscription scope, in audit-only mode, excluding every protected group. Off by default."
  type        = bool
  default     = false
}

variable "huginn_workspace_id" {
  description = "Resource ID of Huginn's Log Analytics workspace (law-huginn). Built from names; no data source, so no listKeys call is ever made."
  type        = string
  default     = "/subscriptions/42146134-9464-4c2d-86b0-afe414704284/resourceGroups/huginn-sentinel-rg/providers/Microsoft.OperationalInsights/workspaces/law-huginn"
}

variable "policy_identity_name" {
  description = "User-assigned identity created by the bootstrap for DeployIfNotExists remediation."
  type        = string
  default     = "id-bastion-policy"
}

variable "policy_identity_resource_group" {
  description = "Resource group of the policy identity."
  type        = string
  default     = "bastion-hub-rg"
}

variable "budget_amount" {
  description = "Monthly subscription budget, in the billing currency of the subscription (USD for Azure for Students)."
  type        = number
  default     = 20

  validation {
    condition     = var.budget_amount > 0
    error_message = "The budget must be greater than zero."
  }
}

variable "budget_alert_emails" {
  description = "Addresses that get budget alerts. Set through the BUDGET_ALERT_EMAIL repository variable (TF_VAR_budget_alert_emails), never committed."
  type        = list(string)

  validation {
    condition     = length(var.budget_alert_emails) > 0 && alltrue([for e in var.budget_alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Give at least one valid email address."
  }
}

variable "budget_start_date" {
  description = "First day of the first budget month (RFC3339). Must be the first of a month, not in the past when first created."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}
