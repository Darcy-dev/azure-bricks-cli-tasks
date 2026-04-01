# Infrastructure as Code — Azure Databricks Workspace

## IaC Structure

```
infra/
├── main.bicep                                  # Subscription-scoped orchestrator
├── main.dev.bicepparam                          # Parameter values for the dev stamp
├── modules/
│   ├── resourceGroup.bicep                     # Resource group: rg-dev-br-ifrisk
│   ├── networkSecurityGroups.bicep             # 2 NSGs with 6 mandatory Databricks rules each
│   ├── virtualNetwork.bicep                    # VNet + public/private subnets with delegation
│   ├── databricks.bicep                        # Databricks workspace (premium, VNet-injected)
│   ├── userAssignedIdentity.bicep              # User Assigned Managed Identity (worker)
│   └── databricksServicePrincipal.bicep        # Contributor role assignment on workspace
└── scripts/
    ├── configure-databricks-entitlements.sh    # Post-deploy: register SP with SCIM entitlements + admin
    ├── add-databricks-user.sh                  # Utility: add user by email to workspace
    ├── create-databricks-cluster.sh            # Post-deploy: create a Databricks cluster
    └── create-databricks-pat.sh               # Post-deploy: create PAT token (60-day expiry)
```

## Deployment Flow

```
main.bicep (subscription scope)
│
├─► resourceGroup.bicep
│       └─ rg-dev-br-ifrisk
│
├─► networkSecurityGroups.bicep          (depends on: resourceGroup)
│       ├─ nsg-public-databricks         (6 inbound/outbound rules)
│       └─ nsg-private-databricks        (6 inbound/outbound rules)
│
├─► virtualNetwork.bicep                 (depends on: NSGs)
│       ├─ vn-dev-br-ifrisk             (172.24.58.0/23)
│       ├─ sn-public-databricks          (172.24.58.0/24)
│       └─ sn-private-databricks         (172.24.59.0/24)
│
├─► userAssignedIdentity.bicep           (depends on: resourceGroup)
│       └─ umi-worker-southbr-dev-0001
│
├─► databricks.bicep                     (depends on: VNet)
│       └─ adb-dev-br-ifrisk            (premium, secure cluster connectivity)
│
└─► databricksServicePrincipal.bicep     (depends on: databricks, workerIdentity)
        └─ Contributor role assignment on workspace
```

## Network Layout

| Resource              | Name                    | CIDR             |
|-----------------------|-------------------------|------------------|
| VNet                  | vn-dev-br-ifrisk        | 172.24.58.0/23   |
| Public subnet (host)  | sn-public-databricks    | 172.24.58.0/24   |
| Private subnet (container) | sn-private-databricks | 172.24.59.0/24 |

### Subnet Configuration

Both subnets include:
- **Delegation**: `Microsoft.Databricks/workspaces`
- **Service endpoints**: `Microsoft.Storage.Global`, `Microsoft.Sql`, `Microsoft.EventHub`
- **NSG**: Attached with all 6 mandatory Databricks security rules

### NSG Rules (applied to both subnets)

| Rule                          | Direction | Port | Protocol | Source/Dest        |
|-------------------------------|-----------|------|----------|--------------------|
| worker-to-worker-inbound      | Inbound   | *    | *        | VNet → VNet        |
| worker-to-worker-outbound     | Outbound  | *    | *        | VNet → VNet        |
| worker-to-databricks-webapp   | Outbound  | 443  | TCP      | VNet → AzureDatabricks |
| worker-to-sql                 | Outbound  | 3306 | TCP      | VNet → Sql         |
| worker-to-storage             | Outbound  | 443  | TCP      | VNet → Storage     |
| worker-to-eventhub            | Outbound  | 9093 | TCP      | VNet → EventHub    |

## Service Principal

| Property      | Value                                    |
|---------------|------------------------------------------|
| Display Name  | umi-worker-southbr-dev-0001              |
| Client ID     | 994f9c0c-c264-47ca-8ff8-14bbb27c21df    |
| Principal ID  | 2aa6472a-eebd-41ae-929d-6b22432f3ddb    |
| Azure RBAC    | Contributor on adb-dev-br-ifrisk         |
| Entitlements  | workspace-access, databricks-sql-access, allow-cluster-create |

## Deployment Commands

### Deploy infrastructure

```bash
az login
az deployment sub create \
  --location brazilsouth \
  --template-file infra/main.bicep \
  --parameters infra/main.dev.bicepparam
```

### What-if (plan)

```bash
az deployment sub what-if \
  --location brazilsouth \
  --template-file infra/main.bicep \
  --parameters infra/main.dev.bicepparam
```

### Post-deployment scripts

```bash
# Register SP with Databricks SCIM entitlements + admin group
./infra/scripts/configure-databricks-entitlements.sh \
  <workspace-url> <client-id> <display-name>

# Create a Databricks cluster
./infra/scripts/create-databricks-cluster.sh \
  <workspace-url> <cluster-name>

# Create a PAT token (default: 60 days)
./infra/scripts/create-databricks-pat.sh \
  <workspace-url> <token-comment>
```

## Errors Encountered During Deployment

### 1. SubnetHasBothRegionalAndGlobalStorageServiceEndpointsTogether

**Error:**
```
Subnet sn-public-databricks has ServiceEndpoint entries for both
'Microsoft.Storage' and 'Microsoft.Storage.Global' together.
Please use either one of them at a time.
```

**Cause:** Both `Microsoft.Storage` (regional) and `Microsoft.Storage.Global` were defined as
service endpoints on the same subnet. Azure does not allow both simultaneously.

**Fix:** Removed `Microsoft.Storage` and kept only `Microsoft.Storage.Global`, which is the
superset that covers both regional and global storage access.

### 2. Service Principal Not Found in Subscription

**Error:**
```
Resource '08423185-e12b-491f-81bc-35bdc0c2a6a2' does not exist or one of its
queried reference-property objects are not present.
```

**Cause:** The original application ID (`08423185-e12b-491f-81bc-35bdc0c2a6a2`) referenced a
service principal from a production subscription we did not have access to.

**Fix:** Refactored the IaC to create a new User Assigned Managed Identity
(`umi-worker-southbr-dev-0001`) as part of the Bicep deployment itself, eliminating the dependency
on a pre-existing service principal. The module `userAssignedIdentity.bicep` was added and the
`databricksServicePrincipal.bicep` module was simplified to use the UMI's `principalId` output
directly.

### 3. Role Assignment Unsupported in What-If Preview

**Diagnostic:**
```
Changes to the resource cannot be analyzed because its resource ID or API version
cannot be calculated until the deployment is under way.
```

**Cause:** The role assignment resource ID depends on the UMI's `principalId`, which is only
available after the identity is created. Azure what-if cannot preview resources whose IDs depend
on runtime values.

**Impact:** None — this is a known limitation of what-if. The role assignment deploys correctly.
