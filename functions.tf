###############################################################################
# AIF saved-search functions. All KQL lives in ./kql/*.kql.
#  - aif_caller_to_team is the ONLY place the principal -> team table lives;
#    every other function calls AIF_CallerToTeam().
#  - depends_on enforces create/destroy ordering for functions that reference
#    other functions (Log Analytics resolves the reference at query time, but
#    ordered apply/destroy avoids transient "unknown function" noise).
###############################################################################

resource "azurerm_log_analytics_saved_search" "aif_caller_to_team" {
  name                       = "AIF_CallerToTeam"
  log_analytics_workspace_id = var.law_id
  category                   = "AIF"
  display_name               = "AIF - Caller to Team mapping"
  function_alias             = "AIF_CallerToTeam"

  query = templatefile("${path.module}/kql/aif_caller_to_team.kql", {
    rows = local.caller_rows
  })
}

resource "azurerm_log_analytics_saved_search" "aif_tokens_by_team" {
  name                       = "AIF_TokensByTeam"
  log_analytics_workspace_id = var.law_id
  category                   = "AIF"
  display_name               = "AIF - Tokens by Team"
  function_alias             = "AIF_TokensByTeam"
  function_parameters        = ["timeRange:timespan=7d"]

  query = file("${path.module}/kql/aif_tokens_by_team.kql")

  depends_on = [azurerm_log_analytics_saved_search.aif_caller_to_team]
}

resource "azurerm_log_analytics_saved_search" "aif_tokens_by_team_model" {
  name                       = "AIF_TokensByTeamModel"
  log_analytics_workspace_id = var.law_id
  category                   = "AIF"
  display_name               = "AIF - Tokens by Team and Model"
  function_alias             = "AIF_TokensByTeamModel"
  function_parameters        = ["timeRange:timespan=7d"]

  query = file("${path.module}/kql/aif_tokens_by_team_model.kql")

  depends_on = [azurerm_log_analytics_saved_search.aif_caller_to_team]
}

resource "azurerm_log_analytics_saved_search" "aif_token_burn" {
  name                       = "AIF_TokenBurn"
  log_analytics_workspace_id = var.law_id
  category                   = "AIF"
  display_name               = "AIF - MTD Token Burn vs Quota"
  function_alias             = "AIF_TokenBurn"
  function_parameters        = ["team_param:string", "monthStart:datetime"]

  query = templatefile("${path.module}/kql/aif_token_burn.kql", {
    quota_rows = local.quota_rows
  })

  depends_on = [azurerm_log_analytics_saved_search.aif_tokens_by_team_model]
}

resource "azurerm_log_analytics_saved_search" "aif_chargeback_by_team" {
  name                       = "AIF_ChargebackByTeam"
  log_analytics_workspace_id = var.law_id
  category                   = "AIF"
  display_name               = "AIF - Monthly Chargeback by Team"
  function_alias             = "AIF_ChargebackByTeam"
  # rgTotalUSD is a parameter (not a hardcoded let) so the monthly Cost Management
  # figure is passed at query time -- no IaC redeploy each month.
  function_parameters = ["monthStart:datetime", "rgTotalUSD:real"]

  query = file("${path.module}/kql/aif_chargeback_by_team.kql")

  depends_on = [azurerm_log_analytics_saved_search.aif_tokens_by_team_model]
}

# INFERRED: the requirement references AIF_TopUsersInTeam ("Tokens by caller oid"
# query) but does not provide its body. This implementation derives it from that
# query, scoped by team. Review before relying on it.
resource "azurerm_log_analytics_saved_search" "aif_top_users_in_team" {
  name                       = "AIF_TopUsersInTeam"
  log_analytics_workspace_id = var.law_id
  category                   = "AIF"
  display_name               = "AIF - Top Users in Team"
  function_alias             = "AIF_TopUsersInTeam"
  function_parameters        = ["team_param:string", "timeRange:timespan=1d"]

  query = file("${path.module}/kql/aif_top_users_in_team.kql")

  depends_on = [azurerm_log_analytics_saved_search.aif_caller_to_team]
}
