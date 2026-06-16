# ---------------------------------------------------------------------------
# Private DNS zones (support) — resolve the storage, key vault and function
# private-endpoint FQDNs to their private IPs from inside the virtual network.
# This is the dns.resolution.vnet-link enabler for the private-endpoint posture;
# it is not itself a CCC service under test, so it is not driven by a
# control-informed tfvars file.
# ---------------------------------------------------------------------------
module "private_dns" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  for_each = {
    blob  = "privatelink.blob.core.windows.net"
    file  = "privatelink.file.core.windows.net"
    vault = "privatelink.vaultcore.azure.net"
    sites = "privatelink.azurewebsites.net"
  }

  domain_name = each.value
  parent_id   = azurerm_resource_group.this.id

  virtual_network_links = {
    link = {
      vnetlinkname       = "to-vnet"
      virtual_network_id = module.virtual_network.resource_id
    }
  }
}
