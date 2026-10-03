# Componente 5 - Azure AI Content Safety.
#
# Sin AVM dedicada (ver tabla de modulos en CLAUDE.md) - mismo recurso que
# ai_foundry.tf, kind distinto. Prompt Shields (input) y el filtro de
# severidad (output) son llamadas de API en tiempo de ejecucion (codigo del
# Function App), no configuracion de Terraform - este archivo solo
# provisiona la cuenta y su acceso privado.
resource "azurerm_cognitive_account" "content_safety" {
  name                = var.content_safety_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "ContentSafety"
  sku_name            = "S0"

  custom_subdomain_name = var.content_safety_account_name

  local_auth_enabled            = false
  public_network_access_enabled = false

  # Sin `bypass`: el provider lo rechaza para kind ContentSafety (solo vale
  # para OpenAI, AIServices y TextAnalytics) - encontrado en el primer plan
  # real, `validate` no lo detecta.
  network_acls {
    default_action = "Deny"
  }

  tags = local.tags
}

resource "azurerm_private_endpoint" "content_safety" {
  name                = "pe-${var.content_safety_account_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.network_privatelink_subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${var.content_safety_account_name}"
    private_connection_resource_id = azurerm_cognitive_account.content_safety.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.cognitiveservices.id]
  }
}
