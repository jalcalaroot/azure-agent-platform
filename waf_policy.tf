# Componente 7a - WAF Policy (OWASP, modo Prevention), asociada al
# Application Gateway en app_gateway.tf vía firewall_policy externo -
# patron recomendado por la propia doc de la AVM de Application Gateway
# sobre el classic waf_configuration inline.
module "waf_policy" {
  source  = "Azure/avm-res-network-applicationgatewaywebapplicationfirewallpolicy/azurerm"
  version = "0.2.0"

  name                = var.waf_policy_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  enable_telemetry = false

  managed_rules = {
    managed_rule_set = {
      owasp = {
        type    = "OWASP"
        version = "3.2"
      }
    }
  }

  policy_settings = {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb     = 100
  }
}
