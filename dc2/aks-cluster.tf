terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.66.0"
    }
  }

  required_version = ">= 0.14"
}

resource "random_pet" "prefix" {}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "${random_pet.prefix.id}-rg"
  location = var.network_region
}

# Create a user assigned identity (required for UserAssigned identity in combination with brining our own subnet/nsg/etc)
resource "azurerm_user_assigned_identity" "identity" {
  name                = "aks-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create the AKS cluster.
resource "azurerm_kubernetes_cluster" "default" {
  name                = "${random_pet.prefix.id}-hashidays-consul-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${random_pet.prefix.id}-k8s"

  default_node_pool {
    name            = "default"
    node_count      = 2
    vm_size         = "Standard_B2s"
    os_disk_size_gb = 30
  }

  identity {
    type                      = "UserAssigned"
    user_assigned_identity_id = azurerm_user_assigned_identity.identity.id
  }
}