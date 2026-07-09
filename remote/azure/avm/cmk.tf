# ---------------------------------------------------------------------------
# Customer-managed key (CMK) layer (CCC.ObjStor.CN01, CCC.Core.CN02, CCC.Core.CN11)
#
# Keys live in the governed key vault and are created over the ARM CONTROL plane
# (azapi) so the vault stays fully private — data-plane key creation would need
# public / IP-allowlisted access to the vault. The storage account encrypts
# blob/file with cmk-storage via a user-assigned identity; the VM OS disk
# encrypts with cmk-disk via a disk encryption set. Both consuming identities
# reach the key through the trusted-Azure-services bypass (network_acls.bypass =
# AzureServices), so no public access is required at runtime either.
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "cmk" {
  name                = "${local.storage_account_name}-cmk-uami"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
}

resource "azapi_resource" "cmk_storage_key" {
  type      = "Microsoft.KeyVault/vaults/keys@2023-07-01"
  name      = "cmk-storage"
  parent_id = module.key_vault.resource_id
  body = {
    properties = {
      kty     = "RSA"
      keySize = 4096
      keyOps  = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
      # CCC.Core.CN11 / CCC.KeyMgmt: rotate the key within 90 days of issuance
      # (rotates at day 60, expires at day 90) so it satisfies the CN11
      # "keys should have a rotation policy" governance audit.
      rotationPolicy = {
        attributes = {
          expiryTime = "P90D"
        }
        lifetimeActions = [
          {
            action  = { type = "rotate" }
            trigger = { timeAfterCreate = "P60D" }
          },
          {
            action  = { type = "notify" }
            trigger = { timeBeforeExpiry = "P30D" }
          }
        ]
      }
    }
  }
}

resource "azapi_resource" "cmk_disk_key" {
  type      = "Microsoft.KeyVault/vaults/keys@2023-07-01"
  name      = "cmk-disk"
  parent_id = module.key_vault.resource_id
  body = {
    properties = {
      kty     = "RSA"
      keySize = 4096
      keyOps  = ["decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"]
      # CCC.Core.CN11: rotate within 90 days of issuance (see cmk-storage).
      rotationPolicy = {
        attributes = {
          expiryTime = "P90D"
        }
        lifetimeActions = [
          {
            action  = { type = "rotate" }
            trigger = { timeAfterCreate = "P60D" }
          },
          {
            action  = { type = "notify" }
            trigger = { timeBeforeExpiry = "P30D" }
          }
        ]
      }
    }
  }
  response_export_values = ["properties.keyUriWithVersion"]
}

# CMK for AKS KMS etcd encryption of Kubernetes secrets (CCC.Core.CN02,
# CCC.Core.CN11). The new AKS KMS experience auto-rotates when given the
# VERSIONLESS key URI (properties.keyUri), so both forms are exported.
resource "azapi_resource" "cmk_aks_key" {
  type      = "Microsoft.KeyVault/vaults/keys@2023-07-01"
  name      = "cmk-aks"
  parent_id = module.key_vault.resource_id
  body = {
    properties = {
      kty     = "RSA"
      keySize = 4096
      keyOps  = ["decrypt", "encrypt", "unwrapKey", "wrapKey"]
      # CCC.Core.CN11: rotate within 90 days of issuance (see cmk-storage).
      rotationPolicy = {
        attributes = {
          expiryTime = "P90D"
        }
        lifetimeActions = [
          {
            action  = { type = "rotate" }
            trigger = { timeAfterCreate = "P60D" }
          },
          {
            action  = { type = "notify" }
            trigger = { timeBeforeExpiry = "P30D" }
          }
        ]
      }
    }
  }
  response_export_values = ["properties.keyUri", "properties.keyUriWithVersion"]
}

# The storage CMK identity may wrap/unwrap the encryption key.
resource "azurerm_role_assignment" "storage_cmk" {
  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cmk.principal_id
}

# Dedicated identity for the VM disk encryption set. It is granted key access
# BEFORE the set is created, so the (control-plane) creation validates without
# the deployer ever needing data-plane access to the private vault.
resource "azurerm_user_assigned_identity" "des" {
  name                = "${local.virtual_machine_name}-des-uami"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
}

resource "azurerm_role_assignment" "des_cmk" {
  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.des.principal_id
}

# RBAC is eventually consistent; let the crypto-role assignments propagate before
# the storage account binds the CMK and the disk encryption set is created.
resource "time_sleep" "wait_for_cmk_rbac" {
  create_duration = "300s"
  depends_on = [
    azurerm_role_assignment.storage_cmk,
    azapi_resource.cmk_storage_key,
  ]
}

resource "time_sleep" "wait_for_des_rbac" {
  create_duration = "300s"
  depends_on      = [azurerm_role_assignment.des_cmk]
}

# Disk Encryption Set for the VM OS disk, created over the ARM CONTROL plane
# (azapi) so the deployer never performs a data-plane key read against the
# private vault (the azurerm provider would, and that path is network-blocked).
# The set's user-assigned identity reaches the key over the trusted-services
# bypass at runtime.
resource "azapi_resource" "des" {
  type      = "Microsoft.Compute/diskEncryptionSets@2023-10-02"
  name      = "${local.virtual_machine_name}-des"
  parent_id = azurerm_resource_group.this.id
  location  = var.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.des.id]
  }

  body = {
    properties = {
      encryptionType = "EncryptionAtRestWithCustomerKey"
      activeKey = {
        keyUrl = azapi_resource.cmk_disk_key.output.properties.keyUriWithVersion
      }
      rotationToLatestKeyVersionEnabled = true
    }
  }

  depends_on = [
    azapi_resource.cmk_disk_key,
    time_sleep.wait_for_des_rbac,
  ]
}
