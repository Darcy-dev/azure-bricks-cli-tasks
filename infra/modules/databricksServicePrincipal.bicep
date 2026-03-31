param location string
param databricksWorkspaceName string
param servicePrincipalObjectId string
param servicePrincipalApplicationId string
param servicePrincipalDisplayName string
param deploymentScriptIdentityId string

resource workspace 'Microsoft.Databricks/workspaces@2024-05-01' existing = {
  name: databricksWorkspaceName
}

// ── Azure RBAC: Contributor on the Databricks workspace ──
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource spRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, servicePrincipalObjectId, contributorRoleId)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: servicePrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}

// ── Databricks SCIM: Register SP with entitlements ──
// The deploymentScriptIdentityId must reference a User Assigned Managed Identity
// with Contributor on this resource group (required for script infrastructure).
resource registerServicePrincipal 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'register-databricks-sp-${uniqueString(servicePrincipalApplicationId)}'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentScriptIdentityId}': {}
    }
  }
  properties: {
    azCliVersion: '2.63.0'
    retentionInterval: 'PT1H'
    timeout: 'PT15M'
    cleanupPreference: 'OnSuccess'
    scriptContent: '''#!/bin/bash
set -euo pipefail

echo "Waiting for RBAC propagation..."
sleep 60

# Acquire Databricks AAD token with retries
TOKEN=""
for i in $(seq 1 10); do
  TOKEN=$(az account get-access-token \
    --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
    --query accessToken -o tsv 2>/dev/null) && break
  echo "Retry $i/10 - waiting for Databricks token..."
  sleep 30
done

if [ -z "${TOKEN:-}" ]; then
  echo "ERROR: Failed to acquire Databricks AAD token"
  exit 1
fi

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

echo "Service principal configured successfully."
echo '{"result":"success"}' > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      { name: 'WORKSPACE_URL', value: workspace.properties.workspaceUrl }
      { name: 'APP_ID', value: servicePrincipalApplicationId }
      { name: 'DISPLAY_NAME', value: servicePrincipalDisplayName }
    ]
  }
  dependsOn: [spRoleAssignment]
}
