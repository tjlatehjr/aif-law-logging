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
# Trace is intentionally omitted: it is internal debug data, adds log volume/cost,
# and contributes nothing to per-team token attribution.
resource "azurerm_monitor_diagnostic_setting" "foundry" {
  name                           = var.diagnostic_setting_name
  target_resource_id             = var.foundry_resource_id
  log_analytics_workspace_id     = var.law_id
  log_analytics_destination_type = var.log_analytics_destination_type

  # Optional second destination for long-term archive (off by default).
  storage_account_id = var.enable_storage_archive ? var.storage_account_id : null

  enabled_log {
    category = "RequestResponse"
  }

  enabled_log {
    category = "Audit"
  }

  # Optional platform metrics. enabled_metric is the azurerm v4 block (the older
  # `metric` block is deprecated and causes plan drift). Off by default.
  dynamic "enabled_metric" {
    for_each = var.enable_platform_metrics ? ["AllMetrics"] : []
    content {
      category = enabled_metric.value
    }
  }

  lifecycle {
    precondition {
      condition     = !var.enable_storage_archive || var.storage_account_id != null
      error_message = "storage_account_id is required when enable_storage_archive = true."
    }
  }
}
