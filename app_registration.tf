# Componente 6 - App Registration + validacion de tokens.
#
# azuread_application (monolitico) en vez del set decompuesto
# (azuread_application_registration + piezas separadas) que trae el
# provider azuread 3.x - para un solo scope expuesto y sin necesidad de
# administrar mas de una pieza por separado, el recurso monolitico alcanza
# y es mas simple de leer.
data "azuread_client_config" "current" {}

resource "random_uuid" "access_as_user_scope" {}

resource "azuread_application" "policy_hub" {
  display_name    = var.app_registration_display_name
  identifier_uris = [var.app_registration_identifier_uri]
  owners          = [data.azuread_client_config.current.object_id]

  sign_in_audience = "AzureADMyOrg" # single-tenant, alcanza para este proyecto

  # Los owners los fija quien crea el recurso (el usuario local o la identidad
  # de CI, segun quien corra). Ignorarlos evita que el apply de CI intente
  # quitar al otro dueño, operacion que requiere mas privilegios que OwnedBy.
  lifecycle {
    ignore_changes = [owners]
  }

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to access Policy Hub on behalf of the signed-in user."
      admin_consent_display_name = "Access Policy Hub"
      user_consent_description   = "Allow the application to access Policy Hub on your behalf."
      user_consent_display_name  = "Access Policy Hub"
      enabled                    = true
      id                         = random_uuid.access_as_user_scope.result
      type                       = "User"
      value                      = "access_as_user"
    }
  }

  # Postman corre como cliente publico (Authorization Code + PKCE, sin
  # client secret) - callback estandar documentado por Postman para su
  # flujo de OAuth2.
  public_client {
    redirect_uris = ["https://oauth.pstmn.io/v1/callback"]
  }

  fallback_public_client_enabled = true

  tags = ["agent-platform"]
}

# Azure CLI (client id publico y conocido de Microsoft) pre-autorizado para
# el scope access_as_user: sin esto, `az account get-access-token` y
# DefaultAzureCredential (demo de Streamlit) piden consentimiento
# interactivo (AADSTS65001) para pedir tokens de esta API.
resource "azuread_application_pre_authorized" "azure_cli" {
  application_id       = azuread_application.policy_hub.id
  authorized_client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
  permission_ids       = [random_uuid.access_as_user_scope.result]
}

resource "azuread_service_principal" "policy_hub" {
  client_id = azuread_application.policy_hub.client_id
  owners    = [data.azuread_client_config.current.object_id]

  # Los owners los fija quien crea el recurso (el usuario local o la identidad
  # de CI, segun quien corra). Ignorarlos evita que el apply de CI intente
  # quitar al otro dueño, operacion que requiere mas privilegios que OwnedBy.
  lifecycle {
    ignore_changes = [owners]
  }
}
