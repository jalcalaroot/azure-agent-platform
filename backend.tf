# Mismo storage account de tfstate que el resto de la cuenta
# (sttfstatejalcalaroot, RG jalcalaroot), key propio para no pisar el state
# de ningun otro proyecto. use_azuread_auth = true - ese storage account
# tiene shared_access_key_enabled = false, el acceso es 100% via RBAC.
terraform {
  backend "azurerm" {
    resource_group_name  = "jalcalaroot"
    storage_account_name = "sttfstatejalcalaroot"
    container_name       = "tfstate"
    key                  = "agent-platform/terraform.tfstate"
    use_azuread_auth     = true
  }
}
