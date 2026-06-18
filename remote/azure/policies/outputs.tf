output "policy_definition_ids" {
  description = "Map of custom policy definition name => resource ID for every definition created."
  value       = { for k, v in azurerm_policy_definition.this : k => v.id }
}

output "policy_set_definition_id" {
  description = "Resource ID of the CCC AVM guardrails initiative (policy set definition)."
  value       = azurerm_policy_set_definition.this.id
}

output "assignment_id" {
  description = "Resource ID of the initiative assignment, or null when create_assignment is false."
  value       = try(module.initiative_assignment[0].resource_id, null)
}
