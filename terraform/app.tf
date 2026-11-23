resource "azurerm_service_plan" "plan" {
  name                = "asp-${local.name}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.tags
}

locals {
  app_settings = {
    APP_ENV                               = var.environment
    WEBSITES_PORT                         = "8000"
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.appi.connection_string
    # Key Vault reference: the value never appears in app config or the pipeline
    WELCOME_MESSAGE = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.welcome.versionless_id})"
  }
}

resource "azurerm_linux_web_app" "app" {
  name                      = "app-${local.name}"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  service_plan_id           = azurerm_service_plan.plan.id
  https_only                = true
  virtual_network_subnet_id = azurerm_subnet.app.id
  app_settings              = local.app_settings
  tags                      = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = local.is_prod
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    http2_enabled                           = true
    health_check_path                       = "/health"
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = true

    # Placeholder image for the first deploy; the app pipeline sets the real image
    application_stack {
      docker_image_name   = "appsvc/staticsite:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
      site_config[0].application_stack[0].docker_registry_url,
    ]
  }
}

# Staging slot (prod only): deploy here, test, then swap into production
resource "azurerm_linux_web_app_slot" "staging" {
  count                     = var.enable_staging_slot ? 1 : 0
  name                      = "staging"
  app_service_id            = azurerm_linux_web_app.app.id
  https_only                = true
  virtual_network_subnet_id = azurerm_subnet.app.id
  app_settings              = local.app_settings
  tags                      = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    minimum_tls_version                     = "1.2"
    ftps_state                              = "Disabled"
    health_check_path                       = "/health"
    health_check_eviction_time_in_min       = 5
    container_registry_use_managed_identity = true

    application_stack {
      docker_image_name   = "appsvc/staticsite:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
  }

  lifecycle {
    ignore_changes = [
      site_config[0].application_stack[0].docker_image_name,
      site_config[0].application_stack[0].docker_registry_url,
    ]
  }
}

# Least privilege: the app may only PULL images and READ secrets
locals {
  app_principals = merge(
    { app = azurerm_linux_web_app.app.identity[0].principal_id },
    { for s in azurerm_linux_web_app_slot.staging : "slot" => s.identity[0].principal_id }
  )
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each             = local.app_principals
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "kv_read" {
  for_each             = local.app_principals
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}
