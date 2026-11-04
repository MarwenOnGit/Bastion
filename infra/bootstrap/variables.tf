variable "tenant_id" {
  description = "Entra ID tenant that holds the subscription."
  type        = string
  default     = "972afa9f-85f2-4581-81c4-a126c475a06d"
}

variable "subscription_id" {
  description = "The single Azure for Students subscription."
  type        = string
  default     = "42146134-9464-4c2d-86b0-afe414704284"
}

variable "location" {
  description = "Region for every Bastion resource. Must be one of the regions the subscription policy allows."
  type        = string
  default     = "francecentral"

  validation {
    condition     = contains(["francecentral", "italynorth", "swedencentral", "polandcentral", "switzerlandnorth"], var.location)
    error_message = "The Azure for Students subscription only allows francecentral, italynorth, swedencentral, polandcentral and switzerlandnorth."
  }
}

variable "owner_tag" {
  description = "Value of the owner tag on every Bastion resource."
  type        = string
  default     = "MarwenOnGit"
}

# GitHub OIDC. This tenant expects ID-based subjects:
# repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
variable "github_owner" {
  description = "GitHub owner (user) name, exactly as GitHub spells it."
  type        = string
  default     = "MarwenOnGit"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID."
  type        = string
  default     = "183097322"
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "Bastion"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID (gh api repos/<owner>/<repo> --jq .id)."
  type        = string
  default     = "1444942400"
}

variable "plan_branches" {
  description = "Branches whose push and scheduled runs may use the read-only plan identity."
  type        = list(string)
  default     = ["bastion-dev", "main"]
}

variable "plan_on_pull_requests" {
  description = "Trust the plan identity for pull_request runs (subject ':pull_request'). GitHub does not issue OIDC tokens to pull requests from forks."
  type        = bool
  default     = true
}

variable "huginn_workspace" {
  description = "Huginn's Log Analytics workspace. Bastion only reads its ID and, if allowed below, grants the policy identity a role on it."
  type = object({
    resource_group_name = string
    name                = string
  })
  default = {
    resource_group_name = "huginn-sentinel-rg"
    name                = "law-huginn"
  }
}

variable "grant_policy_identity_on_huginn_workspace" {
  description = "Grant the policy identity a role on law-huginn so diagnostic settings can send to it (Bastion Diagnostics Destination by default, see narrow_huginn_workspace_role). A role assignment in huginn-sentinel-rg; no setting of the workspace changes. Without it the diagnostic-settings policies can report but not deploy."
  type        = bool
  default     = true
}

variable "narrow_huginn_workspace_role" {
  description = "Use the custom role Bastion Diagnostics Destination (workspaces/read + workspaces/sharedKeys/action) on law-huginn instead of Log Analytics Contributor. Set to false only if Azure refuses the diagnostic-settings deployment with the narrow role."
  type        = bool
  default     = true
}

variable "policy_identity_log_analytics_contributor" {
  description = "Also grant the policy identity Log Analytics Contributor on the Bastion groups, as the KV and NSG diagnostic built-ins list it. Off: Monitoring Contributor covers diagnostic settings and deployments. Turn on only if remediation fails without it."
  type        = bool
  default     = false
}

variable "lock_huginn_workspace" {
  description = "Put a CanNotDelete lock on law-huginn. While it exists, nobody can delete the workspace, including Huginn's own Terraform (terraform destroy in the Huginn repo fails until this is set to false and the bootstrap is applied)."
  type        = bool
  default     = true
}

variable "move_subscription_to_management_group" {
  description = "Optional and off by default. Set to \"landing-zones\" to move the subscription under bastion-landing-zones. Read docs/adr/0001 first."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "platform", "landing-zones", "sandbox"], var.move_subscription_to_management_group)
    error_message = "Use \"\" (do not move), \"platform\", \"landing-zones\" or \"sandbox\"."
  }
}
