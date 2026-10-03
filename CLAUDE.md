# azure-agent-platform

Sistema RAG (Retrieval-Augmented Generation) end-to-end sobre Azure AI Foundry, con Cosmos DB como vector store nativo, detrás de API Management, con identidad de aplicación vía Entra ID y guardrails de Content Safety. Producto/demo interno se llama **Policy Hub** (nombre usado en el scope OAuth `api://policy-hub/access_as_user` y en el título del demo Streamlit) — el repo se llama `azure-agent-platform` porque es el nombre más descriptivo del sistema en sí; no son proyectos distintos, es la misma convención de otros repos (`azure-virtual-network` alojando la red de `jalcalaroot`, sin que el nombre de la cuenta esté en el repo).

## README structure (standard across all `jalcalaroot` Azure repos, 2026-09-30)

README.md es una página de presentación, no un documento de diseño — exactamente 7 secciones, en este orden: **Architecture** (diagrama), **Resources deployed** (tabla: Resource | Purpose | Docs, un link real a docs de Azure por fila), **Prerequisites**, **Usage** (conciso, comandos antes que prosa), **Configuration**, **Outputs**, **CI/CD**. Nada más — sin secciones de Cost, Status, Design notes o changelog, y sin referencias cruzadas a proyectos de otras cuentas cloud. Toda la narrativa — decisiones, historia, gotchas, incidentes — va acá en CLAUDE.md, enlazada desde la última línea del README.

## Qué es este sistema, en una frase

Responde preguntas basándose en contenido propio (los READMEs de otros repos de `jalcalaroot`) — busca los fragmentos más relevantes por similitud vectorial (retrieval) y se los pasa a un modelo de lenguaje para que genere la respuesta (generation), en vez de que el modelo responda solo de memoria.

## Arquitectura

```
INGESTA (offline)

  README de un repo propio (público)
        │
        ▼
┌─────────────────────────────────────┐
│  Durable Function orchestrator        │
│  1. chunk_document                    │
│  2. generate_embeddings (AI Foundry)  │
│  3. store_in_cosmos (vector container)│
└─────────────────────────────────────┘


CONSULTA (en caliente)

  Cliente (Postman / Streamlit)
        │  Authorization: Bearer <token>
        ▼
┌─────────────────────────────────────┐
│  API Management (Developer, External)  │
│  - validate-jwt (Entra ID, scp)         │
│  - rate-limit-by-key por IP             │
└─────────────────────────────────────┘
        │  (VNet injection -> Private Endpoint)
        ▼
┌─────────────────────────────────────┐
│  Function App (Flex Consumption)       │
│  FastAPI + Durable Functions            │
│  - Content Safety filtra input          │
│  - check semantic_cache                 │
│  - si no hay hit:                       │
│      embed_query (AI Foundry)           │
│      vector_search (Cosmos DB)          │
│      generate_answer (AI Foundry)       │
│      Content Safety filtra output       │
│      guarda en semantic_cache           │
│  - log en Cosmos DB                     │
└─────────────────────────────────────┘
```

Todo detrás de la red privada de [`azure-virtual-network`](https://github.com/jalcalaroot/azure-virtual-network) — este repo consume sus outputs (`privatelink_subnet_id`, `apim_subnet_id`, `func_subnet_id`, VNet y Log Analytics), mismo patrón que `azure-container-apps`/`azure-aks-cluster`. API Management es el único componente con exposición pública de todo el sistema (endpoints `POST /policyhub/ask` y `GET /policyhub/health`).

## Componentes

1. **Cosmos DB** — Serverless, NoSQL API, capacidad vectorial habilitada. Containers: `requests`, `orchestrations`, `knowledge_base` (vector index), `semantic_cache`. Private Endpoint, RBAC de datos (Cosmos DB Built-in Data Contributor), sin access keys.
2. **Durable Function (ingesta)** — Adaptado del quickstart oficial de Microsoft ([`Azure-Samples/durable-functions-quickstart-python-azd`](https://github.com/Azure-Samples/durable-functions-quickstart-python-azd)), no escrito desde cero. Orchestrator `ingest_document`: `chunk_document` → `generate_embeddings` (fan-out) → `store_in_cosmos`. Idempotente (id determinístico por chunk).
3. **Function App consolidado (FastAPI + Durable Functions)** — Un solo Function App, FastAPI corriendo vía `AsgiMiddleware` (patrón oficial de Microsoft), sin segundo servicio de compute. Plan Flex Consumption (único que soporta Private Endpoint inbound + VNet integration a la vez). Identity: User Assigned Managed Identity.
4. **API Management (Developer, VNet External)** — Reemplaza al Application Gateway + WAF_v2 de la primera versión (ver "De Application Gateway a API Management"). Valida el JWT con `validate-jwt` contra Entra ID (audiencia = client_id de la App Registration, claim `scp` = `access_as_user`), aplica `rate-limit-by-key` por IP, y reenvía al Function App por su Private Endpoint. `/health` queda sin JWT.
5. **Azure AI Foundry** — Deployments: embeddings (`text-embedding-3-small`) + chat (`gpt-4o-mini` o Claude Sonnet). Acceso vía SDK + Managed Identity, sin API keys.
6. **Azure AI Content Safety** — Cognitive Services account, kind `ContentSafety`. Prompt Shields (input, incluye indirect injection) + filtro de severidad (output).

## Decisiones de arquitectura clave

- **Un solo Function App, no dos servicios de compute separados.** FastAPI vía `AsgiMiddleware` dentro del mismo host de Durable Functions — evita duplicar identidad administrada, red, y pipeline de CI/CD para lo que en el fondo es un único plano de ejecución (ingesta + consulta).
- **Plan Flex Consumption, no Premium ni Consumption clásico.** Es el único plan de Azure Functions que soporta Private Endpoint *inbound* (para recibir tráfico de API Management) simultáneamente con VNet integration *outbound* (para llegar a Cosmos DB/AI Foundry/Content Safety sin salir a internet).
- **Sin API keys en ningún punto del sistema.** Cosmos DB (RBAC de datos, Built-in Data Contributor), AI Foundry y Content Safety — todo vía la misma User Assigned Managed Identity del Function App. Mismo criterio ya aplicado a Key Vault/Storage en `azure-virtual-network`.
- **Durable Function de ingesta: clonado del quickstart oficial, no escrito desde cero** — para heredar los patrones ya validados por Microsoft (orchestrator/activity functions, Durable Task Scheduler) en vez de reinventarlos, y adaptarlos al dominio (chunking + embeddings + Cosmos en vez del ejemplo genérico del quickstart).
- **CI/CD desde el día uno, no al final.** Identidades `plan` (solo lectura) y `apply` (escritura) separadas, OIDC, Checkov bloqueante + gitleaks — mismo esquema que `azure-virtual-network`/`azure-aks-cluster`/`azure-container-apps`, aplicado component por componente a medida que se agregan recursos, no retrofiteado al final.
- **Todo vía Terraform + Azure Verified Modules (AVM), pinneados a versión exacta** donde exista un módulo real — mismo criterio ya establecido en el resto de la cuenta (ver `azure-virtual-network`'s CLAUDE.md, "Rebuilt on Azure Verified Modules"). `App Registration` (provider `azuread`) y `Content Safety` (`azurerm_cognitive_account`) se quedan como recursos crudos porque no existe AVM equivalente hoy.

### Tabla de módulos AVM (IaC)

| Recurso | Módulo |
|---|---|
| Cosmos DB | `Azure/avm-res-documentdb-databaseaccount/azurerm` |
| Function App | `Azure/avm-res-web-site/azurerm` |
| API Management | `Azure/avm-res-apimanagement-service/azurerm` |
| Application Insights | `Azure/avm-res-insights-component/azurerm` |
| Role Assignments | `Azure/avm-res-authorization-roleassignment/azurerm` |
| App Registration | `azuread_application` (provider `azuread`, sin AVM) |
| Content Safety | `azurerm_cognitive_account` (sin AVM dedicado aún) |

Application Gateway, WAF Policy y Key Vault estuvieron en esta tabla en la primera versión y se removieron (ver "De Application Gateway a API Management").

Versiones exactas a pinnear se confirman contra el Registry al implementar cada componente (mismo criterio que `azure-virtual-network`: nunca asumir la versión desde la doc, verificar contra `terraform init`/el Registry en el momento).

## Todo el Terraform escrito de una sola vez (2026-09-30)

Decisión del usuario: en vez de ir componente por componente con confirmación entre cada uno (como dice "Orden de implementación" abajo), escribir todo el Terraform de los 6 componentes + CI/CD de una vez, para revisar todo junto. `terraform fmt`/`init -backend=false`/`validate` corridos contra los dos roots (raíz y `./ci`) para confirmar que el HCL es sintácticamente válido - sin `plan`/`apply`, sin tocar ningún recurso real de Azure (regla explícita del usuario). `validate` pasó limpio en ambos roots después de corregir 2 bugs reales encontrados en el proceso (ver "Gaps y bugs reales encontrados" abajo).

Versiones AVM exactas confirmadas contra el Terraform Registry (`mcp__terraform`, 2026-09-30):

| Módulo | Versión |
|---|---|
| `avm-res-documentdb-databaseaccount` | 0.11.0 |
| `avm-res-web-site` | 0.23.0 |
| `avm-res-apimanagement-service` | 0.9.0 (agregado 2026-10-03, reemplaza a `avm-res-network-applicationgateway` 0.5.3, `avm-res-network-applicationgatewaywebapplicationfirewallpolicy` 0.2.0 y `avm-res-keyvault-vault` 0.11.0 de la primera versión) |
| `avm-res-insights-component` | 0.4.0 |
| `avm-res-authorization-roleassignment` | 0.3.1 |
| `avm-res-storage-storageaccount` | 0.10.0 (Function App deployment storage - no está en la tabla de componentes del documento de requisitos, pero sí en la convención general de la cuenta, ver "Decisiones de arquitectura clave") |

## Gaps y bugs reales encontrados (no asumidos - confirmados contra el Registry, el provider, o `terraform validate`)

1. **`Azure/avm-res-authorization-roleassignment` NO soporta RBAC de data-plane de Cosmos DB** - solo `Microsoft.Authorization/roleAssignments` (control-plane). Confirmado con grep completo de su doc: cero matches para "cosmos"/"sqlRoleAssignment". El RBAC de datos del Function App sobre Cosmos (`Cosmos DB Built-in Data Contributor`) usa el recurso crudo `azurerm_cosmosdb_sql_role_assignment` en `cosmosdb.tf`, referenciando el rol built-in por su GUID fijo (`00000000-0000-0000-0000-000000000002`) sin necesidad de un `sql_role_definition` custom.
2. **Ni `avm-res-documentdb-databaseaccount` ni el recurso nativo `azurerm_cosmosdb_sql_container` (provider azurerm 5.7.0) exponen `vectorEmbeddingPolicy`/vector index** en su schema de containers - el módulo solo permite prender el capability de cuenta `EnableNoSQLVectorSearch`. Los 2 containers que necesitan búsqueda vectorial (`knowledge_base`, `semantic_cache`) se declaran como `azapi_resource` (ARM crudo) en `cosmosdb.tf`.
3. **El body de `vectorEmbeddingPolicy`/`indexingPolicy.vectorIndexes` de esos `azapi_resource` falló `terraform validate`** contra la API version estable `2024-08-15` ("no es esperado aquí, ¿quisiste decir `indexingPolicy`?") - vector search en Cosmos DB NoSQL vive en una superficie de API que el schema embebido de azapi no reconoce para esa versión. Fix aplicado: `schema_validation_enabled = false` en esos 2 recursos, con el body basado en el schema documentado por Microsoft para Vector Search - **sin verificar todavía contra un `plan`/`apply` real**. Confirmar ahí antes de asumir que estos 2 containers funcionan.
4. **`avm-res-web-site` (Function App) no expone el Service Plan** - el patrón documentado en el propio ejemplo oficial del módulo (`flex_consumption`) es crear el Service Plan FC1 como `azapi_resource` aparte (`Microsoft.Web/serverfarms`, `sku.name="FC1"`, `kind="functionapp"`, `properties.reserved=true`) y pasar su ID vía `service_plan_resource_id`. Igual en `function_app.tf`.
5. **`fc1_runtime_name`/`fc1_runtime_version` reemplazan a `site_config.application_stack` en Flex Consumption** - ese bloque se ignora/rechaza en sitios FC1 (ARM error 51021 documentado en el propio módulo). No se declaró `application_stack` en este repo.
6. **Conflicto real de versión del provider `time` entre AVMs usadas en este repo** - fijar un rango propio (`>= 0.12.0, < 0.13.0`, siguiendo lo que documentaba `avm-res-documentdb-databaseaccount`) rompió `terraform init` ("no available releases match the given constraints") porque `avm-res-storage-storageaccount` (usada en `function_app.tf` para el storage de deployment) pide un rango distinto. Fix: no fijar `time` en el `required_providers` de la raíz - mismo criterio que `azure-virtual-network`, que tampoco lo fija (solo fija `azurerm`, el único provider que configura explícitamente).
7. **Dependencia cross-repo, bloquea un apply real hasta que se mergee y aplique**: `azure-virtual-network` no tenía ninguna subnet delegada a `Microsoft.Web/serverFarms` - la VNet integration (outbound) de un Function App Flex Consumption necesita una subnet dedicada a esa delegación, que no puede ser la de `privatelink`. La subnet `func` está escrita en `azure-virtual-network` (PR #32, **todavía abierto**, sin aplicar - la VNet está destruida en Azure). `variables.tf` declara `network_function_app_subnet_id` sin default (falla explícito) hasta que exista el output real.
8. **Subnet `apim`, mismo caso** (2026-10-03): API Management en modo External necesita su propia subnet sin delegation. Escrita en `azure-virtual-network` en la rama `add-apim-subnet` (PR #33, apilado sobre #32), sin aplicar. `network_apim_subnet_id` sin default.
9. **Prerequisito operativo, no de Terraform**: crear `azuread_application`/`azuread_service_principal` requiere que quien corra `apply` (hoy la identidad de CI `agent-platform-agent`) tenga el rol de aplicación de Microsoft Graph `Application.ReadWrite.OwnedBy` (o `.All`) - una Managed Identity puede recibir roles de Graph vía su Service Principal, pero otorgar ese consentimiento requiere un Global Administrator haciéndolo una vez a mano (mismo tipo de paso manual que aplicar `./ci` la primera vez). No automatizado en este repo.
10. **La AVM de API Management rechaza un path de API vacío** - su validación es `^[^*#&+:<>?]+$` (al menos un carácter), encontrada en `terraform validate`. Por eso la API cuelga de `/policyhub` (`POST /policyhub/ask`, `GET /policyhub/health`) en vez de la raíz del gateway; `api_base_url` en los outputs ya incluye el prefijo.
11. **DNS privado de los Private Endpoints, 2 bugs reales corregidos** (2026-10-03): (a) el Private Endpoint de Cosmos DB no tenía zona DNS privada - sin `privatelink.documents.azure.com` linkeada a la VNet, `<cuenta>.documents.azure.com` resolvía a la IP pública y el Function App no podía llegar a Cosmos; ahora `cosmosdb.tf` crea la zona + el link y la pasa en `private_dns_zone_resource_ids`. (b) el storage del Function App usaba una zona inventada `privatelink.blob.core.windows.net.func` que no resuelve nada (el CNAME público de un storage apunta a `<cuenta>.privatelink.blob.core.windows.net`); ahora `function_app.tf` reutiliza por data source la zona real que `azure-virtual-network` ya crea y linkea (no pueden existir dos zonas con el mismo nombre en el mismo resource group). Consecuencia: ese apply requiere `azure-virtual-network` ya desplegado. Sigue sin verificar si AI Foundry necesita además `privatelink.services.ai.azure.com`.
12. **Supuestos de API Management sin verificar contra Azure real** (la AVM 0.9.0 no trae ningún ejemplo con Developer + VNet, todos usan Premium): (a) que Developer en modo External acepte la IP pública gestionada sin `public_ip_address_id` (la doc de Microsoft dice que es opcional en External); (b) que APIM resuelva el Private Endpoint del Function App por la zona `privatelink.azurewebsites.net` linkeada a la VNet (inferido de la doc, no confirmado explícitamente); (c) que el hostname por defecto del Function App sea `<nombre>.azurewebsites.net` y no uno con sufijo único (`service_url` lo asume determinístico); (d) la sintaxis del XML de policy y que la policy de `/health` sin `<base />` omita `validate-jwt`; (e) que la audiencia del token v2 sea el `client_id` (`requested_access_token_version = 2`); (f) el aprovisionamiento de Developer puede tardar bastante más de 15 minutos y el gateway se cae durante los updates de infraestructura (sin SLA).

## De Application Gateway a API Management (2026-10-03)

Decisión del usuario, viniendo de AWS (WAF → API Gateway → Lambda): la capa de entrada pasa de Application Gateway WAF_v2 a **API Management tier Developer** delante del Function App privado. Mapeo AWS → Azure: WAF → Front Door (WAF), API Gateway → API Management, Lambda → Azure Functions. Diferencia de costos que no es 1:1: API Gateway de AWS no tiene costo fijo, APIM sí (Developer ≈ $48/mes, el más barato con VNet injection; Consumption no soporta VNet y Standard v2 ronda $700/mes; Basic v2 no soporta VNet integration).

- **Modo External**: el gateway queda público (`<apim_name>.azure-api.net`) y, inyectado en `snet-apim`, llega al Function App por Private Endpoint. La conexión Function App → Cosmos DB / AI Foundry / Content Safety no cambia: es la VNet integration outbound por la subnet `func`, independiente de lo que esté delante.
- **Sin WAF**: APIM no trae protección OWASP. Para esta POC la protección es `validate-jwt` + `rate-limit-by-key`; se acepta no tener reglas OWASP.
- **Removido**: `app_gateway.tf`, `waf_policy.tf` y `keyvault.tf` (el Key Vault existía solo para el certificado TLS autofirmado del App Gateway; APIM trae el suyo para `azure-api.net`), junto con la zona DNS `vaultcore` y la variable `network_appgw_subnet_id`.
- **Secretos de CI**: `terraform-plan.yml`/`terraform-apply.yml` pasan `TF_VAR_apim_publisher_email` desde el secret `APIM_PUBLISHER_EMAIL` (mismo patrón que `ACME_EMAIL` en `azure-container-apps`) y las 5 variables `network_*` desde GitHub variables `NETWORK_*` - estas últimas faltaban desde la primera versión.

## Front Door Standard (documentado, no desplegado)

Decisión del usuario: documentar Front Door Standard como la capa de edge opcional delante de APIM, **sin desplegarlo** - para esta POC se le pega directo al API de APIM. No hay ningún código Terraform de Front Door en el repo; esto es el diseño verificado para cuando se quiera agregar. Hechos verificados contra Microsoft Learn y el Registry (2026-10-03):

- **WAF de Front Door Standard solo soporta custom rules** (rate limit, filtro IP/geo). Rule sets gestionados (OWASP/DRS), bot protection y **Private Link al origin son solo Premium** (`front-door-cdn-comparison`).
- **Standard → Premium es un upgrade in place, sin downtime** (`tier-upgrade`); **Premium → Standard no está soportado**. Tras el upgrade hay que habilitar a mano los managed rules en la copia de la WAF policy.
- **Facturación**: base fee por hora y solo por las horas usadas - Standard $35/mes, Premium $330/mes (WAF y Private Link incluidos en Premium; en Standard el WAF se factura aparte, tarifa sin verificar). Sin compromiso: se puede dar de baja cuando se quiera.
- **Bloquear el origin (APIM) a este Front Door**: Front Door agrega el header `X-Azure-FDID`; el origen debe rechazar requests cuyo valor no coincida con el ID del profile (una policy `check-header` en APIM, **no verificada** con doc) y se puede restringir la entrada con el service tag `AzureFrontDoor.Backend`, que por sí solo no alcanza ("other Azure customers use the same IP addresses").
- **Módulos AVM**: `Azure/avm-res-cdn-profile/azurerm` **0.1.9** (providers `azapi ~> 2.4`, `azurerm ~> 4.0`; `sku` por defecto `Standard_AzureFrontDoor`; origins con `host_name`/`host_header`/`certificate_name_check_enabled`; WAF asociado vía `front_door_security_policies`) y `Azure/avm-res-network-frontdoorwebapplicationfirewallpolicy/azurerm` **0.1.1** (`name` debe cumplir `^[a-z0-9]{1,80}$`; `managed_rules` trae por defecto DRS 2.1 + BotManager 1.1 y no valida contra el SKU, así que en Standard hay que pasar `managed_rules = []`; `custom_rules` es una lista, mientras que en el input equivalente del cdn-profile es un mapa).
- **Gap conocido**: ningún output del cdn-profile expone el Front Door ID (el profile se crea vía azapi sin `response_export_values`), así que el valor para el check de `X-Azure-FDID` habría que leerlo aparte.
- **Origin público**: Standard no tiene Private Link al origin, así que APIM External debe ser alcanzable por internet - es el caso de este diseño de todos modos.

## Dataset

READMEs de `azure-virtual-network`, `azure-aks-cluster`, `azure-container-apps`, `jalcalaroot-azure-bootstrap` — públicos en GitHub. Sin CVs ni datos personales.

## Fuera de alcance

Escaneo de imágenes, Bicep, AI Foundry Agent Service/MCP, streaming de respuesta, multi-región, Provisioned Throughput. Front Door + WAF delante de API Management: documentado abajo, no desplegado en esta POC.

## Orden de implementación

Cada componente se implementa, se muestra, y espera confirmación antes de pasar al siguiente — no se avanza en paralelo.

1. Azure AI Foundry (modelos + script de prueba suelto)
2. Cosmos DB + emulador local
3. Durable Function — ingesta de los 4 READMEs
4. Function App + FastAPI, endpoint `/ask` end-to-end
5. Content Safety integrado
6. App Registration + validación de tokens
7. API Management (Developer, VNet External) delante del Function App, que pasa a Private Endpoint
8. Postman collection + demo Streamlit

**Ningún `terraform apply`/`az deployment`/`azd up` hasta que el usuario lo confirme explícitamente para cada componente** — el trabajo hasta entonces es código y Terraform local, listo para revisar.

## Testing local

- **Cosmos DB**: emulador vNext en Docker — `docker run -d -p 8081:8081 -p 8080:8080 -p 1234:1234 mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-latest`
- **Durable Functions**: Durable Task Scheduler emulator (`docker run -d -p 8080:8080 -p 8082:8082 mcr.microsoft.com/dts/dts-emulator:latest`, dashboard en `http://localhost:8082`) + Azurite (`docker run -d -p 10000:10000 -p 10001:10001 -p 10002:10002 mcr.microsoft.com/azure-storage/azurite`)

## Status

- 2026-10-03 (latest): Corregidos 2 bugs de DNS privado (Cosmos DB sin zona; zona `.func` inventada del storage del Function App) - ver gap 11. `fmt`/`validate` limpios, sin `plan`/`apply`.
- 2026-10-03: Capa de entrada cambiada de Application Gateway + WAF a API Management Developer (VNet External); Key Vault removido; Front Door Standard documentado sin desplegar. Ver "De Application Gateway a API Management" y "Front Door Standard". `fmt`/`init -backend=false`/`validate` limpios; sin `plan`/`apply`, nada desplegado. Pendiente antes de un apply real: mergear y aplicar las subnets `func` (PR #32) y `apim` (PR #33) en `azure-virtual-network` (hoy destruida), copiar sus outputs a las GitHub variables `NETWORK_*`, y cargar el secret `APIM_PUBLISHER_EMAIL`. Corrección: una nota anterior de este mismo día decía que el PR #32 estaba mergeado; **no lo está**, sigue abierto.
- 2026-10-03: `README.md` agregado, siguiendo el mismo estándar de 7 secciones que el resto de la cuenta (ver "README structure" arriba) - no existía todavía.
- 2026-09-30: Todo el Terraform de los 6 componentes + CI/CD escrito de una sola vez (decisión del usuario, ver sección arriba) - VNet/Cosmos DB/AI Foundry/Content Safety/Function App (Flex Consumption)/App Gateway+WAF/App Registration/Key Vault, identidades de CI en `./ci` (state propio, mismo patrón que el resto de la cuenta), pipelines `terraform-plan`/`terraform-apply`/`gitleaks`/`scorecard`. `terraform fmt`/`validate` pasan limpio en ambos roots (raíz y `./ci`) - sin `plan`/`apply`, nada desplegado todavía. Código de la aplicación (FastAPI, Durable Function de ingesta) **todavía no escrito** - esta pasada fue solo IaC. Ver "Gaps y bugs reales encontrados" para lo que falta resolver antes de un apply real (principalmente: subnet delegada a `Microsoft.Web/serverFarms` inexistente en `azure-virtual-network`, y el body de vector search de Cosmos sin verificar contra Azure real).
- 2026-09-30: Repo creado (público, `jalcalaroot/azure-agent-platform`), CLAUDE.md inicial con las decisiones de arquitectura del documento de requisitos.
