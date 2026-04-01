terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

resource "azurerm_automation_account" "this" {
  name                = var.automation_account_name
  location            = var.automation_account_location
  resource_group_name = data.azurerm_resource_group.existing.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_automation_runbook" "list_resource_groups" {
  name                    = "List-ResourceGroups"
  location                = var.automation_account_location
  resource_group_name     = data.azurerm_resource_group.existing.name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell72"
  description             = "Lists all resource groups in the subscription"

  content = file("${path.module}/runbooks/list-resource-groups.ps1")
}

resource "azurerm_automation_runbook" "stop_idle_vms" {
  name                    = "Stop-IdleVMs"
  location                = var.automation_account_location
  resource_group_name     = data.azurerm_resource_group.existing.name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell72"
  description             = "Stops all running VMs in the subscription"

  content = file("${path.module}/runbooks/stop-idle-vms.ps1")
}

output "automation_account_id" {
  value = azurerm_automation_account.this.id
}

output "automation_account_name" {
  value = azurerm_automation_account.this.name
}

output "identity_principal_id" {
  value = azurerm_automation_account.this.identity[0].principal_id
}
