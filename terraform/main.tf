data "azurerm_client_config" "current" {}

locals {
  name       = "${var.prefix}-${var.environment}"
  name_short = "${var.prefix}${var.environment}" # for names that allow no dashes
  is_prod    = var.environment == "prod"
  tags = {
    project     = "azure-devops-platform"
    environment = var.environment
    managed_by  = "terraform"
    owner       = "platform-team"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}
