# Componente 7 - API Management (tier Developer, VNet External), unico punto
# de entrada publico del sistema. Reemplaza al Application Gateway + WAF de
# la primera version de este repo: ver CLAUDE.md, "De Application Gateway a
# API Management", y "Front Door Standard (documentado, no desplegado)".
#
# Modo External: el gateway queda publico (<apim_name>.azure-api.net) y, al
# estar inyectado en la subnet snet-apim de azure-virtual-network, llega al
# Function App por su Private Endpoint. Sin Front Door ni WAF delante, la
# proteccion de esta capa es validate-jwt (Entra ID) + rate limiting.
#
# Tier Developer: sin SLA, una sola unidad, el gateway se cae durante los
# updates de infraestructura - aceptable para una POC, no para produccion.
locals {
  apim_api_path = "policyhub"
}

# IP publica Standard propia para la inyeccion en VNet (en modo External es
# opcional - Azure puede gestionar una - pero la primera activacion con IP
# gestionada fallo con ActivationFailed). El domain_name_label da el FQDN
# que APIM usa para la IP.
resource "azurerm_public_ip" "apim" {
  name                = "pip-${var.apim_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.apim_name
  tags                = local.tags
}

module "apim" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry, no un git tag.
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.9.0"

  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  tags                = local.tags

  enable_telemetry = false

  sku_name = "Developer_1"

  # No hay ningun ejemplo del modulo con Developer + VNet, ver CLAUDE.md,
  # "Gaps y bugs reales".
  virtual_network_type      = "External"
  virtual_network_subnet_id = var.network_apim_subnet_id
  public_ip_address_id      = azurerm_public_ip.apim.id

  apis = {
    policy_hub = {
      display_name = "Policy Hub"
      # Real error encontrado en `terraform validate`: la AVM valida
      # `^[^*#&+:<>?]+$` sobre el path, o sea que un path vacio (API en la
      # raiz del gateway) no se acepta - de ahi el prefijo /policyhub.
      path                  = local.apim_api_path
      protocols             = ["https"]
      service_url           = "https://${var.function_app_name}.azurewebsites.net"
      subscription_required = false # la autenticacion es el JWT, no subscription keys

      policy = {
        xml_content = <<-XML
          <policies>
            <inbound>
              <base />
              <rate-limit-by-key calls="60" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
              <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
                <openid-config url="https://login.microsoftonline.com/${var.tenant_id}/v2.0/.well-known/openid-configuration" />
                <audiences>
                  <audience>${azuread_application.policy_hub.client_id}</audience>
                  <audience>${var.app_registration_identifier_uri}</audience>
                </audiences>
                <issuers>
                  <issuer>https://login.microsoftonline.com/${var.tenant_id}/v2.0</issuer>
                </issuers>
                <required-claims>
                  <claim name="scp" match="any">
                    <value>access_as_user</value>
                  </claim>
                </required-claims>
              </validate-jwt>
            </inbound>
            <backend>
              <base />
            </backend>
            <outbound>
              <base />
            </outbound>
            <on-error>
              <base />
            </on-error>
          </policies>
        XML
      }

      operations = {
        ask = {
          display_name = "Ask"
          method       = "POST"
          url_template = "/ask"
        }
        ingest = {
          display_name = "Ingest"
          method       = "POST"
          url_template = "/ingest"
        }
        ingest_status = {
          display_name = "Ingest status"
          method       = "GET"
          url_template = "/ingest/{instance_id}"
          template_parameters = [{
            name     = "instance_id"
            required = true
            type     = "string"
          }]
        }
        health = {
          display_name = "Health"
          method       = "GET"
          url_template = "/health"

          # Sin <base /> en inbound: no hereda validate-jwt ni el rate limit
          # del API, /health responde sin token.
          policy = {
            xml_content = <<-XML
              <policies>
                <inbound />
                <backend>
                  <base />
                </backend>
                <outbound />
                <on-error />
              </policies>
            XML
          }
        }
      }
    }
  }
}
