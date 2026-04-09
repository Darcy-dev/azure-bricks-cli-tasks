variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group name"
  type        = string
}

variable "automation_account_location" {
  description = "Location for the Automation Account"
  type        = string
}

variable "automation_account_name" {
  description = "Name of the Automation Account"
  type        = string
}
