plugin "azurerm" {
  enabled = true
  version = "0.32.0" # verificar/actualizar contra la última release de tflint-ruleset-azurerm
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Mismo criterio que azure-virtual-network: este proyecto esta pensado para
# destruirse/recrearse frecuentemente (recursos de costo real - NAT
# Gateway ya en azure-virtual-network, Cosmos DB, AI Foundry, App Gateway
# aca), un lint empujando hacia prevent_destroy pelearia contra ese diseno.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
