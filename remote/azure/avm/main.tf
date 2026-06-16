locals {
  storage_account_name = "avmstor${var.instance_id}"
  default_container    = "ccc-avm-test-container-${var.instance_id}"
  key_vault_name       = "avmkv${var.instance_id}"
  log_analytics_name   = "avmlaw${var.instance_id}"
  virtual_network_name = "avmvnet${var.instance_id}"
  function_plan_name   = "avmplan${var.instance_id}"
  function_app_name    = "avmfunc${var.instance_id}"
  virtual_machine_name = "avmvm${var.instance_id}"
}

data "azurerm_client_config" "current" {}

# Resource group for AVM testing.
# Managed as a resource to allow creation, but we import it if it already exists
# because it is excluded from the automated cleanup (nuke).
resource "azurerm_resource_group" "this" {
  name     = "avm-testing"
  location = var.location
}
