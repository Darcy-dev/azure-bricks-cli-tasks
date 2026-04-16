#!/bin/bash
# Post-deployment script: Add a user by email to the Databricks workspace
#
# Usage:
#   ./add-databricks-user.sh <workspace-url> <user-email>
#
# Example:
#   ./add-databricks-user.sh adb-7405608359153474.14.azuredatabricks.net user@company.com
set -euo pipefail

WORKSPACE_URL="${1:?Usage: $0 <workspace-url> <user-email>}"
USER_EMAIL="${2:?Missing user-email}"

TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

DATABRICKS_HOST="https://${WORKSPACE_URL}"

# Check if user already exists
EXISTING=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Users?filter=userName+eq+${USER_EMAIL}" \
  2>/dev/null || echo '{"Resources":[]}')

USER_ID=$(echo "$EXISTING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
resources = data.get('Resources', [])
print(resources[0]['id'] if resources else '')
" 2>/dev/null || echo "")

if [ -n "$USER_ID" ]; then
  echo "User ${USER_EMAIL} already exists (id=${USER_ID}), updating entitlements..."
  curl -sf -X PATCH \
    "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Users/${USER_ID}" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
      "Operations": [{
        "op": "replace",
        "path": "entitlements",
        "value": [
          {"value": "workspace-access"},
          {"value": "databricks-sql-access"},
          {"value": "allow-cluster-create"}
        ]
      }]
    }'
else
  echo "Adding user ${USER_EMAIL} to workspace..."
  curl -sf -X POST \
    "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Users" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:User\"],
      \"userName\": \"${USER_EMAIL}\",
      \"entitlements\": [
        {\"value\": \"workspace-access\"},
        {\"value\": \"databricks-sql-access\"},
        {\"value\": \"allow-cluster-create\"}
      ],
      \"active\": true
    }"
fi

echo ""
echo "Done. User ${USER_EMAIL} configured with: workspace-access, databricks-sql-access, allow-cluster-create"
