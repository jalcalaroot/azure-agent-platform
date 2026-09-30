# Componente 7b - Application Gateway (WAF_v2), unico punto de exposicion
# publica de todo el sistema. Backend pool apunta al hostname del Function
# App - resuelve a su Private Endpoint gracias al Private DNS Zone
# (privatelink.azurewebsites.net) ya linkeada a la VNet en function_app.tf,
# igual que cualquier otro recurso dentro de esa VNet.
resource "azurerm_public_ip" "appgw" {
  name                = "pip-${var.app_gateway_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # requerido por Application Gateway v2
  tags                = local.tags
}

# ID determinístico del gateway, mismo patron documentado en el ejemplo
# oficial de esta AVM ("selfssl_waf_https_app_gateway") para referenciar
# sub-recursos (listeners/pools/settings/rules) entre si antes de que
# existan, dentro del mismo apply.
locals {
  agw_id = "${data.azurerm_resource_group.this.id}/providers/Microsoft.Network/applicationGateways/${var.app_gateway_name}"
}

module "app_gateway" {
  source  = "Azure/avm-res-network-applicationgateway/azurerm"
  version = "0.5.3"

  name      = var.app_gateway_name
  location  = var.location
  parent_id = data.azurerm_resource_group.this.id
  tags      = local.tags

  enable_telemetry = false

  sku = {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration = {
    min_capacity = 1
    max_capacity = 2 # punto de partida cost-conscious, ajustar contra trafico real
  }

  firewall_policy = {
    id = module.waf_policy.resource_id
  }

  gateway_ip_configurations = [
    {
      name = "appGatewayIpConfig"
      properties = {
        subnet = {
          id = var.network_appgw_subnet_id
        }
      }
    }
  ]

  frontend_ip_configurations = [
    {
      name = "feIpPublic"
      properties = {
        public_ip_address = {
          id = azurerm_public_ip.appgw.id
        }
      }
    }
  ]

  frontend_ports = [
    {
      name = "port443"
      properties = {
        port = 443
      }
    }
  ]

  backend_address_pools = [
    {
      name = "beFunctionApp"
      properties = {
        backend_addresses = [
          { fqdn = "${var.function_app_name}.azurewebsites.net" },
        ]
      }
    }
  ]

  backend_http_settings_collection = [
    {
      name = "functionAppHttpSettings"
      properties = {
        port                                = 443
        protocol                            = "Https"
        pick_host_name_from_backend_address = true # Host header = FQDN del backend, requerido por Azure Functions
        request_timeout                     = 30
      }
    }
  ]

  http_listeners = [
    {
      name = "httpsListener"
      properties = {
        frontend_ip_configuration = {
          id = "${local.agw_id}/frontendIPConfigurations/feIpPublic"
        }
        frontend_port = {
          id = "${local.agw_id}/frontendPorts/port443"
        }
        protocol = "Https"
        ssl_certificate = {
          id = "${local.agw_id}/sslCertificates/${var.app_gateway_name}-cert"
        }
      }
    }
  ]

  request_routing_rules = [
    {
      name = "ruleAsk"
      properties = {
        rule_type = "Basic"
        priority  = 100
        http_listener = {
          id = "${local.agw_id}/httpListeners/httpsListener"
        }
        backend_address_pool = {
          id = "${local.agw_id}/backendAddressPools/beFunctionApp"
        }
        backend_http_settings = {
          id = "${local.agw_id}/backendHttpSettingsCollection/functionAppHttpSettings"
        }
      }
    }
  ]

  ssl_certificates = [
    {
      name = "${var.app_gateway_name}-cert"
      properties = {
        data     = data.azurerm_key_vault_secret.appgw_cert.value
        password = ""
      }
    }
  ]
}
