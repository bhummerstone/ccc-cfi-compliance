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

  # Platform metrics to the central Log Analytics workspace. The VM resource's
  # diagnostic settings are METRICS ONLY; guest access/change logs (the real
  # CCC.Core.CN04 evidence) are collected via the Azure Monitor Agent + syslog
  # Data Collection Rule defined below.
  diagnostic_settings = {
    metrics_to_law = {
      name                  = "diag-${local.virtual_machine_name}"
      workspace_resource_id = module.log_analytics_workspace.resource_id
      metric_categories     = ["AllMetrics"]
    }
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

# ---------------------------------------------------------------------------
# VM guest access/change logging (CCC.Core.CN04). The VM resource's diagnostic
# settings only carry metrics, so genuine access logging (SSH logins, sudo,
# system changes) is collected by the Azure Monitor Agent and shipped to the
# central Log Analytics workspace via a syslog Data Collection Rule. The agent
# authenticates with the VM's system-assigned managed identity.
# ---------------------------------------------------------------------------
resource "azurerm_monitor_data_collection_rule" "vm_syslog" {
  name                = "dcr-${local.virtual_machine_name}-syslog"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  destinations {
    log_analytics {
      name                  = "law-dest"
      workspace_resource_id = module.log_analytics_workspace.resource_id
    }
  }

  # Authentication events (logins, sudo) at Info+ so access is actually
  # captured; other facilities at Warning+ to limit noise.
  data_sources {
    syslog {
      name           = "syslog-auth"
      facility_names = ["auth", "authpriv"]
      log_levels     = ["Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
      streams        = ["Microsoft-Syslog"]
    }
    syslog {
      name           = "syslog-system"
      facility_names = ["cron", "daemon", "kern", "syslog", "user"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["law-dest"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "vm_syslog" {
  name                    = "dcra-${local.virtual_machine_name}-syslog"
  target_resource_id      = module.virtual_machine.resource_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vm_syslog.id
}

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = module.virtual_machine.resource_id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.42"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true

  depends_on = [azurerm_monitor_data_collection_rule_association.vm_syslog]
}
