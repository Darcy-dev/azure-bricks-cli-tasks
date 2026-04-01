#!/bin/bash
# Post-deployment script: Create a Databricks cluster
#
# Usage:
#   ./create-databricks-cluster.sh <workspace-url> <cluster-name> [node-type] [num-workers]
#
# Example:
#   ./create-databricks-cluster.sh adb-7405608359153474.14.azuredatabricks.net cluster-test-br-ifrisk
#   ./create-databricks-cluster.sh adb-7405608359153474.14.azuredatabricks.net my-cluster Standard_DS3_v2 2
set -euo pipefail

WORKSPACE_URL="${1:?Usage: $0 <workspace-url> <cluster-name> [node-type] [num-workers]}"
CLUSTER_NAME="${2:?Missing cluster-name}"
NODE_TYPE="${3:-Standard_DS3_v2}"
NUM_WORKERS="${4:-1}"

TOKEN=$(az account get-access-token \
  --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d \
  --query accessToken -o tsv)

DATABRICKS_HOST="https://${WORKSPACE_URL}"

# Check if cluster with same name already exists
EXISTING=$(curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  "${DATABRICKS_HOST}/api/2.0/clusters/list" \
  2>/dev/null || echo '{"clusters":[]}')

CLUSTER_ID=$(echo "$EXISTING" | python3 -c "
import sys, json
data = json.load(sys.stdin)
clusters = data.get('clusters', [])
match = [c for c in clusters if c.get('cluster_name') == '${CLUSTER_NAME}']
print(match[0]['cluster_id'] if match else '')
" 2>/dev/null || echo "")

if [ -n "$CLUSTER_ID" ]; then
  echo "Cluster '${CLUSTER_NAME}' already exists (id=${CLUSTER_ID}). Skipping creation."
else
  echo "Creating cluster '${CLUSTER_NAME}'..."

  # Get the latest Databricks Runtime LTS version
  SPARK_VERSION=$(curl -sf \
    -H "Authorization: Bearer $TOKEN" \
    "${DATABRICKS_HOST}/api/2.0/clusters/spark-versions" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
versions = data.get('versions', [])
lts = [v for v in versions if 'LTS' in v.get('name', '') and 'ML' not in v.get('name', '') and 'GPU' not in v.get('name', '') and 'Photon' not in v.get('name', '')]
lts.sort(key=lambda v: v['key'], reverse=True)
print(lts[0]['key'] if lts else '15.4.x-scala2.12')
" 2>/dev/null)

  echo "Using Spark version: ${SPARK_VERSION}"

  RESPONSE=$(curl -sf -X POST \
    "${DATABRICKS_HOST}/api/2.0/clusters/create" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"cluster_name\": \"${CLUSTER_NAME}\",
      \"spark_version\": \"${SPARK_VERSION}\",
      \"node_type_id\": \"${NODE_TYPE}\",
      \"num_workers\": ${NUM_WORKERS},
      \"autotermination_minutes\": 30,
      \"spark_conf\": {
        \"spark.databricks.cluster.profile\": \"serverless\",
        \"spark.databricks.repl.allowedLanguages\": \"python,sql,scala,r\"
      },
      \"azure_attributes\": {
        \"first_on_demand\": 1,
        \"availability\": \"ON_DEMAND_AZURE\"
      }
    }")

  CLUSTER_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cluster_id',''))" 2>/dev/null || echo "")

  if [ -n "$CLUSTER_ID" ]; then
    echo "Cluster created successfully. ID: ${CLUSTER_ID}"
  else
    echo "ERROR: Failed to create cluster."
    echo "$RESPONSE"
    exit 1
  fi
fi

echo ""
echo "Done. Cluster '${CLUSTER_NAME}' (node_type=${NODE_TYPE}, workers=${NUM_WORKERS})"
