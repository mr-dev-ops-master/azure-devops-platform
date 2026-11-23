# One registry per environment. Images are built once, pushed to dev,
# and promoted to prod with `az acr import` (same image digest).
resource "azurerm_container_registry" "acr" {
  name                = "acr${local.name_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false # no shared username/password; managed identity + RBAC only
  tags                = local.tags
}

# The pipeline identity running Terraform can push images
resource "azurerm_role_assignment" "deployer_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = data.azurerm_client_config.current.object_id
}
