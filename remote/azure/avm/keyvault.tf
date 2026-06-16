# ---------------------------------------------------------------------------
# Key vault (avm-res-keyvault-vault) — governed secrets/keys store, fully
# private (private endpoint + private DNS). Holds the CMK keys used for storage
# and VM-disk encryption at rest.
# ---------------------------------------------------------------------------
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  name                = local.key_vault_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment
  legacy_access_policies_enabled  = var.legacy_access_policies_enabled
  network_acls                    = var.network_acls
  public_network_access_enabled   = var.public_network_access_enabled
  purge_protection_enabled        = var.purge_protection_enabled
  sku_name                        = var.sku_name
  soft_delete_retention_days      = var.soft_delete_retention_days

  # Vault private endpoint into the pe subnet, resolved via private DNS.
  private_endpoints = {
    vault = {
      name                            = "pe-${local.key_vault_name}-vault"
      private_service_connection_name = "pse-${local.key_vault_name}-vault"
      subnet_resource_id              = module.virtual_network.subnets["pe"].resource_id
      subresource_name                = "vault"
      private_dns_zone_resource_ids   = [module.private_dns["vault"].resource_id]
    }
  }
}
