# ---------------------------------------------------------------------------
# Flex Consumption (FC1) hosting plan for the serverless function, via
# avm-res-web-serverfarm.
# ---------------------------------------------------------------------------
module "app_service_plan" {
  source  = "Azure/avm-res-web-serverfarm/azurerm"
  version = "2.0.3"

  location  = var.location
  name      = local.function_plan_name
  parent_id = azurerm_resource_group.this.id

  os_type  = "Linux"
  sku_name = "FC1"

  # Flex Consumption (FC1) is serverless: Azure manages worker count and zone
  # balancing, so zone balancing is disabled to match plain service-plan
  # behaviour. The module already special-cases FC1 (kind = functionapp,
  # capacity = 0, no maximumElasticWorkerCount).
  zone_balancing_enabled = false
}
