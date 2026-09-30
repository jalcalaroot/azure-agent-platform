# Mismo storage account de tfstate que el resto de la cuenta, key propio
# para no pisar el state principal de este repo
# (agent-platform/terraform.tfstate). Root deliberadamente separado - mismo
# patron que azure-virtual-network/azure-container-apps/azure-aks-cluster,
# ver CLAUDE.md, seccion "Identidades de CI en state propio".
terraform {
  backend "azurerm" {
    resource_group_name  = "jalcalaroot"
    storage_account_name = "sttfstatejalcalaroot"
    container_name       = "tfstate"
    key                  = "agent-platform-ci/terraform.tfstate"
    use_azuread_auth     = true
  }
}
