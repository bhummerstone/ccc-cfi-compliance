# ---------------------------------------------------------------------------
# Log Analytics workspace (avm-res-operationalinsights-workspace) — central log
# sink, internet ingestion/query disabled.
# ---------------------------------------------------------------------------
module "log_analytics_workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  location            = var.location
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.this.name

  log_analytics_workspace_retention_in_days          = var.log_analytics_workspace_retention_in_days
  log_analytics_workspace_internet_ingestion_enabled = var.log_analytics_workspace_internet_ingestion_enabled
  log_analytics_workspace_internet_query_enabled     = var.log_analytics_workspace_internet_query_enabled
}
