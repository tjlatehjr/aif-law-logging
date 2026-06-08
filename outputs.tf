output "diagnostic_setting_id" {
  description = "ID of the Foundry diagnostic setting."
  value       = azurerm_monitor_diagnostic_setting.foundry.id
}

output "saved_function_ids" {
  description = "IDs of the AIF saved-search functions, keyed by alias."
  value = {
    AIF_CallerToTeam      = azurerm_log_analytics_saved_search.aif_caller_to_team.id
    AIF_TokensByTeam      = azurerm_log_analytics_saved_search.aif_tokens_by_team.id
    AIF_TokensByTeamModel = azurerm_log_analytics_saved_search.aif_tokens_by_team_model.id
    AIF_TokenBurn         = azurerm_log_analytics_saved_search.aif_token_burn.id
    AIF_ChargebackByTeam  = azurerm_log_analytics_saved_search.aif_chargeback_by_team.id
    AIF_TopUsersInTeam    = azurerm_log_analytics_saved_search.aif_top_users_in_team.id
  }
}

output "p3_1_gate_alert_id" {
  description = "ID of the P3.1 key-auth gating scheduled query rule."
  value       = azurerm_monitor_scheduled_query_rules_alert_v2.p3_1_gate.id
}
