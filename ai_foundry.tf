# Componente 1 - Azure AI Foundry.
#
# Sin AVM dedicada (ver tabla de modulos en CLAUDE.md) - azurerm_ai_foundry
# es el recurso "Hub classic", explicitamente marcado legacy en la doc del
# provider (confirmado via mcp__terraform, 2026-09-30): "Hub-based projects
# are considered legacy... Microsoft recommends using the new Microsoft
# Foundry resource, which should be provisioned using azurerm_cognitive_account."
# Foundry hoy = azurerm_cognitive_account con kind = "AIServices" (kind
# superset que incluye OpenAI) + azurerm_cognitive_deployment por modelo -
# mismo recurso que Content Safety (ver content_safety.tf), solo con otro
# kind.
resource "azurerm_cognitive_account" "ai_foundry" {
  name                = var.ai_foundry_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "AIServices"
  sku_name            = "S0"

  # Requerido para autenticacion AAD-only y para poder atachar un Private
  # Endpoint (confirmado en la doc del recurso: sin custom_subdomain_name
  # no hay Private Endpoint posible).
  custom_subdomain_name = var.ai_foundry_account_name

  local_auth_enabled            = false # sin API keys - solo Managed Identity/AAD
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = local.tags
}

resource "azurerm_cognitive_deployment" "embedding" {
  name                 = var.embedding_model_name
  cognitive_account_id = azurerm_cognitive_account.ai_foundry.id

  model {
    format  = "OpenAI"
    name    = var.embedding_model_name
    version = var.embedding_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = 10 # 10k TPM - punto de partida, ajustar contra uso real
  }
}

resource "azurerm_cognitive_deployment" "chat" {
  name                 = var.chat_model_name
  cognitive_account_id = azurerm_cognitive_account.ai_foundry.id

  model {
    format  = "OpenAI"
    name    = var.chat_model_name
    version = var.chat_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = 10
  }
}

# Private Endpoint - mismo patron que Key Vault/Storage en
# azure-virtual-network (recurso crudo, esta AVM no tiene modulo dedicado).
# subresource_names = ["account"] es el unico private link group de
# Cognitive Services. Las 3 private DNS zones cubren los distintos dominios
# que un endpoint de AI Services puede necesitar resolver - CONFIRMAR contra
# la configuracion real del NIC del Private Endpoint en el primer apply, no
# verificado contra un deployment real todavia.
resource "azurerm_private_dns_zone" "cognitiveservices" {
  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cognitiveservices" {
  name                  = "link-cognitiveservices-agent-platform"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.cognitiveservices.name
  virtual_network_id    = var.network_vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_dns_zone" "openai" {
  name                = "privatelink.openai.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "openai" {
  name                  = "link-openai-agent-platform"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.openai.name
  virtual_network_id    = var.network_vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_private_endpoint" "ai_foundry" {
  name                = "pe-${var.ai_foundry_account_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.network_privatelink_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${var.ai_foundry_account_name}"
    private_connection_resource_id = azurerm_cognitive_account.ai_foundry.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.cognitiveservices.id,
      azurerm_private_dns_zone.openai.id,
    ]
  }
}
