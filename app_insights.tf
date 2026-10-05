# Application Insights del Function App - no es uno de los 6 componentes
# del documento de requisitos, pero avm-res-insights-component esta en la
# tabla de modulos AVM y function_app.tf lo necesita para
# application_insights_connection_string/key.
module "app_insights" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry, no un git tag.
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "0.4.0"

  name                = "appi-agent-platform"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = var.network_log_analytics_workspace_id
  tags                = local.tags

  enable_telemetry = false

  application_type  = "web"
  retention_in_days = 30 # cost-conscious, mismo criterio que azure-virtual-network

  # local_authentication_disabled queda en su default (false, auth por
  # instrumentation key habilitada) - excepcion deliberada al criterio
  # "sin API keys" del resto del proyecto: es una clave de solo-escritura
  # de telemetria, no una credencial de lectura de datos, y el soporte end
  # to end de ingesta AAD-only en el SDK de Functions no esta confirmado.
}
