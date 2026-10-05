provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    # Un APIM destruido queda en soft-delete 48h y bloquea recrear el mismo
    # nombre: se purga al destruir y no se intenta recuperar uno borrado.
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = false
    }
  }
}

provider "azuread" {
  tenant_id = var.tenant_id
}

# Sin subscription_id explicito no detecta el contexto en corridas locales
# (a diferencia de azurerm, que lo toma de var.subscription_id) - en CI lo
# toma solo de ARM_SUBSCRIPTION_ID (ya seteado por los workflows), pero en
# local no hay ninguna var de entorno equivalente salvo que se exporte a
# mano, asi que se fija explicito aca para los dos casos.
provider "azapi" {
  subscription_id = var.subscription_id
}
