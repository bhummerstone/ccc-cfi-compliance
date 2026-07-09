# This file is CONTROL-INFORMED CANDIDATE configuration, not a compliance
# attestation. It covers only technical settings expressible as AVM module
# inputs. It does NOT establish FedRAMP / CCC / NIST compliance. Mapped
# controls may be only partially satisfied; unmapped and process/evidence
# controls are out of scope here. Human review and deployment-context
# validation are required before use.
#
# AVM module:   Azure/avm-res-containerservice-managedcluster/azurerm
# Module ver:   0.6.7  (provider azurerm >= 4.46, < 5.0; azapi ~> 2.9)
# Sources:      {"ccc": ["CCC.Core"], "ccc_catalog_ref": "https://github.com/finos/common-cloud-controls/blob/main/catalogs/core/ccc/controls.yaml"}
#
# The bulk of the CCC.Core posture for this cluster is expressed directly in
# aks.tf (private API-server VNet integration, managed Entra ID, CMEK/KMS,
# Defender, audit diagnostics) plus the AKS Automatic SKU defaults. This file
# holds only the deployment-specific knobs.

# Controls: CCC.Core.CN03, CCC.Core.CN05  [coverage: partial]
# Entra ID group(s) granted cluster-admin via Azure RBAC. Local accounts are
# disabled (aks.tf: disable_local_accounts = true), so at least one group is
# required to administer the cluster. Populate with your platform-admin group
# object ID(s); leaving it empty deploys a cluster only the deploying principal
# can administer.
aks_admin_group_object_ids = []

# NOTE on Kubernetes version: not pinned on purpose. AKS Automatic manages the
# version on the fixed "stable" channel (CCC.Core.CN13/CN14); pinning would be
# re-asserted every apply and conflict with auto-upgrade. New Automatic clusters
# provision on a current version (>= 1.33), satisfying the private-KMS
# prerequisite without a pin.
