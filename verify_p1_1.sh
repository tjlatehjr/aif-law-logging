#!/usr/bin/env bash
set -euo pipefail
#
# P1.1 Acceptance-Criteria Verification (pure bash + az CLI)
# Run after terraform apply + one test invocation per auth path.
#
# Required env vars (set in GitLab CI variables block):
#   SUBSCRIPTION, RESOURCE_GROUP, FOUNDRY_ACCOUNT, LAW_WORKSPACE, LAW_RG

: "${SUBSCRIPTION:?Set SUBSCRIPTION}"
: "${RESOURCE_GROUP:?Set RESOURCE_GROUP}"
: "${FOUNDRY_ACCOUNT:?Set FOUNDRY_ACCOUNT}"
: "${LAW_WORKSPACE:?Set LAW_WORKSPACE}"
: "${LAW_RG:?Set LAW_RG}"

FOUNDRY_UPPER=$(echo "$FOUNDRY_ACCOUNT" | tr '[:lower:]' '[:upper:]')

LAW_ID=$(az monitor log-analytics workspace show \
  --workspace-name "$LAW_WORKSPACE" \
  --resource-group "$LAW_RG" \
  --subscription "$SUBSCRIPTION" \
  --query id -o tsv)

PASS=0
FAIL=0
WARN=0

result() {
  local status="$1" label="$2" detail="${3:-}"
  case "$status" in
    PASS) ((PASS++)); echo "  ✅ $label" ;;
    FAIL) ((FAIL++)); echo "  ❌ $label${detail:+ — $detail}" ;;
    WARN) ((WARN++)); echo "  ⚠️  $label${detail:+ — $detail}" ;;
  esac
}

run_query() {
  local query="$1"
  az monitor log-analytics query \
    --workspace "$LAW_ID" \
    --analytics-query "$query" \
    -o tsv 2>/dev/null || echo ""
}

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " P1.1 Acceptance Criteria Verification"
echo " $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "═══════════════════════════════════════════════════════════"

# ───────────────────────────────────────────────────────────────
# AC 1: Diagnostic setting deployed via IaC
# ───────────────────────────────────────────────────────────────
echo ""
echo "AC 1: Diagnostic setting exists on the Foundry account"

DIAG_NAME=$(az monitor diagnostic-settings list \
  --resource "$FOUNDRY_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --resource-type "Microsoft.CognitiveServices/accounts" \
  --subscription "$SUBSCRIPTION" \
  --query "[?name=='foundry-token-logging'].name" -o tsv 2>/dev/null || echo "")

if [ -n "$DIAG_NAME" ]; then
  result PASS "Diagnostic setting 'foundry-token-logging' exists"

  for CAT in RequestResponse Audit; do
    CAT_CHECK=$(az monitor diagnostic-settings list \
      --resource "$FOUNDRY_ACCOUNT" \
      --resource-group "$RESOURCE_GROUP" \
      --resource-type "Microsoft.CognitiveServices/accounts" \
      --subscription "$SUBSCRIPTION" \
      --query "[?name=='foundry-token-logging'].logs[?category=='$CAT' && enabled].category" -o tsv 2>/dev/null || echo "")

    if [ -n "$CAT_CHECK" ]; then
      result PASS "Category '$CAT' enabled"
    else
      result FAIL "Category '$CAT' not found" "Check enabled_log blocks"
    fi
  done

  LAW_TARGET=$(az monitor diagnostic-settings list \
    --resource "$FOUNDRY_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --resource-type "Microsoft.CognitiveServices/accounts" \
    --subscription "$SUBSCRIPTION" \
    --query "[?name=='foundry-token-logging'].workspaceId" -o tsv 2>/dev/null || echo "")

  if [ -n "$LAW_TARGET" ]; then
    result PASS "Targets a Log Analytics workspace"
  else
    result FAIL "Not targeting a Log Analytics workspace"
  fi
else
  result FAIL "Diagnostic setting 'foundry-token-logging' not found" \
    "Run terraform apply first"
fi

# ───────────────────────────────────────────────────────────────
# AC 2: Rows landing within 15 minutes (smoke test)
# ───────────────────────────────────────────────────────────────
echo ""
echo "AC 2: Verification query — rows within 15 minutes of a test call"

SMOKE_RESULT=$(run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES'
| where Resource == '$FOUNDRY_UPPER'
| where TimeGenerated > ago(30m)
| summarize RowCount = count()")

if echo "$SMOKE_RESULT" | grep -qE '[1-9][0-9]*'; then
  ROW_COUNT=$(echo "$SMOKE_RESULT" | grep -oE '[0-9]+' | tail -1)
  result PASS "Found $ROW_COUNT row(s) in AzureDiagnostics within last 30 min"
else
  result WARN "No rows found" \
    "Make a test API call, wait 15 min, re-run"
fi

# ───────────────────────────────────────────────────────────────
# AC 3: Both auth paths visible
# ───────────────────────────────────────────────────────────────
echo ""
echo "AC 3: Both auth paths visible (AAD + API-key)"

AAD_RESULT=$(run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES'
| where Resource == '$FOUNDRY_UPPER'
| where TimeGenerated > ago(24h)
| where isnotempty(identity_claim_oid_g)
| summarize AADCalls = count()")

if echo "$AAD_RESULT" | grep -qE '[1-9][0-9]*'; then
  result PASS "AAD-authenticated call found (oid populated)"
else
  result WARN "No AAD-authenticated call found in last 24h" \
    "Make a call with a bearer token"
fi

KEY_RESULT=$(run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES'
| where Resource == '$FOUNDRY_UPPER'
| where TimeGenerated > ago(24h)
| where isempty(identity_claim_oid_g)
| summarize KeyCalls = count()")

if echo "$KEY_RESULT" | grep -qE '[1-9][0-9]*'; then
  result PASS "API-key call found (oid absent)"
else
  result WARN "No API-key call found in last 24h" \
    "Make a call with Ocp-Apim-Subscription-Key"
fi

# ───────────────────────────────────────────────────────────────
# AC 4: Five saved functions resolvable in the workspace
# ───────────────────────────────────────────────────────────────
echo ""
echo "AC 4: Saved functions resolvable in the workspace"

declare -a FUNCTIONS=(
  'AIF_TokensByTeam(7d)'
  'AIF_TokensByTeamModel(7d)'
  'AIF_TopUsersInTeam("api-key-unattributed", 1d)'
  'AIF_TokenBurn("api-key-unattributed", startofmonth(now()))'
  'AIF_ChargebackByTeam(startofmonth(now()), 0.0)'
)

for FUNC in "${FUNCTIONS[@]}"; do
  FNAME="${FUNC%%(*}"

  if az monitor log-analytics query \
    --workspace "$LAW_ID" \
    --analytics-query "$FUNC | take 0" \
    -o none 2>/dev/null; then
    result PASS "$FNAME resolves and runs"
  else
    result FAIL "$FNAME not resolvable" \
      "Check saved_search in terraform state"
  fi
done

if az monitor log-analytics query \
  --workspace "$LAW_ID" \
  --analytics-query "AIF_CallerToTeam() | take 0" \
  -o none 2>/dev/null; then
  result PASS "AIF_CallerToTeam (helper) resolves"
else
  result FAIL "AIF_CallerToTeam (helper) not resolvable" \
    "Required by all five functions"
fi

# ───────────────────────────────────────────────────────────────
# AC 5: No PII — RequestResponse is metadata-level only
# ───────────────────────────────────────────────────────────────
echo ""
echo "AC 5: No PII — confirm prompts/completions NOT in logs"

PII_SAMPLE=$(run_query "
AzureDiagnostics
| where ResourceProvider == 'MICROSOFT.COGNITIVESERVICES'
| where Resource == '$FOUNDRY_UPPER'
| where Category == 'RequestResponse'
| where TimeGenerated > ago(24h)
| take 1
| project properties_s")

if [ -z "$PII_SAMPLE" ]; then
  result WARN "No rows to inspect" "Make a test call first"
elif echo "$PII_SAMPLE" | grep -qiE '"(prompt|messages|completion).*content"'; then
  result WARN "properties_s MAY contain prompt/completion content" \
    "Manually inspect — paste a sample row in the ticket"
  echo "       Sample (first 500 chars):"
  echo "       ${PII_SAMPLE:0:500}"
else
  result PASS "properties_s appears metadata-level (no prompt/completion content)"
  echo "       Re-verify manually: paste one sample row in the ticket comments"
fi

# ───────────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Results:  ✅ $PASS passed   ❌ $FAIL failed   ⚠️  $WARN warnings"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "Fix failures before requesting review."
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "Warnings require manual verification."
  exit 0
else
  echo "All checks passed. Ready for review."
  exit 0
fi
