output "cosmos_account_id" {
  description = "ID de la cuenta de Cosmos DB"
  value       = module.cosmos.resource_id
}

output "cosmos_account_endpoint" {
  description = "Endpoint de la cuenta de Cosmos DB"
  value       = module.cosmos.resource.endpoint
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

output "app_gateway_public_ip" {
  description = "IP publica del Application Gateway - unico punto de entrada del sistema"
  value       = azurerm_public_ip.appgw.ip_address
}

output "app_registration_client_id" {
  description = "Client ID de la App Registration (Postman/Streamlit)"
  value       = azuread_application.policy_hub.client_id
}

output "app_registration_identifier_uri" {
  description = "Identifier URI - la Streamlit/Postman piden token para <esto>/access_as_user o <esto>/.default"
  value       = var.app_registration_identifier_uri
}

output "key_vault_id" {
  description = "ID del Key Vault (certificado TLS del Application Gateway)"
  value       = module.key_vault.resource_id
}
