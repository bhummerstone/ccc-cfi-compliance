# ---------------------------------------------------------------------------
# Virtual network (support) — provides the delegated functions subnet, the VM
# subnet and the private-endpoints subnet used by the storage, key-vault,
# serverless-function and virtual-machine modules. This is an enabler for the
# CCC capability services, not itself a CCC service under test, so it is not
# driven by a control-informed tfvars file.
# ---------------------------------------------------------------------------
module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  location      = var.location
  name          = local.virtual_network_name
  parent_id     = azurerm_resource_group.this.id
  address_space = ["10.40.0.0/16"]

  # VNet-level encryption is DISABLED because it is incompatible with AKS API
  # Server VNet Integration on v4+ node SKUs (see aks.tf) and AKS shares this
  # VNet. CCC.Core.CN01 in-transit encryption is still enforced at the
  # application/TLS layer on every service in this VNet (storage secure-transfer
  # + TLS1.2, function https_only + TLS1.3, VM in-transit), and AKS can layer on
  # ACNS WireGuard pod-to-pod encryption. Re-enable only if AKS is moved to a
  # dedicated VNet.
  encryption = {
    enabled     = false
    enforcement = "AllowUnencrypted"
  }

  subnets = {
    # Dedicated subnet for the storage / key-vault / function private endpoints.
    pe = {
      name                              = "private-endpoints"
      address_prefixes                  = ["10.40.1.0/24"]
      private_endpoint_network_policies = "Enabled"
    }
    functions = {
      name             = "functions-integration"
      address_prefixes = ["10.40.2.0/24"]
      delegations = [{
        name = "Microsoft.App.environments"
        service_delegation = {
          name = "Microsoft.App/environments"
        }
      }]
    }
    vm = {
      name             = "vm"
      address_prefixes = ["10.40.3.0/24"]
    }
    # --- AKS Automatic (private, API Server VNet Integration) --------------
    # Workload node pool subnet (CCC.Core.CN05).
    aks_nodes = {
      name             = "aks-nodes"
      address_prefixes = ["10.40.4.0/24"]
    }
    # Managed system node pool subnet for the Automatic hosted system profile.
    aks_system = {
      name             = "aks-system"
      address_prefixes = ["10.40.5.0/24"]
    }
    # Dedicated API server subnet, delegated to AKS so it can inject the API
    # server internal load balancer (API Server VNet Integration). Minimum /28,
    # cannot host other workloads.
    aks_apiserver = {
      name             = "aks-apiserver"
      address_prefixes = ["10.40.6.0/28"]
      delegations = [{
        name = "aks-apiserver-delegation"
        service_delegation = {
          name = "Microsoft.ContainerService/managedClusters"
        }
      }]
    }
  }
}
