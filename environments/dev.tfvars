# P1.1 — Dev environment values from the JIRA ticket.
# law_id: confirm the workspace name in the owner-team IaC repo before merge.

foundry_resource_id = "/subscriptions/e36760c0-97ec-41f7-a993-36afc19f2770/resourceGroups/a1a-51412-dev-rg-aif-eus2-01/providers/Microsoft.CognitiveServices/accounts/a1a-51412-dev-aif-aif-eus2-02"
foundry_rg          = "a1a-51412-dev-rg-aif-eus2-01"
location            = "eastus2"

# TODO: replace with actual workspace resource ID from the owner-team repo
law_id = "/subscriptions/e36760c0-97ec-41f7-a993-36afc19f2770/resourceGroups/<copilot-rg>/providers/Microsoft.OperationalInsights/workspaces/<copilot-law-name>"

diagnostic_setting_name = "foundry-token-logging"

# AzureDiagnostics = shared table (the KQL targets this).
# Switch to "Dedicated" only if the workspace is configured for resource-specific mode.
log_analytics_destination_type = "AzureDiagnostics"

# Stub row — keeps AIF_CallerToTeam() resolvable before P0.3 inventory arrives.
# Replace with real principal IDs once inventory is seeded.
caller_to_team = [
  { principal_id = "api-key", caller_type = "key", team = "api-key-unattributed" }
]

# Empty until quotas are agreed (P1.4). Functions still parse + run; quota columns show null.
token_quotas = []
