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

locals {
  runbooks = jsondecode(file("${path.module}/runbooks.json"))
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
