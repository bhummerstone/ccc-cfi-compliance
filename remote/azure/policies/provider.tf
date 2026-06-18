# Subscription ID can be set via:
#   - ARM_SUBSCRIPTION_ID environment variable
#   - TF_VAR_subscription_id environment variable
#   - az account set --subscription <id>

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}
