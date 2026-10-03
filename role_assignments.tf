# RBAC de control-plane para la Managed Identity del Function App sobre AI
# Foundry y Content Safety - unico modulo de este repo que usa
# Azure/avm-res-authorization-roleassignment (la tabla de IaC del
# documento de requisitos lo lista explicitamente). El RBAC de datos de
# Cosmos DB NO pasa por aca - ver nota en cosmosdb.tf, esta AVM no lo
# soporta.
module "role_assignments" {
  source  = "Azure/avm-res-authorization-roleassignment/azurerm"
  version = "0.3.1"

  enable_telemetry = false

  role_assignments_azure_resource_manager = {
    function_app_ai_foundry = {
      principal_id         = azurerm_user_assigned_identity.function_app.principal_id
      role_definition_name = "Cognitive Services OpenAI User"
      scope                = azurerm_cognitive_account.ai_foundry.id
    }
    function_app_content_safety = {
      principal_id         = azurerm_user_assigned_identity.function_app.principal_id
      role_definition_name = "Cognitive Services User"
      scope                = azurerm_cognitive_account.content_safety.id
    }

    # Storage del Function App: la identidad lee el deployment package
    # (blob) y el host/Durable Functions usan blob, cola y tabla via
    # AzureWebJobsStorage por identidad (shared keys deshabilitadas).
    function_app_storage_blob = {
      principal_id         = azurerm_user_assigned_identity.function_app.principal_id
      role_definition_name = "Storage Blob Data Owner"
      scope                = module.function_app_storage.resource_id
    }
    function_app_storage_queue = {
      principal_id         = azurerm_user_assigned_identity.function_app.principal_id
      role_definition_name = "Storage Queue Data Contributor"
      scope                = module.function_app_storage.resource_id
    }
    function_app_storage_table = {
      principal_id         = azurerm_user_assigned_identity.function_app.principal_id
      role_definition_name = "Storage Table Data Contributor"
      scope                = module.function_app_storage.resource_id
    }
  }
}
