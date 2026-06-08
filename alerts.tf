# P3.1 gate: fires if ANY successful API-key-authenticated call is seen.
# Must stay silent for 7 consecutive days before disableLocalAuth=true may merge.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "p3_1_gate" {
  name                = "aif-key-auth-calls-gate"
  resource_group_name = var.foundry_rg
  location            = var.location

  # NOTE: v2 uses `scopes` (the workspace IS the scope). The v1-style
  # `workspace_id` argument does not exist on this resource.
  scopes   = [var.law_id]
  severity = 3 # Informational

  evaluation_frequency = "P1D"
  window_duration      = "P7D"

  criteria {
    query                   = file("${path.module}/kql/p3_1_key_auth_gate.kql")
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"
  }

  dynamic "action" {
    for_each = length(var.action_group_ids) > 0 ? [1] : []
    content {
      action_groups = var.action_group_ids
    }
  }

  description = "Fires if any successful API-key-authenticated call is seen. Must be silent for 7 days before P3.1 (disableLocalAuth) merges."
}
