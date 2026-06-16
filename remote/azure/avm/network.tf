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

  # CCC.Core.CN01 (network-layer encryption). DropUnencrypted requires full-fleet
  # SKU/accelerated-networking support and can break traffic to unsupported
  # workloads, so the deployable baseline relaxes enforcement to AllowUnencrypted.
  # Set to DropUnencrypted for a hardened posture once fleet support is validated.
  encryption = {
    enabled     = true
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
  }
}
