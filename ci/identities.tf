# Identidades de CI para GitHub Actions via OIDC - state propio, separado
# del root principal, para que este proyecto pueda destruirse y recrearse
# cuantas veces haga falta sin que el CI se rompa - mismo fix ya aplicado en
# azure-virtual-network/azure-aks-cluster/azure-container-apps. Ver
# CLAUDE.md, seccion "Identidades de CI en state propio".
data "azurerm_resource_group" "shared" {
  name = "jalcalaroot"
}

resource "azurerm_user_assigned_identity" "ci_agent" {
  name                = "agent-platform-agent"
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = data.azurerm_resource_group.shared.location
}

resource "azurerm_user_assigned_identity" "ci_plan" {
  name                = "agent-platform-plan"
  resource_group_name = data.azurerm_resource_group.shared.name
  location            = data.azurerm_resource_group.shared.location
}

# Subject claims segun el formato ACTUAL de GitHub para este repo
# (confirmado via `gh api repos/jalcalaroot/azure-docs-assistant` ->
# owner.id=22682982, id=1398572774). Push a main y schedule (cron)
# presentan el MISMO subject claim (ref:refs/heads/main).
resource "azurerm_federated_identity_credential" "ci_agent_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci_agent.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:jalcalaroot@22682982/azure-docs-assistant@1398572774:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "ci_plan_pr" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci_plan.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:jalcalaroot@22682982/azure-docs-assistant@1398572774:pull_request"
}
