terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # avm-ptn-policyassignment constrains azurerm to ~> 3.74 (>= 3.74, < 4.0),
      # so this root module pins below 4.0 even though the rest of the repo allows 4.x.
      version = ">= 3.90, < 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.8"
    }
    modtm = {
      source  = "Azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0, < 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
}
