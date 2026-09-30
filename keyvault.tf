# Key Vault - unico proposito hoy: alojar el certificado TLS (autofirmado,
# ver variable app_gateway_cert_subject) que consume el listener HTTPS del
# Application Gateway (app_gateway.tf). Mismo patron de AVM que
# azure-virtual-network/keyvault.tf.
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  #checkov:skip=CKV_AZURE_110:purge protection deliberadamente off - habilitarla es irreversible y bloquea el ciclo destroy/recreate de este proyecto (mismo criterio que azure-virtual-network).
  #checkov:skip=CKV_AZURE_42:mismo motivo que CKV_AZURE_110.
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags

  enable_telemetry = false

  sku_name                      = "standard"
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = false

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  private_endpoints = {
    vault = {
      subnet_resource_id            = var.network_privatelink_subnet_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.vaultcore.id]
    }
  }

  diagnostic_settings = {
    sendToLogAnalytics = {
      workspace_resource_id = var.network_log_analytics_workspace_id
    }
  }

  # RBAC de datos para poder crear azurerm_key_vault_certificate.appgw
  # (operacion de data-plane, no cubierta por el Contributor de ARM que ya
  # tienen las identidades de CI sobre el resource group) - otorgado tanto
  # al agent (aplica el certificado) como a quien corra el primer apply
  # manual local.
  role_assignments = {
    ci_agent_certificates_officer = {
      role_definition_id_or_name = "Key Vault Certificates Officer"
      principal_id               = data.azurerm_user_assigned_identity.ci_agent.principal_id
    }
    current_user_certificates_officer = {
      role_definition_id_or_name = "Key Vault Certificates Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    function_app_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = azurerm_user_assigned_identity.function_app.principal_id
    }
  }
}

resource "azurerm_private_dns_zone" "vaultcore" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vaultcore" {
  name                  = "link-vaultcore-agent-platform"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.vaultcore.name
  virtual_network_id    = var.network_vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

# Certificado TLS autofirmado, generado por el propio Key Vault (issuer
# "Self" - no depende de ninguna Certificate Authority externa). Sin
# dominio publico asignado a este proyecto todavia, ver variable
# app_gateway_cert_subject.
resource "azurerm_key_vault_certificate" "appgw" {
  name         = "cert-${var.app_gateway_name}"
  key_vault_id = module.key_vault.resource_id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]
      subject            = var.app_gateway_cert_subject
      validity_in_months = 12
    }
  }
}

# El secret-plano (PFX + private key, base64) vive bajo el mismo nombre que
# el certificate en el vault - es el unico dato que puede alimentar
# ssl_certificates[].properties.data de la AVM de Application Gateway (el
# recurso azurerm_key_vault_certificate NO expone la private key en sus
# atributos certificate_data*, solo el secret si lo hace).
data "azurerm_key_vault_secret" "appgw_cert" {
  name         = azurerm_key_vault_certificate.appgw.name
  key_vault_id = module.key_vault.resource_id

  depends_on = [azurerm_key_vault_certificate.appgw]
}
