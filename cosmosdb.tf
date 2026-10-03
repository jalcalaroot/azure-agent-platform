# Componente 2 - Cosmos DB.
#
# Zona DNS privada del endpoint SQL (NoSQL) de Cosmos DB. Sin ella el
# Private Endpoint existe pero <cuenta>.documents.azure.com sigue
# resolviendo a la IP publica, y el Function App (sin acceso publico a
# Cosmos) no podria conectarse. Faltaba en la primera version de este
# archivo - las de AI Foundry, Content Safety, storage y Function App ya
# estaban.
resource "azurerm_private_dns_zone" "cosmos_sql" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos_sql" {
  name                  = "link-cosmos-sql-agent-platform"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos_sql.name
  virtual_network_id    = var.network_vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

# GAP REAL, confirmado contra la doc del modulo (mcp__terraform,
# 2026-09-30) Y contra la doc del recurso nativo azurerm_cosmosdb_sql_container
# (provider azurerm 5.7.0): NINGUNO de los dos expone un campo de
# vectorEmbeddingPolicy/vector index en el schema de containers - el modulo
# solo permite prender el capability de cuenta EnableNoSQLVectorSearch, sin
# forma de declarar el indice vectorial en si via azurerm ni via esta AVM.
# Los 2 containers que necesitan busqueda vectorial (knowledge_base,
# semantic_cache) se declaran mas abajo como azapi_resource (ARM PUT crudo)
# en su lugar - los otros 2 (requests, orchestrations, solo logs/estado, sin
# busqueda vectorial) sí entran en el sql_databases del modulo.
module "cosmos" {
  #checkov:skip=CKV_TF_1:pinned por version semver del Terraform Registry, no un git tag - mismo criterio que azure-virtual-network.
  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "0.11.0"

  name                = var.cosmos_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = local.tags

  enable_telemetry = false

  capabilities = [
    { name = "EnableServerless" },
    { name = "EnableNoSQLVectorSearch" },
  ]

  local_authentication_disabled = true # sin access keys - solo RBAC de datos (ver azurerm_cosmosdb_sql_role_assignment abajo)
  public_network_access_enabled = false

  private_endpoints = {
    sql = {
      subnet_resource_id            = var.network_privatelink_subnet_id
      subresource_name              = "SQL"
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.cosmos_sql.id]
    }
  }

  sql_databases = {
    policyhub = {
      name = "policyhub"

      containers = {
        requests = {
          name                = "requests"
          partition_key_paths = ["/id"]
        }
        orchestrations = {
          name                = "orchestrations"
          partition_key_paths = ["/id"]
        }
      }
    }
  }
}

# ID determinístico de la base de datos creada arriba (patron "resolver el
# ID antes de que exista", mismo usado en los ejemplos oficiales de la AVM
# de Application Gateway) - evita depender de la forma exacta del output
# sql_databases del modulo, no verificada contra un apply real todavia.
locals {
  cosmos_database_id = "${module.cosmos.resource_id}/sqlDatabases/policyhub"
}

# Containers con busqueda vectorial - ARM crudo via azapi, ver nota arriba.
# Body basado en el schema documentado por Microsoft para Vector Search en
# Cosmos DB NoSQL.
#
# schema_validation_enabled = false, real error encontrado en
# `terraform validate` (2026-09-30): el schema embebido de azapi para la
# API version estable 2024-08-15 no reconoce
# `properties.resource.vectorEmbeddingPolicy` ni
# `properties.resource.indexingPolicy.vectorIndexes` - vector search en
# Cosmos DB NoSQL todavia vive en una superficie de API preview que el
# azapi provider no tiene embebida para esta version. Confirmar contra un
# `terraform plan`/apply real (o contra una API version preview mas nueva)
# antes de dar este container por funcional.
resource "azapi_resource" "knowledge_base_container" {
  type                      = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-08-15"
  name                      = "knowledge_base"
  parent_id                 = local.cosmos_database_id
  schema_validation_enabled = false

  body = {
    properties = {
      resource = {
        id = "knowledge_base"
        partitionKey = {
          paths = ["/id"]
          kind  = "Hash"
        }
        indexingPolicy = {
          indexingMode = "consistent"
          automatic    = true
          includedPaths = [
            { path = "/*" },
          ]
          excludedPaths = [
            { path = "/embedding/*" },
            { path = "/\"_etag\"/?" },
          ]
          vectorIndexes = [
            { path = "/embedding", type = "quantizedFlat" },
          ]
        }
        vectorEmbeddingPolicy = {
          vectorEmbeddings = [
            {
              path             = "/embedding"
              dataType         = "float32"
              dimensions       = 1536 # text-embedding-3-small, dimension default
              distanceFunction = "cosine"
            },
          ]
        }
      }
    }
  }

  depends_on = [module.cosmos]
}

resource "azapi_resource" "semantic_cache_container" {
  type                      = "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-08-15"
  name                      = "semantic_cache"
  parent_id                 = local.cosmos_database_id
  schema_validation_enabled = false

  body = {
    properties = {
      resource = {
        id = "semantic_cache"
        partitionKey = {
          paths = ["/id"]
          kind  = "Hash"
        }
        indexingPolicy = {
          indexingMode = "consistent"
          automatic    = true
          includedPaths = [
            { path = "/*" },
          ]
          excludedPaths = [
            { path = "/embedding/*" },
            { path = "/\"_etag\"/?" },
          ]
          vectorIndexes = [
            { path = "/embedding", type = "quantizedFlat" },
          ]
        }
        vectorEmbeddingPolicy = {
          vectorEmbeddings = [
            {
              path             = "/embedding"
              dataType         = "float32"
              dimensions       = 1536
              distanceFunction = "cosine"
            },
          ]
        }
      }
    }
  }

  depends_on = [module.cosmos]
}

# RBAC de datos (data-plane) - NI el modulo AVM de Cosmos DB ni la AVM
# Azure/avm-res-authorization-roleassignment soportan esto (confirmado
# contra ambas doc, 2026-09-30): ambas solo cubren RBAC de control-plane
# (Microsoft.Authorization/roleAssignments). El rol "Cosmos DB Built-in Data
# Contributor" es un rol built-in con GUID fijo y bien documentado por
# Microsoft (00000000-0000-0000-0000-000000000002) - no hace falta crear un
# sql_role_definition custom, solo referenciar el built-in por su ID
# completo.
resource "azurerm_cosmosdb_sql_role_assignment" "function_app_data_contributor" {
  resource_group_name = var.resource_group_name
  account_name        = var.cosmos_account_name
  role_definition_id  = "${module.cosmos.resource_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_user_assigned_identity.function_app.principal_id
  scope               = module.cosmos.resource_id

  depends_on = [module.cosmos]
}
