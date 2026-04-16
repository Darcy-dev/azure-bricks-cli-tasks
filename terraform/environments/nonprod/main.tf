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
  subscription_id = "e1852036-5910-40d9-bd13-e2cc10a04110"
}

module "automation_account" {
  source = "../../modules/automation-account"

  subscription_id             = "e1852036-5910-40d9-bd13-e2cc10a04110"
  resource_group_name         = "rg-devops-agents"
  automation_account_name     = "s00175nonprod"
  automation_account_location = "eastus"
}

output "automation_account_id" {
  value = module.automation_account.automation_account_id
}

output "automation_account_name" {
  value = module.automation_account.automation_account_name
}

output "identity_principal_id" {
  value = module.automation_account.identity_principal_id
}

output "runbook_names" {
  value = module.automation_account.runbook_names
}
