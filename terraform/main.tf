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

import {
  to = azurerm_automation_account.this
  id = "/subscriptions/e1852036-5910-40d9-bd13-e2cc10a04110/resourceGroups/rg-devops-agents/providers/Microsoft.Automation/automationAccounts/s00175nonprod"
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

locals {
  runbooks = jsondecode(file("${path.module}/runbooks.json"))
}

import {
  to = azurerm_automation_runbook.this["list-resource-groups.ps1"]
  id = "/subscriptions/e1852036-5910-40d9-bd13-e2cc10a04110/resourceGroups/rg-devops-agents/providers/Microsoft.Automation/automationAccounts/s00175nonprod/runbooks/List-ResourceGroups"
}

import {
  to = azurerm_automation_runbook.this["stop-idle-vms.ps1"]
  id = "/subscriptions/e1852036-5910-40d9-bd13-e2cc10a04110/resourceGroups/rg-devops-agents/providers/Microsoft.Automation/automationAccounts/s00175nonprod/runbooks/Stop-IdleVMs"
}

import {
  to = azurerm_automation_runbook.this["cleanup-unused-disks.ps1"]
  id = "/subscriptions/e1852036-5910-40d9-bd13-e2cc10a04110/resourceGroups/rg-devops-agents/providers/Microsoft.Automation/automationAccounts/s00175nonprod/runbooks/Cleanup-UnusedDisks"
}

import {
  to = azurerm_automation_runbook.this["check-tag-compliance.ps1"]
  id = "/subscriptions/e1852036-5910-40d9-bd13-e2cc10a04110/resourceGroups/rg-devops-agents/providers/Microsoft.Automation/automationAccounts/s00175nonprod/runbooks/Check-TagCompliance"
}

import {
  to = azurerm_automation_runbook.this["export-cost-report.ps1"]
  id = "/subscriptions/e1852036-5910-40d9-bd13-e2cc10a04110/resourceGroups/rg-devops-agents/providers/Microsoft.Automation/automationAccounts/s00175nonprod/runbooks/Export-CostReport"
}

resource "azurerm_automation_runbook" "this" {
  for_each                = local.runbooks
  name                    = each.value.name
  location                = var.automation_account_location
  resource_group_name     = data.azurerm_resource_group.existing.name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = each.value.runbook_type
  description             = each.value.description
  content                 = file("${path.module}/runbooks/${each.key}")
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

output "runbook_names" {
  value = [for rb in azurerm_automation_runbook.this : rb.name]
}
