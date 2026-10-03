# azure-agent-platform

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jalcalaroot/azure-agent-platform/badge)](https://scorecard.dev/viewer/?uri=github.com/jalcalaroot/azure-agent-platform)

RAG (Retrieval-Augmented Generation) end-to-end sobre Azure AI Foundry, con Cosmos DB como vector store nativo, detrás de Application Gateway + WAF, identidad de aplicación vía Entra ID y guardrails de Content Safety. Standalone Terraform project — own backend, own CI/CD, own state; consume los outputs de [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network).

## Architecture

```
INGESTA (offline)

  README de un repo propio (público)
        │
        ▼
  Durable Function orchestrator
  (chunk_document → generate_embeddings → store_in_cosmos)


CONSULTA (en caliente)

  Cliente (Postman / Streamlit)
        │  Authorization: Bearer <token>
        ▼
  Application Gateway (WAF_v2)
        │
        ▼
  Function App (Flex Consumption)
  FastAPI + Durable Functions
  - App Registration valida el token
  - Content Safety filtra input/output
  - check semantic_cache → si no hay hit: embed → vector search → generate
  - log en Cosmos DB
```

Todo detrás de la red privada de [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network) — Application Gateway es el único componente con exposición pública de todo el sistema.

## Resources deployed

| Resource | Purpose | Docs |
|---|---|---|
| Cosmos DB (serverless, vector search) | Vector store para retrieval + caché semántica; built on [`Azure/avm-res-documentdb-databaseaccount` v0.11.0](https://registry.terraform.io/modules/Azure/avm-res-documentdb-databaseaccount/azurerm/0.11.0) | [Vector search in Azure Cosmos DB](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/vector-search) |
| Azure AI Foundry (Cognitive Services, kind `AIServices`) | Deployments de embeddings + chat; sin AVM dedicada todavía | [Azure AI Foundry overview](https://learn.microsoft.com/en-us/azure/ai-foundry/what-is-ai-foundry) |
| Azure AI Content Safety | Prompt Shields (input) + filtro de severidad (output); sin AVM dedicada todavía | [Content Safety overview](https://learn.microsoft.com/en-us/azure/ai-services/content-safety/overview) |
| Function App (Flex Consumption) | FastAPI + Durable Functions, endpoint `/ask`; built on [`Azure/avm-res-web-site` v0.23.0](https://registry.terraform.io/modules/Azure/avm-res-web-site/azurerm/0.23.0) | [Flex Consumption plan](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan) |
| Application Gateway (WAF_v2) | Único punto de exposición pública del sistema; built on [`Azure/avm-res-network-applicationgateway` v0.5.3](https://registry.terraform.io/modules/Azure/avm-res-network-applicationgateway/azurerm/0.5.3) | [Application Gateway overview](https://learn.microsoft.com/en-us/azure/application-gateway/overview) |
| WAF Policy (OWASP 3.2, Prevention) | Reglas aplicadas por el Application Gateway; built on [`Azure/avm-res-network-applicationgatewaywebapplicationfirewallpolicy` v0.2.0](https://registry.terraform.io/modules/Azure/avm-res-network-applicationgatewaywebapplicationfirewallpolicy/azurerm/0.2.0) | [WAF on Application Gateway](https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/ag-overview) |
| Key Vault (Private Endpoint) | Certificado TLS del listener del Application Gateway; built on [`Azure/avm-res-keyvault-vault` v0.11.0](https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm/0.11.0) | [Private Link overview](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview) |
| Application Insights | Telemetría del Function App; built on [`Azure/avm-res-insights-component` v0.4.0](https://registry.terraform.io/modules/Azure/avm-res-insights-component/azurerm/0.4.0) | [Application Insights overview](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview) |
| App Registration (Entra ID) | Valida los tokens del endpoint `/ask` (Postman/Streamlit) | [Register an application](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) |
| Role Assignments | RBAC de la Managed Identity del Function App sobre AI Foundry/Content Safety; built on [`Azure/avm-res-authorization-roleassignment` v0.3.1](https://registry.terraform.io/modules/Azure/avm-res-authorization-roleassignment/azurerm/0.3.1) | [Azure RBAC overview](https://learn.microsoft.com/en-us/azure/role-based-access-control/overview) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), logged in via `az login` con Contributor-or-better en la suscripción
- [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network) ya desplegado — este proyecto consume sus subnets (`privatelink`, `appgw`, `func`) y su Log Analytics Workspace, copiados a mano (sin `terraform_remote_state`)
- Quien corra el primer `apply` necesita el rol de aplicación de Microsoft Graph `Application.ReadWrite.OwnedBy` (o `.All`) para crear la App Registration/Service Principal

## Usage

```bash
az login
export TF_VAR_subscription_id="<subscription-id>"
export TF_VAR_tenant_id="<tenant-id>"

terraform init
terraform apply
```

`resource_group_name`/`location` default a `jalcalaroot`/`eastus`. Las 5 variables `network_*` (subnets + Log Analytics Workspace de `azure-virtual-network`) no tienen default — pasarlas explícitamente.

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `subscription_id` | — | via `TF_VAR_subscription_id` |
| `tenant_id` | — | via `TF_VAR_tenant_id`, requerido por el provider `azuread` |
| `resource_group_name` / `location` | `jalcalaroot` / `eastus` | |
| `network_privatelink_subnet_id` / `network_appgw_subnet_id` / `network_function_app_subnet_id` / `network_vnet_id` / `network_log_analytics_workspace_id` | — | outputs de `azure-virtual-network`, copiados a mano |
| `cosmos_account_name` | `cosmos-agent-platform` | único globalmente |
| `ai_foundry_account_name` / `content_safety_account_name` | `aif-agent-platform` / `cs-agent-platform` | únicos globalmente (custom subdomain) |
| `embedding_model_name` / `embedding_model_version` | `text-embedding-3-small` / `1` | |
| `chat_model_name` / `chat_model_version` | `gpt-4o-mini` / `2024-07-18` | |
| `function_app_name` / `function_app_storage_account_name` | `func-agent-platform` / `stagentplatformfunc` | storage único globalmente |
| `fc1_instance_memory_mb` / `fc1_maximum_instance_count` | `2048` / `100` | |
| `fc1_python_version` | `3.12` | |
| `app_gateway_name` / `waf_policy_name` | `agw-agent-platform` / `waf-agent-platform` | |
| `app_gateway_cert_subject` | `CN=agent-platform.jalcalaroot.internal` | certificado autofirmado, sin dominio público asignado todavía |
| `key_vault_name` | `kv-agent-platform` | único globalmente |
| `app_registration_display_name` / `app_registration_identifier_uri` | `policy-hub` / `api://policy-hub` | |
| `owner` / `environment` / `tags` | `johan` / `dev` / `{}` | |

## Outputs

| Output | Description |
|---|---|
| `cosmos_account_id` / `cosmos_account_endpoint` | Cosmos DB resource ID / endpoint |
| `ai_foundry_account_id` / `ai_foundry_endpoint` | AI Foundry resource ID / endpoint |
| `content_safety_account_id` | Content Safety resource ID |
| `function_app_id` / `function_app_name` / `function_app_identity_principal_id` | Function App resource ID, nombre, y el principal ID de su Managed Identity |
| `app_gateway_public_ip` | IP pública — único punto de entrada del sistema |
| `app_registration_client_id` / `app_registration_identifier_uri` | Para configurar el cliente OAuth (Postman/Streamlit) |
| `key_vault_id` | Key Vault resource ID |

## CI/CD

GitHub Actions, autenticado contra Azure vía OIDC (Workload Identity Federation) — sin secretos ni credenciales estáticas en GitHub.

| Workflow | Trigger | Identity | What it does |
|---|---|---|---|
| `terraform-plan.yml` | Pull request | `agent-platform-plan` (read-only) | `fmt -check`, `validate`, tflint, Checkov (blocking), `plan`, posts the plan as a PR comment |
| `terraform-apply.yml` | Push to `main` | `agent-platform-agent` | `plan` + `apply` |
| `gitleaks.yml` | PR / push to `main` | — | Secret scanning |

Ambas identidades viven en un root de Terraform persistente ([`./ci`](./ci)), separado del state destruible de este proyecto. Required GitHub repository variables: `ARM_CLIENT_ID_AGENT`, `ARM_CLIENT_ID_PLAN`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`.

See [CLAUDE.md](CLAUDE.md) for design decisions, gaps conocidos, y el historial completo del proyecto.
