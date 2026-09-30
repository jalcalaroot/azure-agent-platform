# Identidades de CI para GitHub Actions via OIDC - sin ningun secreto de
# Azure almacenado en GitHub. Mismo patron que
# azure-virtual-network/azure-container-apps/azure-aks-cluster: "agent"
# (apply, push a main) y "plan" (solo lectura, PRs), RBAC acotado recurso
# por recurso.
#
# Los identity/federated_identity_credential viven en el root separado
# ./ci (state propio, nunca se destruye junto con esta plataforma) - ver
# CLAUDE.md, seccion "Identidades de CI en state propio". Este archivo
# solo las referencia via data source para otorgarles RBAC sobre los
# recursos de ESTE root.
data "azurerm_user_assigned_identity" "ci_agent" {
  name                = "agent-platform-agent"
  resource_group_name = "jalcalaroot"
}

data "azurerm_user_assigned_identity" "ci_plan" {
  name                = "agent-platform-plan"
  resource_group_name = "jalcalaroot"
}

data "azurerm_storage_account" "tfstate" {
  name                = "sttfstatejalcalaroot"
  resource_group_name = "jalcalaroot"
}

resource "azurerm_role_assignment" "ci_agent_rg_contributor" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_user_assigned_identity.ci_agent.principal_id
}

resource "azurerm_role_assignment" "ci_plan_rg_reader" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.ci_plan.principal_id
}

resource "azurerm_role_assignment" "ci_agent_state_write" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_user_assigned_identity.ci_agent.principal_id
}

resource "azurerm_role_assignment" "ci_plan_state_write" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_user_assigned_identity.ci_plan.principal_id
}

resource "azurerm_role_assignment" "ci_agent_state_reader" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.ci_agent.principal_id
}

resource "azurerm_role_assignment" "ci_plan_state_reader" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_user_assigned_identity.ci_plan.principal_id
}

# RBAC de datos de Cosmos DB y Key Vault son operaciones separadas del
# Contributor de ARM que ya tiene ci_agent sobre el resource group -
# otorgadas puntualmente donde se necesitan (ver keyvault.tf; Cosmos DB no
# necesita RBAC de datos para el propio agent, solo la Managed Identity del
# Function App la necesita, ver cosmosdb.tf).
