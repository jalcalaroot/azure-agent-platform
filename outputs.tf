output "cosmos_account_id" {
  description = "ID de la cuenta de Cosmos DB"
  value       = module.cosmos.resource_id
}

output "cosmos_account_endpoint" {
  description = "Endpoint de la cuenta de Cosmos DB"
  value       = module.cosmos.endpoint
}

output "ai_foundry_account_id" {
  description = "ID de la cuenta Cognitive Services (AI Foundry)"
  value       = azurerm_cognitive_account.ai_foundry.id
}

output "ai_foundry_endpoint" {
  description = "Endpoint de AI Foundry"
  value       = azurerm_cognitive_account.ai_foundry.endpoint
}

output "content_safety_account_id" {
  description = "ID de la cuenta Cognitive Services (Content Safety)"
  value       = azurerm_cognitive_account.content_safety.id
}

output "function_app_id" {
  description = "ID del Function App"
  value       = module.function_app.resource_id
}

output "function_app_name" {
  description = "Nombre del Function App"
  value       = var.function_app_name
}

output "function_app_identity_principal_id" {
  description = "Principal ID de la Managed Identity del Function App"
  value       = azurerm_user_assigned_identity.function_app.principal_id
}

output "apim_id" {
  description = "ID del API Management"
  value       = module.apim.resource_id
}

output "apim_gateway_url" {
  description = "URL publica del gateway de API Management - unico punto de entrada del sistema"
  value       = module.apim.apim_gateway_url
}

output "api_base_url" {
  description = "Base URL de la API (POST <esto>/ask, GET <esto>/health) - lo que usan Postman/Streamlit como GATEWAY_URL"
  value       = "${module.apim.apim_gateway_url}/${local.apim_api_path}"
}

output "app_registration_client_id" {
  description = "Client ID de la App Registration (Postman/Streamlit)"
  value       = azuread_application.policy_hub.client_id
}

output "app_registration_identifier_uri" {
  description = "Identifier URI - la Streamlit/Postman piden token para <esto>/access_as_user o <esto>/.default"
  value       = var.app_registration_identifier_uri
}
