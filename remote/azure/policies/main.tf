locals {
  # All custom policy definition JSON files live in per-service subfolders.
  # Exclude the initiatives/ folder, which holds the policy set definition.
  policy_files = [
    for f in fileset(path.module, "*/*.json") : f
    if dirname(f) != "initiatives"
  ]

  # Key each definition by its globally unique `name` (file basenames collide
  # across services, e.g. core-cn05-no-public-network.json in two folders).
  policy_definitions = {
    for f in local.policy_files :
    jsondecode(file("${path.module}/${f}")).name => jsondecode(file("${path.module}/${f}")).properties
  }

  # Initiative (policy set definition) source.
  initiative_raw = jsondecode(file("${path.module}/initiatives/ccc-avm-initiative.json"))
  initiative     = local.initiative_raw.properties

  # Members are either custom definitions created in this module (their
  # policyDefinitionId carries the {scope} placeholder) or Azure built-in
  # governance policies (a literal /providers/... definition ID). The built-in
  # "Policy-only governance baseline" covers CCC controls that AVM cannot
  # configure (CN06 trust perimeter, CN11 key rotation, CN04 resource logs,
  # CN14 backups) and is toggled by var.include_governance_baseline.
  selected_members = [
    for m in local.initiative.policyDefinitions : m
    if var.include_governance_baseline || strcontains(m.policyDefinitionId, "{scope}")
  ]

  selected_group_names = toset(flatten([for m in local.selected_members : try(m.groupNames, [])]))
  selected_groups = [
    for g in local.initiative.policyDefinitionGroups : g
    # Keep referenced groups plus the intentionally member-less gap group.
    if contains(local.selected_group_names, g.name) || g.name == "CCC.SvlsComp.CN02"
  ]

  # Override the governance parameter defaults from input variables so operators
  # can tune the trust perimeter / rotation cadence without editing the JSON.
  initiative_parameters = jsonencode(merge(
    local.initiative.parameters,
    {
      allowedLocations       = merge(local.initiative.parameters.allowedLocations, { defaultValue = length(var.allowed_locations) > 0 ? var.allowed_locations : [var.location] })
      allowedLocationsEffect = merge(local.initiative.parameters.allowedLocationsEffect, { defaultValue = var.allowed_locations_effect })
      keyRotationMaximumDays = merge(local.initiative.parameters.keyRotationMaximumDays, { defaultValue = var.key_rotation_maximum_days })
      logRetentionDays       = merge(local.initiative.parameters.logRetentionDays, { defaultValue = tostring(var.governance_log_retention_days) })
    }
  ))

  # The scope the initiative is assigned to (defaults to the provider subscription).
  assignment_scope = coalesce(var.assignment_scope, "/subscriptions/${var.subscription_id}")
}

# ---------------------------------------------------------------------------
# Custom policy definitions (one per JSON file under the service subfolders).
# No AVM module exists for policy/initiative *definitions*, so these use the
# native azurerm resources. They are assigned via the AVM pattern module below.
# ---------------------------------------------------------------------------
resource "azurerm_policy_definition" "this" {
  for_each = local.policy_definitions

  name         = each.key
  policy_type  = "Custom"
  mode         = each.value.mode
  display_name = each.value.displayName
  description  = try(each.value.description, null)

  management_group_id = var.management_group_id

  metadata    = jsonencode(each.value.metadata)
  parameters  = jsonencode(each.value.parameters)
  policy_rule = jsonencode(each.value.policyRule)
}

# ---------------------------------------------------------------------------
# Initiative (policy set definition) bundling every custom definition above.
# References are built from the initiative JSON; each member's definition name
# is the last segment of its placeholder policyDefinitionId, resolved to the
# real resource ID created above.
# ---------------------------------------------------------------------------
resource "azurerm_policy_set_definition" "this" {
  name         = local.initiative_raw.name
  policy_type  = "Custom"
  display_name = local.initiative.displayName
  description  = local.initiative.description

  management_group_id = var.management_group_id

  metadata = jsonencode(local.initiative.metadata)

  # Governance parameters (allowed locations, rotation cadence, log retention)
  # only apply when the built-in governance baseline is included.
  parameters = var.include_governance_baseline ? local.initiative_parameters : null

  dynamic "policy_definition_reference" {
    for_each = local.selected_members
    content {
      # Custom members resolve to the definitions created above; built-in
      # governance members use their literal Azure definition ID verbatim.
      policy_definition_id = strcontains(policy_definition_reference.value.policyDefinitionId, "{scope}") ? azurerm_policy_definition.this[basename(policy_definition_reference.value.policyDefinitionId)].id : policy_definition_reference.value.policyDefinitionId
      reference_id         = policy_definition_reference.value.policyDefinitionReferenceId
      policy_group_names   = try(policy_definition_reference.value.groupNames, null)
      parameter_values     = try(jsonencode(policy_definition_reference.value.parameters), null)
    }
  }

  dynamic "policy_definition_group" {
    for_each = local.selected_groups
    content {
      name         = policy_definition_group.value.name
      display_name = try(policy_definition_group.value.displayName, null)
      description  = try(policy_definition_group.value.description, null)
      category     = try(policy_definition_group.value.category, null)
    }
  }
}
