# ---------------------------------------------------------------------------
# Serverless function backing identity + RBAC. The Flex Consumption app reads
# and writes its deployment package on the GOVERNED storage account's
# deploymentpackage container using this user-assigned identity (no account
# keys, no separate public storage account). The container itself is created on
# the governed account over the control plane (module.storage_account
# containers), so the account stays fully private.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "function" {
  name                = "${local.function_app_name}-uami"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
}

resource "azurerm_role_assignment" "function_blob" {
  scope                = module.storage_account.resource_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function.principal_id
}

resource "time_sleep" "wait_for_function_rbac" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.function_blob]
}

# ---------------------------------------------------------------------------
# Serverless function (avm-res-web-site) — Flex Consumption, VNet-integrated,
# inbound private endpoint resolved via private DNS.
# ---------------------------------------------------------------------------
module "serverless_function" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "0.22.0"

  location  = var.location
  name      = local.function_app_name
  parent_id = azurerm_resource_group.this.id

  kind                     = "functionapp"
  os_type                  = "Linux"
  service_plan_resource_id = module.app_service_plan.resource_id

  function_app_uses_fc1 = var.function_app_uses_fc1
  fc1_runtime_name      = "dotnet-isolated"
  fc1_runtime_version   = "8.0"

  client_certificate_enabled    = var.client_certificate_enabled
  client_certificate_mode       = var.client_certificate_mode
  https_only                    = var.https_only
  maximum_instance_count        = var.maximum_instance_count
  public_network_access_enabled = var.public_network_access_enabled
  site_config                   = var.site_config
  managed_identities = {
    system_assigned            = var.managed_identities.system_assigned
    user_assigned_resource_ids = [azurerm_user_assigned_identity.function.id]
  }

  # Outbound VNet integration so vnet_route_all egress policy takes effect.
  virtual_network_subnet_id = module.virtual_network.subnets["functions"].resource_id

  # Flex Consumption backing deployment container, accessed via the pre-authorised
  # user-assigned identity (no storage account keys).
  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "https://${local.storage_account_name}.blob.core.windows.net/deploymentpackage"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.function.id

  # Function app resource logs (FunctionAppLogs) + metrics to the central Log
  # Analytics workspace, satisfying CCC.Core.CN04 (log all access and changes).
  diagnostic_settings = {
    to_law = {
      name                  = "diag-${local.function_app_name}"
      workspace_resource_id = module.log_analytics_workspace.resource_id
      logs = [
        { category_group = "allLogs" }
      ]
      metrics = [
        { category = "AllMetrics" }
      ]
    }
  }

  # Inbound private endpoint for the function app, resolved via private DNS.
  private_endpoints = {
    sites = {
      name                            = "pe-${local.function_app_name}-sites"
      private_service_connection_name = "pse-${local.function_app_name}-sites"
      subnet_resource_id              = module.virtual_network.subnets["pe"].resource_id
      subresource_name                = "sites"
      private_dns_zone_resource_ids   = [module.private_dns["sites"].resource_id]
    }
  }

  depends_on = [time_sleep.wait_for_function_rbac, module.storage_account]
}
