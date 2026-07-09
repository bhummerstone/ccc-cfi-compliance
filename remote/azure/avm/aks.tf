# ---------------------------------------------------------------------------
# AKS Automatic managed cluster (avm-res-containerservice-managedcluster)
#
# A private, production-ready-by-default AKS Automatic cluster that reuses the
# landing zone's shared enablers: the support virtual network (dedicated AKS
# subnets in network.tf), the fully private governed key vault + its CMK
# (cmk.tf), the disk encryption set, and the central Log Analytics workspace.
#
# CCC.Core coverage at the CLUSTER-INFRASTRUCTURE level. Honest scoping: a
# cluster resource cannot by itself satisfy application-, data- or process-level
# requirements. Legend:
#   [met]        the cluster config enforces the control's ARs
#   [partial]    enforces some ARs, or needs a governance add-on to complete
#   [supporting] contributes but does not satisfy the literal AR
#   [workload]   must be met by workloads/apps/backup, not the cluster resource
#
#   CN01 Encrypt in transit       [partial]  Managed Cilium + API/ingress TLS;
#                                            node SSH restricted. In-transit pod
#                                            encryption can be added via ACNS
#                                            WireGuard (Cilium-native, meets the
#                                            objective but not the literal TLS/mTLS
#                                            wording). AR08 mTLS = Istio mesh (infra)
#                                            + STRICT PeerAuthentication (workload).
#   CN02 Encrypt at rest          [met]      KMS CMEK for etcd + CMEK node disks
#                                            (workload PV CMK = CMK storage class).
#   CN03 MFA for access           [partial]  Managed Entra ID + Azure RBAC +
#                                            private API + local accounts off. The
#                                            MFA factor itself = Entra Conditional
#                                            Access (tenant policy, not a cluster arg).
#   CN04 Log access/changes       [met]      kube-audit* + guard + activity log to
#                                            an external LAW, plus ACNS Hubble flow
#                                            logs (app data-plane = workload).
#   CN05 Prevent untrusted access [met]      Private cluster + VNet integration,
#                                            Azure RBAC, Deployment Safeguards
#                                            (Enforce), ACNS FQDN + L7 Cilium policy,
#                                            deny-by-default KV.
#   CN06 Trust perimeter          [partial]  Region pinned; the approved-location
#                                            allowlist is enforced by the "Allowed
#                                            locations" Azure Policy (sub/MG governance).
#   CN07 Alert on enumeration     [met]      Defender for Containers detection +
#                                            audit logs + ACNS Hubble flow metrics
#                                            (route via a Monitor action group).
#   CN08 Replicate to >1 location [workload] Zonal node spread + HA managed control
#                                            plane give availability; replicating
#                                            workload DATA is a storage/PV/backup concern.
#   CN09 Log integrity            [partial]  Logs to an EXTERNAL LAW (AR01 met).
#                                            Immutable logging config (AR02/03) =
#                                            Azure Policy + activity-log alert on
#                                            diagnostic-setting changes.
#   CN10 Replication perimeter    [workload] Region pinning + private networking;
#                                            actual replication destinations are a
#                                            storage/backup-layer concern.
#   CN11 Protect encryption keys  [met]      HSM CMK, rotation <=90d, CMEK for etcd +
#                                            disks, least-privilege RBAC, private vault.
#   CN13 Minimize cert lifetime   [supporting] AKS auto-rotates control-plane /
#                                            kubelet certs; app + ingress cert
#                                            lifetime = cert-manager / KV CSI
#                                            (workload). A CMK is not a certificate.
#   CN14 Maintain recent backups  [workload] NOT met by the cluster. Deploy Azure
#                                            Backup for AKS + an immutable Backup
#                                            vault (30-day lock) for cluster-state /
#                                            PV backups.
#
# See aks.tfvars for the control-informed knobs.
# ---------------------------------------------------------------------------

# Dedicated cluster identity, pre-granted access to the BYO network and the
# private key vault BEFORE the cluster is created (CCC.Core.CN11.AR04
# least-privilege). The new KMS CMEK experience requires a managed identity.
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${local.aks_cluster_name}-uami"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
}

# Cluster identity must be able to inject the API server internal load balancer
# and nodes into the delegated subnets (CCC.Core.CN05).
resource "azurerm_role_assignment" "aks_network" {
  scope                = module.virtual_network.resource_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# KMS etcd CMEK against the fully PRIVATE key vault: the new AKS KMS experience
# reaches the vault through the trusted-Azure-services bypass
# (network_acls.bypass = AzureServices), so no public vault access is needed.
# The CMK-private path requires BOTH Key Vault Crypto User (encrypt/decrypt) and
# Key Vault Contributor (key management) on the cluster identity.
# (CCC.Core.CN02 / CCC.Core.CN11)
resource "azurerm_role_assignment" "aks_kv_crypto_user" {
  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

resource "azurerm_role_assignment" "aks_kv_contributor" {
  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# RBAC is eventually consistent; let the assignments and the CMK key propagate
# before the cluster binds them.
resource "time_sleep" "wait_for_aks_rbac" {
  create_duration = "300s"
  depends_on = [
    azurerm_role_assignment.aks_network,
    azurerm_role_assignment.aks_kv_crypto_user,
    azurerm_role_assignment.aks_kv_contributor,
    azapi_resource.cmk_aks_key,
  ]
}

module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.6.7"

  name       = local.aks_cluster_name
  location   = var.location
  parent_id  = azurerm_resource_group.this.id
  dns_prefix = local.aks_cluster_name

  # AKS Automatic provisioning (managed system pool across zones + add-ons) can
  # exceed the azapi default operation timeout, so allow up to an hour.
  cluster_timeouts = {
    create = "60m"
    update = "60m"
    delete = "60m"
    read   = "10m"
  }

  # kubernetes_version is intentionally NOT set. AKS Automatic auto-upgrades on
  # the stable channel (fixed for Automatic) and moves minor versions over time,
  # so pinning a version here would be re-asserted on every apply and fight the
  # managed upgrade (attempted downgrades are rejected). Letting Azure manage the
  # version is the CCC.Core.CN13/CN14-aligned posture, and new Automatic clusters
  # provision on a current version (>= 1.33, the private-KMS prerequisite).

  # AKS Automatic: hardened, production-ready default posture (Deployment
  # Safeguards + baseline PSS in ENFORCE mode -> CCC.Core.CN05; Azure RBAC /
  # Workload Identity / OIDC -> CCC.Core.CN03; managed Prometheus + Container
  # Insights -> CCC.Core.CN04/CN07; Image Cleaner + Azure Linux auto-patch ->
  # CCC.Core.CN13/CN14; managed Cilium networking -> CCC.Core.CN01/CN05).
  sku = {
    name = "Automatic"
    tier = "Standard"
  }

  # User-assigned identity pre-granted KMS + network access.
  managed_identities = {
    system_assigned            = false
    user_assigned_resource_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # Managed Entra ID + Azure RBAC, local accounts disabled so all human access
  # is brokered through Entra ID / Conditional Access (CCC.Core.CN03/CN05).
  enable_rbac            = true
  disable_local_accounts = true
  aad_profile = {
    managed                = true
    enable_azure_rbac      = true
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  # Grant the deployer cluster-admin over Azure RBAC (local accounts are off).
  role_assignments = merge(
    {
      deployer = {
        principal_id               = data.azurerm_client_config.current.object_id
        role_definition_id_or_name = "Azure Kubernetes Service RBAC Cluster Admin"
        principal_type             = "User"
      }
    },
    {
      for id in var.aks_admin_group_object_ids : "admin-${id}" => {
        principal_id               = id
        role_definition_id_or_name = "Azure Kubernetes Service RBAC Cluster Admin"
        principal_type             = "Group"
      }
    }
  )

  # Private API server via VNet integration into the delegated subnet; no public
  # network access; run command disabled (CCC.Core.CN05). AKS manages the
  # private DNS zone ("system"), so no BYO zone is required.
  api_server_access_profile = {
    subnet_id                          = module.virtual_network.subnets["aks_apiserver"].resource_id
    enable_private_cluster             = true
    enable_private_cluster_public_fqdn = false
    private_dns_zone                   = "system"
    disable_run_command                = true
  }
  public_network_access = "Disabled"

  # BYO VNet subnet wiring for the Automatic managed system + workload nodes.
  hosted_system_profile = {
    enabled               = true
    node_subnet_id        = module.virtual_network.subnets["aks_nodes"].resource_id
    system_node_subnet_id = module.virtual_network.subnets["aks_system"].resource_id
  }
  # NOTE: on the Automatic SKU the module does not forward an explicit node
  # vm_size (Automatic selects from its own D-series candidate set via Node
  # Auto-Provisioning). Automatic requires ~16 vCPUs of a candidate D-family
  # across 3 zones in the target region, so ensure that quota exists before
  # deploying (see the CCC coverage notes / README).
  default_agent_pool = {
    vnet_subnet_id = module.virtual_network.subnets["aks_nodes"].resource_id
  }

  # Automatic manages Azure CNI Overlay + Cilium; egress via managed LB.
  # Advanced Container Networking Services (ACNS), Cilium-native:
  #  - observability -> Hubble network flow logs/metrics (CCC.Core.CN04/CN07).
  #  - security      -> FQDN egress filtering + Layer 7 (HTTP/Kafka) network
  #                     policies for in-cluster segmentation (CCC.Core.CN05).
  # NOTE: ACNS WireGuard in-transit encryption (CCC.Core.CN01) is deliberately
  # NOT enabled here: WireGuard is not TLS/mTLS (so it would not meet the literal
  # AR01 "TLS 1.3" / AR08 "mTLS" wording), and the module does not expose the
  # transit-encryption toggle (it would require an azapi patch on networkProfile).
  network_profile = {
    outbound_type = "loadBalancer"
    advanced_networking = {
      enabled = true
      observability = {
        enabled = true
      }
      security = {
        enabled                   = true
        advanced_network_policies = "L7"
      }
    }
  }

  # CMEK at rest for node OS/data disks, reusing the landing zone's disk
  # encryption set (cmk-disk). Passed at create time so Node Auto-Provisioned
  # pools inherit the customer-managed key (CCC.Core.CN02 / CCC.Core.CN11).
  disk_encryption_set_id = azapi_resource.des.id

  # Security profile:
  #  - azure_key_vault_kms  -> CMEK etcd encryption via the PRIVATE key vault
  #                            (CCC.Core.CN02 / CCC.Core.CN11). The GA KMS
  #                            provider requires a VERSIONED key URI; the key's
  #                            rotation policy rotates the version in Key Vault,
  #                            and a subsequent apply rolls the cluster forward.
  #  - defender             -> threat / enumeration detection (CCC.Core.CN07).
  #  - workload_identity    -> federated, secret-less pod auth (CCC.Core.CN03).
  #  - image_cleaner        -> prunes stale images (attack-surface reduction).
  security_profile = {
    azure_key_vault_kms = {
      enabled                  = true
      key_id                   = azapi_resource.cmk_aks_key.output.properties.keyUriWithVersion
      key_vault_network_access = "Private"
      key_vault_resource_id    = module.key_vault.resource_id
    }
    defender = {
      log_analytics_workspace_resource_id = module.log_analytics_workspace.resource_id
      security_monitoring = {
        enabled = true
      }
    }
    image_cleaner = {
      enabled        = true
      interval_hours = 168
    }
    workload_identity = {
      enabled = true
    }
  }

  oidc_issuer_profile = {
    enabled = true
  }

  # Azure Policy add-on backs Deployment Safeguards (CCC.Core.CN05).
  addon_profile_azure_policy = {
    enabled = true
  }

  # CSI secret store with auto-rotation of mounted secrets/certs
  # (CCC.Core.CN11; supporting for CN13 app-cert rotation).
  addon_profile_key_vault_secrets_provider = {
    enabled = true
    config = {
      enable_secret_rotation = true
      rotation_poll_interval = "2m"
    }
  }

  # Container Insights to the central Log Analytics workspace (CCC.Core.CN04).
  addon_profile_oms_agent = {
    enabled = true
    config = {
      log_analytics_workspace_resource_id = module.log_analytics_workspace.resource_id
      use_aad_auth                        = true
    }
  }

  # Control-plane audit logs to the EXTERNAL workspace (CCC.Core.CN04 +
  # CCC.Core.CN09). kube-audit* captures every access and configuration change.
  diagnostic_settings = {
    to_law = {
      name                  = "diag-${local.aks_cluster_name}"
      workspace_resource_id = module.log_analytics_workspace.resource_id
      log_categories = [
        "kube-audit",
        "kube-audit-admin",
        "kube-apiserver",
        "kube-controller-manager",
        "cluster-autoscaler",
        "guard",
      ]
      metric_categories = ["AllMetrics"]
    }
  }

  # Version/patch currency is handled by AKS Automatic itself: the upgrade
  # channel is fixed to "stable" and node images are auto-patched, so no
  # auto_upgrade_profile is set here. This SUPPORTS CN13 (keeping AKS-managed
  # certs/components current) but is NOT a backup: CN14 requires Azure Backup
  # for AKS + an immutable Backup vault (workload/add-on, not configured here).

  depends_on = [time_sleep.wait_for_aks_rbac]
}
