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

# `plan` refresca el estado real. Con recursos ya desplegados, el provider
# llama a dos acciones POST `list*` que Reader no incluye (403 en el check
# Plan del PR #1): claves de Cosmos DB y la clave de delegacion de APIM. Rol
# personalizado minimo, asignado solo sobre esos dos recursos y no al RG.
# Tambien necesita el rol de aplicacion Graph `Application.Read.All` (lo lee
# `azuread_application`); es un consentimiento manual, ver CLAUDE.md, gap 9.
resource "azurerm_role_definition" "ci_plan_refresh" {
  name        = "agent-platform-plan-refresh"
  scope       = data.azurerm_resource_group.this.id
  description = "Acciones list* que terraform plan necesita al refrescar Cosmos DB y APIM."

  permissions {
    actions = [
      "Microsoft.DocumentDB/databaseAccounts/listKeys/action",
      "Microsoft.ApiManagement/service/portalsettings/listSecrets/action",
    ]
  }

  assignable_scopes = [data.azurerm_resource_group.this.id]
}

resource "azurerm_role_assignment" "ci_plan_cosmos_refresh" {
  scope              = module.cosmos.resource_id
  role_definition_id = azurerm_role_definition.ci_plan_refresh.role_definition_resource_id
  principal_id       = data.azurerm_user_assigned_identity.ci_plan.principal_id
}

resource "azurerm_role_assignment" "ci_plan_apim_refresh" {
  scope              = module.apim.resource_id
  role_definition_id = azurerm_role_definition.ci_plan_refresh.role_definition_resource_id
  principal_id       = data.azurerm_user_assigned_identity.ci_plan.principal_id
}
