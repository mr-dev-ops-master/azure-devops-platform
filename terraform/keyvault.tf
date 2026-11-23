resource "azurerm_key_vault" "kv" {
  name                       = "kv-${local.name}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = local.is_prod
  tags                       = local.tags
}

# Let the identity running Terraform (the pipeline) manage secrets in this vault
resource "azurerm_role_assignment" "deployer_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC can take a minute to apply
resource "time_sleep" "wait_for_rbac" {
  depends_on      = [azurerm_role_assignment.deployer_kv]
  create_duration = "60s"
}

resource "azurerm_key_vault_secret" "welcome" {
  name         = "welcome-message"
  value        = var.welcome_message
  key_vault_id = azurerm_key_vault.kv.id
  content_type = "text/plain"
  depends_on   = [time_sleep.wait_for_rbac]
}
