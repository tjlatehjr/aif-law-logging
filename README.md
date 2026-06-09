# AIF Log Analytics Logging (P1.1)

Terraform module that ships Azure AI Foundry diagnostic logs to the **shared,
Copilot-owned** Log Analytics workspace and provisions the AIF saved-function
suite (per-team token attribution + chargeback) plus the P3.1 key-auth gating
alert. Scope is the data feed and its analytics — it does **not** create or own
the workspace.

## Layout

```
aif-law-logging/
├── versions.tf        # azurerm >= 4.0
├── variables.tf       # law_id, foundry target, caller_to_team, token_quotas, optional toggles
├── main.tf            # datatable-row locals + diagnostic setting
├── functions.tf       # 6 azurerm_log_analytics_saved_search functions
├── alerts.tf          # P3.1 scheduled query rule
├── outputs.tf
├── verify_p1_1.sh     # post-deploy AC check (pure bash + az CLI)
├── environments/
│   └── dev.tfvars
└── kql/
    ├── aif_caller_to_team.kql        # templated (rows from var.caller_to_team)
    ├── aif_tokens_by_team.kql
    ├── aif_tokens_by_team_model.kql
    ├── aif_token_burn.kql            # templated (quota rows from var.token_quotas)
    ├── aif_chargeback_by_team.kql
    ├── aif_top_users_in_team.kql     # INFERRED — see note
    └── p3_1_key_auth_gate.kql
```

## Why this differs from the standard tutorial pattern

Most "Foundry diagnostic logging with Terraform" guides assume a greenfield,
single-team setup. This module is deliberately different because the environment
is brownfield, multi-team, and cost-sensitive:

- **Workspace is referenced, not created.** A second workspace carries its own
  baseline cost for no functional gain, and the ticket explicitly says reuse the
  owner team's workspace. There is no `azurerm_log_analytics_workspace` resource
  here — only `var.law_id`.
- **RequestResponse + Audit only — no Trace.** Trace is internal service debug
  data; it inflates log volume (and cost) and adds nothing to token attribution.
- **No operational metric alerts.** Latency/error metric alerts are a separate
  observability concern. The one alert here is the P3.1 *log* gate, which is the
  actual requirement.
- **Storage archive and platform metrics are optional, default-off toggles**
  (`enable_storage_archive`, `enable_platform_metrics`) — available if you later
  want them, but out of the P1.1 data-feed scope by default.

## Prerequisites (one-time, from the Copilot team / shared DevOps)

1. The workspace **resource ID** (feeds `var.law_id`).
2. **Log Analytics Contributor** on that workspace for the Foundry IaC service
   principal — required to create the saved functions and the alert.
3. **Retention:** the ticket prefers 90 days for chargeback reconciliation. You
   don't own the workspace, so request 90-day table retention from the owner, or
   flip `enable_storage_archive` for independent long-term retention in your own
   Storage Account.

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
    { principal_id = "app-id-of-svc-acct", caller_type = "app",  team = "sg-aif-mcp-qe" },
    { principal_id = "api-key",            caller_type = "key",  team = "api-key-unattributed" },
  ]

  token_quotas = [
    { team = "sg-aif-mcp", model = "claude-sonnet-4-6", input_quota = 50000000, output_quota = 10000000 },
  ]

  # Optional extras (off by default):
  # enable_storage_archive  = true
  # storage_account_id      = azurerm_storage_account.logs.id
  # enable_platform_metrics = true
  # action_group_ids        = [azurerm_monitor_action_group.aif.id]
}
```

Calling the functions in the workspace:

```kql
AIF_TokensByTeam(7d)
AIF_TokensByTeamModel(30d)
AIF_TopUsersInTeam("sg-aif-mcp", 1d)
AIF_TokenBurn("sg-aif-mcp", startofmonth(now()))
AIF_ChargebackByTeam(startofmonth(now()), 38500.0)   // RG total from Cost Management
```

## Robustness: empty-data and column resolution

Azure validates a scheduled-query rule's KQL against the workspace schema **at
creation time**, and the saved functions are queried before much data exists.
The Foundry-specific columns (`identity_claim_oid_g`, `identity_claim_appid_g`,
`properties_s`) don't exist until Cognitive Services data lands — a chicken-and-
egg problem, since the diagnostic setting that creates them deploys in the same
apply.

Every query wraps those columns in `column_ifexists("name", "")`, so it parses
and runs on an empty workspace and returns the correct columns (the ticket's
explicit AC). `case(...)` — not `coalesce(...)` — distinguishes the auth paths,
because an empty-string claim is non-null and `coalesce` would not fall through.

## Decisions & deltas from the requirement doc

- **Option B (variable) for the workspace ref.** For Option A (live data source):
  ```hcl
  data "azurerm_log_analytics_workspace" "copilot" {
    name                = var.copilot_law_name
    resource_group_name = var.copilot_law_rg
  }
  # reference data.azurerm_log_analytics_workspace.copilot.id (needs Reader on the Copilot RG)
  ```
- **`AIF_CallerToTeam()` is the single mapping source.** The datatable lives in
  one place; every other function calls it.
- **`rgTotalUSD` is a function parameter**, not a hardcoded `let` — no IaC
  redeploy each month.
- **Quotas are a variable** injected into `AIF_TokenBurn`.
- **Alert corrected** — `..._v2` uses `scopes`, not `workspace_id`.
- **`AIF_TopUsersInTeam` is INFERRED.** The doc/ticket name it (params match the
  ticket's `(team, timeRange)`) but give no body; derived from the "tokens by
  caller oid" query. Review before relying on it.

## Deployment fixes folded in

- `window_duration = "P2D"` — provider caps it at P2D; the real 7-day lookback is
  in the query's `ago(7d)`.
- `column_ifexists("identity_claim_oid_g", "")` across all queries — fixes the
  `Failed to resolve scalar expression 'identity_claim_oid_g'` 400 and the
  empty-data case.
- `enabled_metric` (not the deprecated `metric` block) for the optional metrics.

## Verify before / after apply

- **Table mode.** KQL targets the shared `AzureDiagnostics` table
  (`log_analytics_destination_type = "AzureDiagnostics"`). If the workspace is in
  **Dedicated** mode, Foundry emits to `AIFoundryRequestResponse` with typed
  columns and the queries must be rewritten. Pull one sample row after go-live.
- **Provider version.** `enabled_log`, `enabled_metric`,
  `log_analytics_destination_type`, and the `_v2` rule are azurerm v4 shapes.
  `terraform validate` against your pin.
- **AC check:** run `verify_p1_1.sh` after apply + one test call per auth path.
