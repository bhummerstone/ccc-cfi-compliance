# ---------------------------------------------------------------------------
# Storage account (avm-res-storage-storageaccount) — governed object storage,
# fully private (private endpoints + private DNS), CMK encryption at rest.
# Also backs the Flex Consumption function's deployment package container.
# ---------------------------------------------------------------------------
locals {
  # Optional, off-by-default break-glass: allow a single operator IP through the
  # storage firewall for data-plane provisioning. The default posture is fully
  # private (deny + no public access); the function's deploymentpackage container
  # is created over the ARM control plane, so this is normally unnecessary.
  deployer_ip_rules = var.allow_deployer_ip && var.deployer_ip_address != "" ? toset([var.deployer_ip_address]) : toset([])
  storage_network_rules = merge(var.network_rules, {
    ip_rules = local.deployer_ip_rules
  })
  storage_public_network_access_enabled = var.allow_deployer_ip ? true : var.public_network_access_enabled
}

module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.7.2"

  location  = var.location
  parent_id = azurerm_resource_group.this.id
  name      = local.storage_account_name

  allow_nested_items_to_be_public   = var.allow_nested_items_to_be_public
  blob_properties                   = var.blob_properties
  default_to_oauth_authentication   = var.default_to_oauth_authentication
  https_traffic_only_enabled        = var.https_traffic_only_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  min_tls_version                   = var.min_tls_version
  network_rules                     = local.storage_network_rules
  public_network_access_enabled     = local.storage_public_network_access_enabled
  shared_access_key_enabled         = var.shared_access_key_enabled

  # Customer-managed key (CMK) encryption at rest (CCC.ObjStor.CN01, CCC.Core.CN02).
  # The account encrypts blob/file data with cmk-storage in the governed key vault,
  # reached through a user-assigned identity. Gated on RBAC propagation.
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.cmk.id]
  }
  customer_managed_key = {
    key_vault_resource_id = module.key_vault.resource_id
    key_name              = "cmk-storage"
    user_assigned_identity = {
      resource_id = azurerm_user_assigned_identity.cmk.id
    }
  }

  # Account-level blob versioning stays on via var.blob_properties
  # (CCC.ObjStor.CN04/CN05). We intentionally do NOT enable container-level
  # version-level immutability (WORM) here, for two reasons:
  #   1. It is wrong for the function's `deploymentpackage` container, which the
  #      Flex Consumption runtime must be able to overwrite.
  #   2. On the test data container an *unlocked* immutability flag does not
  #      satisfy CCC.ObjStor.CN03.AR02 (the retention policy MUST be
  #      irrevocable), yet it still forces the container create to depend on the
  #      versioning update, which races on a cold apply
  #      ("Required feature Versioning is disabled").
  #
  # Realizing CN03 fully IS possible: on the DATA container only (never the
  # function package container), enable version-level immutability and then
  # *lock* a time-based retention policy, e.g.
  #     immutable_storage_with_versioning = { enabled = true }
  # plus a locked Microsoft.Storage immutabilityPolicy with
  # immutabilityPeriodSinceCreationInDays (and optionally a legal hold). Once
  # locked, the policy cannot be shortened or removed, so objects are
  # irrevocably retained for the period. The trade-off is that the account /
  # container then cannot be deleted until every blob's retention expires, which
  # is why it is omitted from this tear-down-able reference deployment.
  containers = {
    (local.default_container) = {
      name          = local.default_container
      public_access = "None"
    }
    # Flex Consumption backing deployment container, created over the ARM control
    # plane so the account can stay fully private (no data-plane / public access).
    deploymentpackage = {
      name          = "deploymentpackage"
      public_access = "None"
    }
  }

  # Blob + file private endpoints into the pe subnet, resolved via private DNS.
  private_endpoints = {
    blob = {
      name                            = "pe-${local.storage_account_name}-blob"
      private_service_connection_name = "pse-${local.storage_account_name}-blob"
      subnet_resource_id              = module.virtual_network.subnets["pe"].resource_id
      subresource_name                = "blob"
      private_dns_zone_resource_ids   = [module.private_dns["blob"].resource_id]
    }
    file = {
      name                            = "pe-${local.storage_account_name}-file"
      private_service_connection_name = "pse-${local.storage_account_name}-file"
      subnet_resource_id              = module.virtual_network.subnets["pe"].resource_id
      subresource_name                = "file"
      private_dns_zone_resource_ids   = [module.private_dns["file"].resource_id]
    }
  }

  depends_on = [time_sleep.wait_for_cmk_rbac]
}
