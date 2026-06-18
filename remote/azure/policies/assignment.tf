# ---------------------------------------------------------------------------
# Assign the initiative using the AVM pattern module. AVM does not publish a
# module for policy *definitions*, only for *assignment*, so this is the one
# part of the workflow that uses a Verified Module.
# ---------------------------------------------------------------------------
module "initiative_assignment" {
  source  = "Azure/avm-ptn-policyassignment/azurerm"
  version = "0.2.0"

  count = var.create_assignment ? 1 : 0

  name                 = var.assignment_name
  display_name         = local.initiative.displayName
  description          = local.initiative.description
  location             = var.location
  scope                = local.assignment_scope
  policy_definition_id = azurerm_policy_set_definition.this.id
  enforce              = var.enforcement_mode
}
