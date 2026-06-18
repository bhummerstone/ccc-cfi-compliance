variable "subscription_id" {
  type        = string
  description = "Azure subscription ID used by the azurerm provider and, by default, as the deployment/assignment scope."
}

variable "location" {
  type        = string
  description = "Azure region for the policy assignment's managed identity (required by avm-ptn-policyassignment even when no remediation identity is used)."
  default     = "westeurope"
}

variable "management_group_id" {
  type        = string
  description = "Optional management group resource ID at which to create the policy and initiative definitions (e.g. /providers/Microsoft.Management/managementGroups/<mg>). When null, definitions are created at the subscription configured in the provider."
  default     = null
}

variable "assignment_scope" {
  type        = string
  description = "Resource ID of the scope the initiative is assigned to (subscription, resource group, or management group). When null, defaults to the provider subscription (/subscriptions/<subscription_id>)."
  default     = null
}

variable "create_assignment" {
  type        = bool
  description = "When true, assign the initiative at assignment_scope via the avm-ptn-policyassignment module. Set to false to deploy only the definitions and the initiative."
  default     = true
}

variable "enforcement_mode" {
  type        = string
  description = "Assignment enforcement mode. 'Default' enforces effects (e.g. Deny); 'DoNotEnforce' evaluates compliance without enforcing - useful for an initial audit-only roll-out."
  default     = "Default"

  validation {
    condition     = contains(["Default", "DoNotEnforce"], var.enforcement_mode)
    error_message = "enforcement_mode must be either 'Default' or 'DoNotEnforce'."
  }
}

variable "assignment_name" {
  type        = string
  description = "Name (max 24 chars) for the initiative assignment resource."
  default     = "ccc-avm-guardrails"
}

# ---------------------------------------------------------------------------
# Policy-only governance baseline. These reference Azure built-in policies that
# enforce CCC controls the AVM modules cannot configure (CN06 trust perimeter,
# CN11 key rotation, CN04 resource logs, CN14 backups). All are Audit /
# AuditIfNotExists / Deny - no remediation identity is required.
# ---------------------------------------------------------------------------
variable "include_governance_baseline" {
  type        = bool
  description = "When true, add the built-in policy-only governance baseline (CCC.Core CN06/CN11/CN04/CN14) to the initiative. Set false to deploy only the custom AVM-aligned definitions."
  default     = true
}

variable "allowed_locations" {
  type        = list(string)
  description = "CCC.Core.CN06 trust perimeter - Azure regions resources may be deployed to. When empty, defaults to [var.location]."
  default     = []
}

variable "allowed_locations_effect" {
  type        = string
  description = "Effect for the CCC.Core.CN06 allowed-locations guardrail. Audit (report-only) by default; set Deny to block out-of-perimeter regions."
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.allowed_locations_effect)
    error_message = "allowed_locations_effect must be one of Audit, Deny, or Disabled."
  }
}

variable "key_rotation_maximum_days" {
  type        = number
  description = "CCC.Core.CN11 - maximum days after key creation before rotation is required (audit only)."
  default     = 365
}

variable "governance_log_retention_days" {
  type        = number
  description = "CCC.Core.CN04 - required diagnostic-log retention in days for the resource-logs audit."
  default     = 365
}
