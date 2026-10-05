# Rango real, verificado contra el Terraform Registry (mcp__terraform,
# 2026-09-30) para cada AVM usada en este repo - no adivinado:
#   - azurerm: documentdb-databaseaccount (0.11.0) pide ~> 4.0; apimanagement-
#     service (0.9.0) pide >= 4.0, < 5.0; insights-component y
#     authorization-roleassignment aceptan >= 3.71, < 5.0. El piso 4.81 viene
#     de la primera version de este repo (keyvault-vault 0.11.0, ya
#     removido) y se mantiene a proposito: mismo piso que azure-virtual-
#     network, sin motivo para aflojarlo.
#   - azapi: documentdb-databaseaccount y web-site piden ~> 2.12 (el mas
#     estricto); apimanagement-service ~> 2.4; insights-component/
#     authorization-roleassignment ~> 2.4. Interseccion: >= 2.12.0, < 3.0.0.
#   - azuread: solo authorization-roleassignment lo declara, >= 2.46, < 4.0.
#   - random: documentdb-databaseaccount pide ~> 3.6 (el mas estricto).
#   - time: usado transitivamente por varios modulos (documentdb-databaseaccount,
#     storage-storageaccount, web-site) con rangos que en un primer intento
#     de fijar un piso/techo explicito aca resultaron INCOMPATIBLES entre si
#     (error real de `terraform init`, 2026-09-30: "no available releases
#     match the given constraints"). Sin pin propio a proposito - se deja
#     que Terraform resuelva la interseccion real entre modulos, mismo
#     criterio que azure-virtual-network (que tampoco fija random/time/modtm
#     en su versions.tf, solo azurerm).
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.81.0, < 5.0.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.46.0, < 4.0.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.12.0, < 3.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0, < 4.0.0"
    }
  }
}
