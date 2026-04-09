# Azure Automation Runbooks

## Architecture

Runbooks are managed via Terraform using a `for_each` pattern driven by a JSON manifest (`terraform/runbooks.json`). Each entry maps a script filename to its Azure Automation metadata.

```
terraform/
├── modules/
│   └── automation-account/
│       ├── main.tf          # for_each over runbooks.json
│       ├── variables.tf     # module input variables
│       └── outputs.tf       # module outputs
├── environments/
│   ├── nonprod/
│   │   └── main.tf          # calls module with nonprod values (s00175nonprod, eastus)
│   └── prod/
│       └── main.tf          # calls module with prod values (s00175prod, eastus2)
├── runbooks.json            # manifest: filename -> {name, description, runbook_type}
├── sync_runbooks.py         # helper to keep manifest in sync
└── runbooks/
    ├── list-resource-groups.ps1
    ├── stop-idle-vms.ps1
    ├── cleanup-unused-disks.ps1
    ├── check-tag-compliance.ps1
    └── export-cost-report.ps1
```

Each environment has its own directory with isolated Terraform state, making it impossible to accidentally overwrite one environment with another.

## How the for_each Pattern Works

Instead of writing a separate `azurerm_automation_runbook` block per script, a single resource block iterates over `runbooks.json`:

```hcl
locals {
  runbooks = jsondecode(file("${path.module}/runbooks.json"))
}

resource "azurerm_automation_runbook" "this" {
  for_each = local.runbooks
  name     = each.value.name
  content  = file("${path.module}/runbooks/${each.key}")
  ...
}
```

Terraform addresses each runbook as `azurerm_automation_runbook.this["<filename>"]`.

## Adding a New Runbook

1. Create the script in `terraform/runbooks/` (e.g., `my-new-task.ps1`)
2. Run the sync script to auto-add it to the manifest:
   ```bash
   python3 terraform/sync_runbooks.py
   ```
   Or use the scaffold command:
   ```bash
   python3 terraform/sync_runbooks.py --new my-new-task.ps1
   ```
3. Edit `terraform/runbooks.json` to set a proper description
4. Deploy:
   ```bash
   cd terraform
   terraform plan
   terraform apply
   ```

## Removing a Runbook

1. Delete the script file from `terraform/runbooks/`
2. Remove the entry from `terraform/runbooks.json`
3. Run `terraform apply` — Terraform will destroy the runbook in Azure

## Sync Script Usage

```bash
# Default: scan runbooks/, add missing files to manifest
python3 terraform/sync_runbooks.py

# Validate: check manifest matches files (for CI pipelines)
python3 terraform/sync_runbooks.py --validate

# New: scaffold a runbook + add to manifest
python3 terraform/sync_runbooks.py --new <filename>
```

### Naming Convention

Filenames use kebab-case and map to PascalCase runbook names:

| Filename | Runbook Name |
|----------|-------------|
| `cleanup-unused-disks.ps1` | `Cleanup-UnusedDisks` |
| `check-tag-compliance.ps1` | `Check-TagCompliance` |

### Extension Mapping

| Extension | Runbook Type |
|-----------|-------------|
| `.ps1` | PowerShell72 |
| `.py` | Python3 |

## Deployment

Each environment is deployed from its own directory with isolated state:

```bash
# Non-prod
cd terraform/environments/nonprod
terraform init
terraform plan
terraform apply

# Prod
cd terraform/environments/prod
terraform init
terraform plan
terraform apply
```

The CI/CD pipeline (`pipelines/deploy-automation-account.yml`) deploys non-prod first, then prod, with environment gates for approval.

| Environment | Automation Account | Region | Resource Group |
|-------------|-------------------|--------|----------------|
| Non-Prod | s00175nonprod | eastus | rg-devops-agents |
| Prod | s00175prod | eastus2 | rg-devops-agents |

## Runbook Inventory

| Runbook | Description |
|---------|-------------|
| List-ResourceGroups | Lists all resource groups in the subscription |
| Stop-IdleVMs | Stops all running VMs in the subscription |
| Cleanup-UnusedDisks | Finds and removes unattached managed disks |
| Check-TagCompliance | Reports resources missing required tags |
| Export-CostReport | Exports 30-day cost/usage summary by service |
