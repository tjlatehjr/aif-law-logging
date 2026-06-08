# AIF Log Analytics Logging (P1.1)

Terraform module that ships Azure AI Foundry diagnostic logs to the **shared,
Copilot-owned** Log Analytics workspace and provisions the AIF saved-function
suite plus the P3.1 key-auth gating alert.

## Layout

```
aif-law-logging/
├── versions.tf        # azurerm >= 4.0
├── variables.tf       # law_id, foundry target, caller_to_team, token_quotas, ...
├── main.tf            # datatable-row locals + diagnostic setting
├── functions.tf       # 6 azurerm_log_analytics_saved_search functions
├── alerts.tf          # P3.1 scheduled query rule
├── outputs.tf
└── kql/
    ├── aif_caller_to_team.kql        # templated (rows from var.caller_to_team)
    ├── aif_tokens_by_team.kql
    ├── aif_tokens_by_team_model.kql
    ├── aif_token_burn.kql            # templated (quota rows from var.token_quotas)
    ├── aif_chargeback_by_team.kql
    ├── aif_top_users_in_team.kql     # INFERRED — see note below
    └── p3_1_key_auth_gate.kql
```

## Prerequisites (one-time, from the Copilot team / shared DevOps)

1. The workspace **resource ID** (feeds `var.law_id`).
2. **Log Analytics Contributor** on that workspace, granted to the Foundry IaC
   service principal — required to create the saved functions and the alert.

You never create or own the workspace; this module only references it.

## Usage

```hcl
module "aif_logging" {
  source = "./aif-law-logging"

  law_id              = var.copilot_law_id          # supplied by DevOps
  foundry_resource_id = azurerm_cognitive_account.foundry.id
  foundry_rg          = var.foundry_rg
  location            = var.location

  caller_to_team = [
    { principal_id = "aad-oid-of-alice",   caller_type = "user", team = "sg-aif-mcp" },
    { principal_id = "aad-oid-of-bob",     caller_type = "user", team = "sg-aif-mcp-tool" },
    { principal_id = "app-id-of-svc-acct", caller_type = "app",  team = "sg-aif-mcp-qe" },
    { principal_id = "api-key",            caller_type = "key",  team = "api-key-unattributed" },
  ]

  token_quotas = [
    { team = "sg-aif-mcp",      model = "claude-sonnet-4-6", input_quota = 50000000, output_quota = 10000000 },
    { team = "sg-aif-mcp-tool", model = "claude-sonnet-4-6", input_quota = 30000000, output_quota = 6000000 },
  ]

  # Optional: notify on the P3.1 gate instead of portal-only
  # action_group_ids = [azurerm_monitor_action_group.aif.id]
}
```

Calling the functions in the workspace:

```kql
AIF_TokensByTeam(7d)
AIF_TokensByTeamModel(30d)
AIF_TokenBurn("sg-aif-mcp", startofmonth(now()))
AIF_ChargebackByTeam(startofmonth(now()), 38500.0)   // RG total from Cost Management
AIF_TopUsersInTeam("sg-aif-mcp", 1d)
```

## Decisions & deltas from the requirement doc

These are the places where the module deviates from the literal text of the
spec — each is a deliberate choice, flagged so you can override.

- **Option B (variable) for the workspace ref**, per the doc's recommendation.
  For Option A (live data source), replace `var.law_id` with:
  ```hcl
  data "azurerm_log_analytics_workspace" "copilot" {
    name                = var.copilot_law_name
    resource_group_name = var.copilot_law_rg
  }
  # then reference data.azurerm_log_analytics_workspace.copilot.id
  ```
  Option A needs **Reader** on the Copilot RG for the IaC SP.

- **`AIF_CallerToTeam()` is the single mapping source.** The doc shows two
  styles (a `templatefile` injecting `caller_to_team` directly into
  `AIF_TokensByTeam`, and a standalone `AIF_CallerToTeam()` helper). These are
  reconciled to the helper-only design — the datatable lives in one place and
  every other function calls it, matching "the only place the translation lives."

- **`rgTotalUSD` is a function parameter**, not a hardcoded `let`. The monthly
  Cost Management figure is passed at query time, so no IaC redeploy each month.

- **Quotas are a variable** (`var.token_quotas`) injected into `AIF_TokenBurn`,
  rather than an edited-in-place datatable.

- **Alert resource corrected.** `azurerm_monitor_scheduled_query_rules_alert_v2`
  uses `scopes`; the `workspace_id` line in the doc's snippet is a v1 concept and
  is dropped. An optional `action` block is wired to `var.action_group_ids`.

- **`AIF_TopUsersInTeam` is INFERRED.** The doc names it (basis: the
  "Tokens by caller oid" query) but gives no body. The bundled KQL derives it
  from that query, scoped by team. Review before relying on it; remove the
  resource + `.kql` file if it's owned elsewhere.

## Verify before / after apply

- **Table mode.** The KQL targets the shared `AzureDiagnostics` table
  (`var.log_analytics_destination_type = "AzureDiagnostics"`, the default). If
  the workspace is in **Dedicated** (resource-specific) mode, Foundry emits to a
  typed `AIFoundryRequestResponse` table and the queries must be rewritten. Pull
  one sample row after the diagnostic setting goes live and confirm the table +
  column names (`identity_claim_oid_g`, `properties_s`, etc.).

- **Provider version.** `enabled_log`, `log_analytics_destination_type`, and the
  `_v2` scheduled-query resource are azurerm v4 shapes. Run `terraform validate`
  against your pinned provider — these arguments shifted across major versions.

- **Smoke test (rows within ~15 min):** filter `AzureDiagnostics` to
  `ResourceProvider == "MICROSOFT.COGNITIVESERVICES"` for your Foundry resource
  and confirm `RequestResponse` rows are landing before trusting the functions.
