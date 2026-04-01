#!/bin/bash
# Post-deployment script: Create a Databricks Personal Access Token (PAT)
#
# Usage:
#   ./create-databricks-pat.sh <workspace-url> <token-comment> [lifetime-seconds]
#
# Example:
#   ./create-databricks-pat.sh adb-7405608359153474.14.azuredatabricks.net pipeline-token-dev
#   ./create-databricks-pat.sh adb-7405608359153474.14.azuredatabricks.net pipeline-token-dev 5184000
set -euo pipefail

WORKSPACE_URL="${1:?Usage: $0 <workspace-url> <token-comment> [lifetime-seconds]}"
TOKEN_COMMENT="${2:?Missing token-comment}"
LIFETIME_SECONDS="${3:-5184000}" # Default: 60 days (60 * 24 * 60 * 60)

TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

DATABRICKS_HOST="https://${WORKSPACE_URL}"

echo "Creating PAT token (comment='${TOKEN_COMMENT}', lifetime=${LIFETIME_SECONDS}s / $((LIFETIME_SECONDS / 86400)) days)..."

RESPONSE=$(curl -sf -X POST \
  "${DATABRICKS_HOST}/api/2.0/token/create" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"comment\": \"${TOKEN_COMMENT}\",
    \"lifetime_seconds\": ${LIFETIME_SECONDS}
  }")

TOKEN_VALUE=$(echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('token_value', ''))
" 2>/dev/null || echo "")

if [ -z "$TOKEN_VALUE" ]; then
  echo "ERROR: Failed to create PAT token."
  echo "$RESPONSE"
  exit 1
fi

echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
info = data.get('token_info', {})
print(f\"Token ID:    {info.get('token_id', 'N/A')}\")
print(f\"Comment:     {info.get('comment', 'N/A')}\")
print(f\"Expiry (ms): {info.get('expiry_time', 'N/A')}\")
" 2>/dev/null

TOKEN_BASE64=$(echo -n "$TOKEN_VALUE" | base64)

echo ""
echo "Done. PAT token created successfully."
echo "WARNING: The token value is shown only once. Store it securely."
echo "Token: ${TOKEN_VALUE}"
echo "Token (base64): ${TOKEN_BASE64}"
