# Root independiente del resto del repo - sin ninguna dependencia de Azure
# Verified Modules, no hereda el rango acotado de azurerm que pide el root
# principal (ver versions.tf de la raiz).
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {}
}
