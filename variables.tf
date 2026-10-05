variable "subscription_id" {
  description = "Subscription ID de Azure - requerido explicitamente por el provider azurerm >= 4.0. Sin default a proposito: pasarlo via -var, un .tfvars gitignoreado, o TF_VAR_subscription_id (NO usar ARM_SUBSCRIPTION_ID, el provider no lo lee)."
  type        = string
}

variable "tenant_id" {
  description = "Tenant ID de Entra ID - requerido explicitamente por el provider azuread (App Registration). Sin default, mismo criterio que subscription_id."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group compartido de la cuenta jalcalaroot (no creado por este proyecto)"
  type        = string
  default     = "jalcalaroot"
}

variable "location" {
  description = "Azure region - debe coincidir con la region del resource group y de azure-virtual-network"
  type        = string
  default     = "eastus"
}

variable "owner" {
  description = "Owner tag aplicado a todos los recursos"
  type        = string
  default     = "johan"
}

variable "environment" {
  description = "Environment tag aplicado a todos los recursos"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags extra a mergear con las base (Project/Environment/Owner/ManagedBy)"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# Red: outputs de azure-virtual-network, copiados a mano (sin
# terraform_remote_state, mismo patron que azure-container-apps/
# azure-aks-cluster - ver azure-virtual-network/README.md "No
# terraform_remote_state").
# ==============================================================================

variable "network_privatelink_subnet_id" {
  description = "privatelink_subnet_id de azure-virtual-network - destino de los Private Endpoints de Cosmos DB, AI Foundry, Content Safety, el storage del Function App y el Function App (inbound)."
  type        = string
}

variable "network_apim_subnet_id" {
  description = <<-EOT
    apim_subnet_id de azure-virtual-network (snet-apim, 10.0.74.0/24, sin
    delegation, con nsg-apim) - donde se inyecta API Management en modo
    VNet External. Copiar aca el output network_apim_subnet_id. Ver
    azure-virtual-network/CLAUDE.md, seccion "Subnet nueva apim".
  EOT
  type        = string
}

variable "network_function_app_subnet_id" {
  description = <<-EOT
    azure-virtual-network no tenia ninguna subnet delegada a
    Microsoft.Web/serverFarms - se agrego una nueva en codigo (func,
    10.0.73.0/24, NSG dedicada nsg-func; PR #32 de ese repo, todavia sin
    mergear ni aplicar) para esto. Copiar aca el output
    network_func_subnet_id de azure-virtual-network. Ver
    azure-virtual-network/CLAUDE.md, seccion "Subnet nueva func, delegada a
    Microsoft.Web/serverFarms".

    Sin default a proposito (mismo criterio que el resto de variables
    network_* de este repo - se copian a mano, sin terraform_remote_state).
  EOT
  type        = string
}

variable "network_vnet_id" {
  description = "vnet_id de azure-virtual-network - destino de los virtual_network_link de las Private DNS Zones que crea este repo."
  type        = string
}

variable "network_log_analytics_workspace_id" {
  description = "log_analytics_workspace_id de azure-virtual-network - destino de diagnostic settings y del Application Insights de este proyecto."
  type        = string
}

# ==============================================================================
# Cosmos DB
# ==============================================================================

variable "cosmos_account_name" {
  description = "Nombre de la cuenta de Cosmos DB (debe ser unico globalmente, 3-44 caracteres, minusculas/numeros/'-')"
  type        = string
  default     = "cosmos-agent-platform"
}

# ==============================================================================
# Azure AI Foundry (Cognitive Services, kind = AIServices)
# ==============================================================================

variable "ai_foundry_account_name" {
  description = "Nombre de la cuenta Cognitive Services (kind=AIServices) que actua como Azure AI Foundry"
  type        = string
  default     = "aif-agent-platform"
}

variable "embedding_model_name" {
  description = "Nombre del modelo de embeddings a deployar en AI Foundry"
  type        = string
  default     = "text-embedding-3-small"
}

variable "embedding_model_version" {
  description = "Version del modelo de embeddings - confirmar contra `az cognitiveservices account list-models` al momento del apply, las versiones disponibles varian por region."
  type        = string
  default     = "1"
}

variable "chat_model_name" {
  description = "Nombre del modelo de chat a deployar en AI Foundry"
  type        = string
  default     = "gpt-4.1-mini"
}

variable "chat_model_version" {
  description = "Version del modelo de chat - confirmar contra `az cognitiveservices account list-models` al momento del apply."
  type        = string
  default     = "2025-04-14"
}

# ==============================================================================
# Azure AI Content Safety
# ==============================================================================

variable "content_safety_account_name" {
  description = "Nombre de la cuenta Cognitive Services (kind=ContentSafety)"
  type        = string
  default     = "cs-agent-platform"
}

# ==============================================================================
# Function App (Flex Consumption) + FastAPI + Durable Functions
# ==============================================================================

variable "function_app_name" {
  description = "Nombre del Function App consolidado (FastAPI + Durable Functions)"
  type        = string
  default     = "func-jalcalaroot-agent"
}

variable "function_app_storage_account_name" {
  description = "Storage account dedicado del Function App (deployment package + Durable Functions state) - debe ser unico globalmente"
  type        = string
  default     = "stagentplatformfunc"
}

variable "fc1_instance_memory_mb" {
  description = "Memoria por instancia del plan Flex Consumption (MB) - valores validos: 2048 y 4096"
  type        = number
  default     = 2048
}

variable "fc1_maximum_instance_count" {
  description = "Limite maximo de instancias del plan Flex Consumption"
  type        = number
  default     = 100
}

variable "fc1_python_version" {
  description = "Version de runtime Python del Function App - confirmar versiones soportadas por Flex Consumption al momento del deploy"
  type        = string
  default     = "3.12"
}

# ==============================================================================
# API Management (tier Developer, VNet External)
# ==============================================================================

variable "apim_name" {
  description = "Nombre del API Management - debe ser unico globalmente (el gateway queda en <nombre>.azure-api.net)"
  type        = string
  default     = "apim-jalcalaroot-agent"
}

variable "apim_publisher_name" {
  description = "Nombre del publisher de API Management"
  type        = string
  default     = "jalcalaroot"
}

variable "apim_publisher_email" {
  description = "Email del publisher de API Management (notificaciones del servicio). Sin default a proposito - este repo es publico: pasarlo via TF_VAR_apim_publisher_email o la GitHub variable APIM_PUBLISHER_EMAIL."
  type        = string
}

# ==============================================================================
# App Registration (Entra ID)
# ==============================================================================

variable "app_registration_display_name" {
  description = "Display name de la App Registration que protege el endpoint /ask"
  type        = string
  default     = "policy-hub"
}

variable "app_registration_identifier_uri" {
  description = "Identifier URI de la App Registration - scope expuesto como <esto>/access_as_user"
  type        = string
  default     = "api://policy-hub"
}
