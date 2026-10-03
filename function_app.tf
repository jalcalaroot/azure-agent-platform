# Componentes 3+4 (infra) - Function App consolidado (FastAPI vía
# AsgiMiddleware + Durable Functions), plan Flex Consumption.
#
# El codigo de la aplicacion (FastAPI, orchestrator de ingesta clonado del
# quickstart oficial) no es parte de este pase - ver CLAUDE.md, "Orden de
# implementacion". Este archivo solo provisiona el Function App vacio y su
# storage de deployment.

resource "azurerm_user_assigned_identity" "function_app" {
  name                = "id-${var.function_app_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

# Storage de deployment package + estado de Durable Functions. Sin AVM en
# la tabla de este proyecto para esto en particular (no es uno de los 6
# componentes del documento de requisitos), pero si en la tabla general de
# la cuenta (mismo modulo ya usado en azure-virtual-network) - criterio de
# CLAUDE.md, "todo vía AVM donde exista un modulo real", aplica igual aca.
module "function_app_storage" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry, no un git tag.
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  #checkov:skip=CKV_AZURE_33:este storage account no expone Queue service para uso externo, no aplica.
  #checkov:skip=CKV_AZURE_206:LRS por costo - storage de deployment/estado interno del Function App, no datos de negocio.
  #checkov:skip=CKV2_AZURE_1:CMK genera costo de operaciones de Key Vault por un dato operacional, no critico.
  name      = var.function_app_storage_account_name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id
  tags      = local.tags

  enable_telemetry = false

  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # acceso vía UserAssignedIdentity (storage_authentication_type del Function App), sin keys

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  private_endpoints = {
    blob = {
      subnet_resource_id            = var.network_privatelink_subnet_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [data.azurerm_private_dns_zone.blob.id]
    }
    # El host de Functions (AzureWebJobsStorage por identidad) y Durable
    # Functions (provider Azure Storage) usan tambien cola y tabla, no solo
    # blob - sin estos 2 endpoints privados el app no arranca o no orquesta.
    queue = {
      subnet_resource_id            = var.network_privatelink_subnet_id
      subresource_name              = "queue"
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.queue.id]
    }
    table = {
      subnet_resource_id            = var.network_privatelink_subnet_id
      subresource_name              = "table"
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.table.id]
    }
  }
}

resource "azurerm_private_dns_zone" "queue" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  name                  = "link-queue-agent-platform"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.queue.name
  virtual_network_id    = var.network_vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "table" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  name                  = "link-table-agent-platform"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = var.network_vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

# azure-virtual-network ya crea Y linkea a la VNet la zona real
# "privatelink.blob.core.windows.net" (para su propio storage), y no pueden
# existir dos zonas con el mismo nombre en el mismo resource group - se
# reutiliza por data source en vez de crear otra. Antes este repo creaba
# "privatelink.blob.core.windows.net.func", un nombre inventado que no
# resuelve nada: el CNAME publico de un storage account apunta a
# <cuenta>.privatelink.blob.core.windows.net, nunca a un sufijo ".func".
# Consecuencia: requiere azure-virtual-network desplegado (ya es
# prerrequisito de este proyecto).
data "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_storage_container" "deployment_package" {
  name                  = "deploymentpackage"
  storage_account_id    = module.function_app_storage.resource_id
  container_access_type = "private"
}

# Plan Flex Consumption (FC1) - la AVM de Function App (avm-res-web-site) no
# expone el Service Plan en si, solo lo referencia via
# service_plan_resource_id (confirmado contra la doc del modulo,
# 2026-09-30: azapi_resource crudo es el patron documentado en el ejemplo
# oficial "flex_consumption" del propio modulo).
resource "azapi_resource" "function_service_plan" {
  type      = "Microsoft.Web/serverfarms@2025-03-01"
  name      = "plan-${var.function_app_name}"
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id

  body = {
    kind = "functionapp"
    sku = {
      name = "FC1"
    }
    properties = {
      reserved = true
    }
  }

  tags = local.tags
}

resource "azurerm_private_dns_zone" "azurewebsites" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "azurewebsites" {
  name                  = "link-azurewebsites-agent-platform"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.azurewebsites.name
  virtual_network_id    = var.network_vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

module "function_app" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "0.23.0"

  location                 = var.location
  name                     = var.function_app_name
  parent_id                = data.azurerm_resource_group.this.id
  service_plan_resource_id = azapi_resource.function_service_plan.id
  tags                     = local.tags

  enable_telemetry = false

  # Los roles de storage tienen que existir antes de que la plataforma lea
  # el deployment package al crear el app.
  depends_on = [module.role_assignments]

  kind                   = "functionapp"
  os_type                = "Linux"
  function_app_uses_fc1  = true
  fc1_runtime_name       = "python"
  fc1_runtime_version    = var.fc1_python_version
  instance_memory_in_mb  = var.fc1_instance_memory_mb
  maximum_instance_count = var.fc1_maximum_instance_count

  # Storage de deployment vía identidad administrada, sin access keys -
  # storage_container_endpoint construido de forma deterministica (URL de
  # blob container), no vía un output del modulo de storage (no verificado
  # que exponga un output de endpoint bajo ese nombre exacto).
  storage_authentication_type       = "UserAssignedIdentity"
  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "https://${var.function_app_storage_account_name}.blob.core.windows.net/${azurerm_storage_container.deployment_package.name}"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.function_app.id

  # Conexion SEPARADA de la de deployment: AzureWebJobsStorage es la
  # conexion propia del host (function keys, singletons, metadata de
  # triggers, tareas de Durable Functions) y, segun la doc del propio
  # modulo, "every plan requires" - sin ella el app no arranca. Encontrado
  # leyendo el codigo del modulo, no en un plan/apply.
  storage_account_name                     = var.function_app_storage_account_name
  storage_uses_managed_identity            = true
  storage_user_assigned_identity_client_id = azurerm_user_assigned_identity.function_app.client_id

  # Configuracion que lee el codigo de la aplicacion (app/). Todo accede por
  # la Managed Identity del Function App - sin keys ni connection strings.
  app_settings = {
    AZURE_CLIENT_ID         = azurerm_user_assigned_identity.function_app.client_id
    COSMOS_ENDPOINT         = module.cosmos.endpoint
    COSMOS_DATABASE         = "policyhub"
    AZURE_OPENAI_ENDPOINT   = "https://${var.ai_foundry_account_name}.openai.azure.com/"
    EMBEDDING_DEPLOYMENT    = azurerm_cognitive_deployment.embedding.name
    CHAT_DEPLOYMENT         = azurerm_cognitive_deployment.chat.name
    CONTENT_SAFETY_ENDPOINT = azurerm_cognitive_account.content_safety.endpoint
  }

  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.function_app.id]
  }

  # VNet integration (outbound) - ver GAP documentado en variables.tf,
  # network_function_app_subnet_id no tiene todavia un valor real.
  virtual_network_subnet_id     = var.network_function_app_subnet_id
  vnet_route_all_traffic        = true
  public_network_access_enabled = false

  private_endpoints = {
    sites = {
      subnet_resource_id            = var.network_privatelink_subnet_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.azurewebsites.id]
    }
  }

  application_insights_connection_string = module.app_insights.connection_string
  application_insights_key               = module.app_insights.instrumentation_key
}
