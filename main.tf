locals {
  # Rows injected into the AIF_CallerToTeam() datatable. join() avoids a trailing
  # comma (which KQL datatable() rejects); %q produces safely-quoted strings.
  caller_rows = join(",\n    ", [
    for r in var.caller_to_team : format("%q, %q, %q", r.principal_id, r.caller_type, r.team)
  ])

  # Rows injected into the quota datatable inside AIF_TokenBurn.
  quota_rows = join(",\n    ", [
    for q in var.token_quotas : format("%q, %q, %d, %d", q.team, q.model, q.input_quota, q.output_quota)
  ])
}

# Ships Foundry RequestResponse + Audit logs to the shared (Copilot-owned) workspace.
resource "azurerm_monitor_diagnostic_setting" "foundry" {
  name                           = var.diagnostic_setting_name
  target_resource_id             = var.foundry_resource_id
  log_analytics_workspace_id     = var.law_id
  log_analytics_destination_type = var.log_analytics_destination_type

  enabled_log {
    category = "RequestResponse"
  }

  enabled_log {
    category = "Audit"
  }
}
