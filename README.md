# Azure Docs Assistant

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jalcalaroot/azure-docs-assistant/badge)](https://scorecard.dev/viewer/?uri=github.com/jalcalaroot/azure-docs-assistant)

An end-to-end **RAG** (Retrieval-Augmented Generation) service on **Azure AI Foundry**, with **Cosmos DB** as the native vector store, fronted by **API Management**, secured with **Entra ID** and guarded by **Content Safety**. Standalone Terraform project: own backend, own CI/CD, own state. It consumes the outputs of [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network).

## Architecture

```
Client (Streamlit / Postman)
   │  Authorization: Bearer <Entra token>
   ▼
API Management  (Developer, VNet External)      ← only public component
   │  validate-jwt + rate limit (60/min per IP)
   ▼
Function App    (Flex Consumption, private endpoint)
   │  FastAPI + Durable Functions
   │  Content Safety (Prompt Shields) → semantic cache → embed → vector search → generate
   ▼
Cosmos DB (vectors + cache) · AI Foundry (embeddings + chat) · Content Safety
```

Ingestion runs through the same Function App: a Durable orchestrator chunks the READMEs of the project repos, embeds them and stores them in Cosmos DB. Everything except APIM sits behind the private network of `azure-virtual-network`.

Public endpoints: `POST /policyhub/ask`, `POST /policyhub/ingest`, `GET /policyhub/ingest/{id}` (JWT required) and `GET /policyhub/health` (no token).

## Resources deployed

| Resource | Purpose | Module / docs |
|---|---|---|
| Cosmos DB (serverless, vector search) | Knowledge base and semantic cache | [`avm-res-documentdb-databaseaccount` 0.11.0](https://registry.terraform.io/modules/Azure/avm-res-documentdb-databaseaccount/azurerm/0.11.0) |
| Azure AI Foundry (`AIServices`) | `text-embedding-3-small` and `gpt-4.1-mini` deployments | [Overview](https://learn.microsoft.com/en-us/azure/ai-foundry/what-is-ai-foundry) |
| Azure AI Content Safety | Prompt Shields on input, severity filter on output | [Overview](https://learn.microsoft.com/en-us/azure/ai-services/content-safety/overview) |
| Function App (Flex Consumption) + storage | FastAPI and Durable Functions, managed identity only | [`avm-res-web-site` 0.23.0](https://registry.terraform.io/modules/Azure/avm-res-web-site/azurerm/0.23.0), [`avm-res-storage-storageaccount` 0.10.0](https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/0.10.0) |
| API Management (Developer, VNet External) | Public gateway: JWT validation and rate limiting | [`avm-res-apimanagement-service` 0.9.0](https://registry.terraform.io/modules/Azure/avm-res-apimanagement-service/azurerm/0.9.0) |
| Application Insights | Function App telemetry | [`avm-res-insights-component` 0.4.0](https://registry.terraform.io/modules/Azure/avm-res-insights-component/azurerm/0.4.0) |
| App Registration (Entra ID) | `access_as_user` scope validated by APIM | [Register an app](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) |
| Role assignments | RBAC for the Function App identity | [`avm-res-authorization-roleassignment` 0.3.1](https://registry.terraform.io/modules/Azure/avm-res-authorization-roleassignment/azurerm/0.3.1) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5.0 and [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az login`, Contributor on the subscription)
- [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network) deployed: this project needs its `privatelink`, `apim` and `func` subnets, the VNet and the Log Analytics workspace
- Microsoft Graph application role `Application.ReadWrite.OwnedBy` (or `.All`) for whoever runs the first `apply`, to create the App Registration

## Usage

```bash
az login
export TF_VAR_subscription_id="<subscription-id>"
export TF_VAR_tenant_id="<tenant-id>"
export TF_VAR_apim_publisher_email="<email>"
# plus the five TF_VAR_network_* values from azure-virtual-network

terraform init && terraform apply
```

Deploy the app (the Function App is private, so the script opens public access only for the deploy and always closes it), then smoke-test through the gateway:

```bash
scripts/deploy-app.sh
export API_BASE_URL="$(terraform output -raw api_base_url)"
TOKEN=$(az account get-access-token --scope api://policy-hub/.default --query accessToken -o tsv)
scripts/smoke-test.sh "$API_BASE_URL" "$TOKEN" --ingest
```

Demo UI and Postman:

```bash
python3 -m venv .venv && .venv/bin/pip install -r demo/requirements.txt
GATEWAY_URL="$API_BASE_URL" .venv/bin/streamlit run demo/streamlit_app.py   # http://localhost:8501
```

A Postman collection is in `demo/postman/`. Unit tests: `cd app && pip install -r requirements-dev.txt && pytest`.

## Configuration

Defaults live in [`variables.tf`](variables.tf). The ones you will most likely touch:

| Variable | Default | Notes |
|---|---|---|
| `subscription_id`, `tenant_id`, `apim_publisher_email` | none | via `TF_VAR_*` |
| `network_*` (5 variables) | none | outputs of `azure-virtual-network` |
| `resource_group_name` / `location` | `jalcalaroot` / `eastus` | |
| `function_app_name`, `apim_name`, `cosmos_account_name` | `func-jalcalaroot-agent`, `apim-jalcalaroot-agent`, `cosmos-agent-platform` | globally unique |
| `chat_model_name` / `chat_model_version` | `gpt-4.1-mini` / `2025-04-14` | non-reasoning model, accepts `temperature` |
| `embedding_model_name` | `text-embedding-3-small` | |

## Outputs

| Output | Description |
|---|---|
| `api_base_url` | Gateway base URL (`<base>/ask`, `/ingest`, `/health`) |
| `apim_gateway_url` / `apim_id` | APIM gateway URL and resource ID |
| `app_registration_client_id` / `app_registration_identifier_uri` | OAuth client settings for Postman and Streamlit |
| `cosmos_account_endpoint`, `ai_foundry_endpoint`, `function_app_name`, … | Endpoints and IDs of the other resources |

## CI/CD

GitHub Actions authenticated to Azure through OIDC, with no stored credentials.

| Workflow | Trigger | Identity | What it does |
|---|---|---|---|
| `terraform-plan.yml` | Pull request | `agent-platform-plan` (read-only) | fmt, validate, tflint, Checkov, plan posted on the PR |
| `terraform-apply.yml` | Push to `main` | `agent-platform-agent` | plan and apply |
| `gitleaks.yml` | PR / push | none | Secret scanning |

Both identities live in the persistent [`ci/`](ci) root. Required repository variables: `ARM_CLIENT_ID_AGENT`, `ARM_CLIENT_ID_PLAN`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, `NETWORK_PRIVATELINK_SUBNET_ID`, `NETWORK_APIM_SUBNET_ID`, `NETWORK_FUNC_SUBNET_ID`, `NETWORK_VNET_ID`, `NETWORK_LOG_ANALYTICS_WORKSPACE_ID`; required secret: `APIM_PUBLISHER_EMAIL`.

Design decisions, known gaps and project history are in [CLAUDE.md](CLAUDE.md).
