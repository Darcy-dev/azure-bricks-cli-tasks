#!/bin/bash
# Post-deployment script: Register the worker UMI in Databricks with entitlements
# Run after the Bicep deployment completes.
#
# Usage:
#   ./configure-databricks-entitlements.sh <workspace-url> <application-id> <display-name>
#
# Example:
#   ./configure-databricks-entitlements.sh \
#     adb-test-br-ifrisk.azuredatabricks.net \
#     $(az identity show -n umi-worker-southbr-dev-0001 -g rg-test-br-ifrisk --query clientId -o tsv) \
#     umi-worker-southbr-dev-0001
set -euo pipefail

WORKSPACE_URL="${1:?Usage: $0 <workspace-url> <application-id> <display-name>}"
APP_ID="${2:?Missing application-id}"
DISPLAY_NAME="${3:?Missing display-name}"

TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

DATABRICKS_HOST="https://${WORKSPACE_URL}"

# Check if service principal already exists
EXISTING=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/ServicePrincipals?filter=applicationId+eq+${APP_ID}" \
  2>/dev/null || echo '{"Resources":[]}')

SP_ID=$(echo "$EXISTING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
resources = data.get('Resources', [])
print(resources[0]['id'] if resources else '')
" 2>/dev/null || echo "")

if [ -n "$SP_ID" ]; then
  echo "Service principal exists (id=$SP_ID), updating entitlements..."
  curl -sf -X PATCH \
    "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/ServicePrincipals/${SP_ID}" \
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
  echo "Registering new service principal..."
  curl -sf -X POST \
    "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/ServicePrincipals" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"schemas\": [\"urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal\"],
      \"applicationId\": \"${APP_ID}\",
      \"displayName\": \"${DISPLAY_NAME}\",
      \"entitlements\": [
        {\"value\": \"workspace-access\"},
        {\"value\": \"databricks-sql-access\"},
        {\"value\": \"allow-cluster-create\"}
      ],
      \"active\": true
    }"
fi

echo ""
echo "Entitlements configured: workspace-access, databricks-sql-access, allow-cluster-create"

# ──────────────────────────────────────────────
# Add SP to the Databricks admins group
# ──────────────────────────────────────────────
echo "Looking up admins group..."

ADMIN_GROUP_RESPONSE=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups?filter=displayName+eq+admins" \
  2>/dev/null || echo '{"Resources":[]}')

ADMIN_GROUP_ID=$(echo "$ADMIN_GROUP_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
resources = data.get('Resources', [])
print(resources[0]['id'] if resources else '')
" 2>/dev/null || echo "")

if [ -z "$ADMIN_GROUP_ID" ]; then
  echo "ERROR: Could not find 'admins' group in Databricks workspace."
  exit 1
fi

# Re-fetch SP_ID in case SP was just created (POST branch doesn't capture it)
if [ -z "$SP_ID" ]; then
  REFETCH=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/ServicePrincipals?filter=applicationId+eq+${APP_ID}" \
    2>/dev/null || echo '{"Resources":[]}')

  SP_ID=$(echo "$REFETCH" | python3 -c "
import sys, json
data = json.load(sys.stdin)
resources = data.get('Resources', [])
print(resources[0]['id'] if resources else '')
" 2>/dev/null || echo "")
fi

if [ -z "$SP_ID" ]; then
  echo "ERROR: SP not found. Cannot add to admins group."
  exit 1
fi

echo "Adding SP (id=$SP_ID) to admins group (id=$ADMIN_GROUP_ID)..."

curl -sf -X PATCH \
  "${DATABRICKS_HOST}/api/2.0/preview/scim/v2/Groups/${ADMIN_GROUP_ID}" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"schemas\": [\"urn:ietf:params:scim:api:messages:2.0:PatchOp\"],
    \"Operations\": [{
      \"op\": \"add\",
      \"path\": \"members\",
      \"value\": [{
        \"value\": \"${SP_ID}\"
      }]
    }]
  }"

echo ""
echo "Done. SP added as admin with entitlements: workspace-access, databricks-sql-access, allow-cluster-create"
