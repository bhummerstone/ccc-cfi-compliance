# ---------------------------------------------------------------------------
# Virtual machine (avm-res-compute-virtualmachine) — Linux, Trusted Launch,
# encryption at host, no-password (generated SSH key), NIC on the VM subnet,
# OS disk encrypted with a customer-managed key via the disk encryption set.
# ---------------------------------------------------------------------------
module "virtual_machine" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.21.0"

  location            = var.location
  name                = local.virtual_machine_name
  resource_group_name = azurerm_resource_group.this.name
  zone                = var.vm_zone
  os_type             = "Linux"
  sku_size            = var.vm_sku_size

  # Marketplace image. Must be a Gen2 image for Trusted Launch.
  source_image_reference = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  account_credentials        = var.account_credentials
  boot_diagnostics           = var.boot_diagnostics
  encryption_at_host_enabled = var.encryption_at_host_enabled
  managed_identities         = var.managed_identities
  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled

  # OS-disk customer-managed key via the disk encryption set (CCC.Core.CN11).
  os_disk = {
    caching                = "ReadWrite"
    storage_account_type   = "Premium_LRS"
    disk_encryption_set_id = azapi_resource.des.id
  }

  network_interfaces = {
    primary = {
      name = "${local.virtual_machine_name}-nic"
      ip_configurations = {
        ipconfig1 = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = module.virtual_network.subnets["vm"].resource_id
        }
      }
    }
  }

  depends_on = [azapi_resource.des]
}
