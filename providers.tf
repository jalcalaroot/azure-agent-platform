provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
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
