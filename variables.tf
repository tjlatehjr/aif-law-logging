###############################################################################
# Workspace reference (Option B — variable supplied by DevOps).
# Option A (data source) is shown in README if you'd rather look it up live.
###############################################################################

variable "law_id" {
  description = "Resource ID of the shared Log Analytics workspace owned by the Copilot team. You never create/own this — DevOps supplies the ID."
  type        = string

  validation {
    condition     = can(regex("/providers/[Mm]icrosoft.OperationalInsights/workspaces/", var.law_id))
    error_message = "law_id must be a full Log Analytics workspace resource ID."
  }
}

###############################################################################
# Diagnostic setting target + alert placement
###############################################################################

variable "foundry_resource_id" {
  description = "Resource ID of the Azure AI Foundry (Cognitive Services) account that emits the RequestResponse/Audit logs."
  type        = string
}

variable "foundry_rg" {
  description = "Resource group name where the scheduled query rule (P3.1 gate) is created."
  type        = string
}

variable "location" {
  description = "Azure region for the scheduled query rule."
  type        = string
}

variable "diagnostic_setting_name" {
  description = "Name of the diagnostic setting on the Foundry account."
  type        = string
  default     = "foundry-token-logging"
}

variable "log_analytics_destination_type" {
  description = <<-EOT
    Table layout in the workspace:
      - "AzureDiagnostics" (default, shared table) — the bundled KQL targets this.
      - "Dedicated" (resource-specific AIFoundryRequestResponse table with typed columns).
    If you switch to Dedicated, the queries must be rewritten to the dedicated table/columns.
  EOT
  type        = string
  default     = "AzureDiagnostics"

  validation {
    condition     = contains(["AzureDiagnostics", "Dedicated"], var.log_analytics_destination_type)
    error_message = "Must be \"AzureDiagnostics\" or \"Dedicated\"."
  }
}

###############################################################################
# Caller -> team mapping (single source of truth, injected into AIF_CallerToTeam)
###############################################################################

variable "caller_to_team" {
  description = "Maps principal IDs (oid or appid) to team names. Seeded from the P0.3 inventory. Migrates to Entra group-ID keys after P1.2."
  type = list(object({
    principal_id = string
    caller_type  = string # "user" | "app" | "key"
    team         = string
  }))

  # Fallback row keeps AIF_CallerToTeam() resolvable before inventory data arrives.
  default = [
    { principal_id = "api-key", caller_type = "key", team = "api-key-unattributed" }
  ]
}

###############################################################################
# Per-team-per-model monthly token quotas (injected into AIF_TokenBurn)
###############################################################################

variable "token_quotas" {
  description = "Per-team-per-model token quotas consumed by AIF_TokenBurn. Update as quotas are agreed per P1.4."
  type = list(object({
    team         = string
    model        = string
    input_quota  = number
    output_quota = number
  }))
  default = []
}

###############################################################################
# Optional notification target for the P3.1 gate alert
###############################################################################

variable "action_group_ids" {
  description = "Action group IDs to notify when the P3.1 key-auth gate fires. Leave empty for a portal-only (silent) signal."
  type        = list(string)
  default     = []
}
