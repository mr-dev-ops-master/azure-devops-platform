resource "azurerm_log_analytics_workspace" "law" {
  name                = "log-${local.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "appi" {
  name                = "appi-${local.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.law.id
  application_type    = "web"
  tags                = local.tags
}

resource "azurerm_monitor_action_group" "ops" {
  name                = "ag-${local.name}"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = substr("ops${var.environment}", 0, 12)
  tags                = local.tags

  email_receiver {
    name                    = "platform-team"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# Send web app platform logs and metrics to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_linux_web_app.app.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log { category = "AppServiceHTTPLogs" }
  enabled_log { category = "AppServiceConsoleLogs" }
  enabled_log { category = "AppServiceAppLogs" }
  enabled_log { category = "AppServicePlatformLogs" }

  enabled_metric { category = "AllMetrics" }
}

# Alert 1: server errors
resource "azurerm_monitor_metric_alert" "http5xx" {
  name                = "alert-http5xx-${local.name}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_web_app.app.id]
  description         = "More than 5 HTTP 5xx errors in 5 minutes"
  severity            = local.is_prod ? 1 : 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 5
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}

# Alert 2: availability test on /health from two locations
resource "azurerm_application_insights_standard_web_test" "health" {
  name                    = "webtest-health-${local.name}"
  resource_group_name     = azurerm_resource_group.rg.name
  location                = azurerm_resource_group.rg.location
  application_insights_id = azurerm_application_insights.appi.id
  geo_locations           = ["emea-gb-db3-azr", "emea-nl-ams-azr"]
  frequency               = 300
  enabled                 = true
  tags                    = local.tags

  request {
    url = "https://${azurerm_linux_web_app.app.default_hostname}/health"
  }

  validation_rules {
    expected_status_code = 200
    ssl_check_enabled    = true
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  name                = "alert-availability-${local.name}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_application_insights_standard_web_test.health.id, azurerm_application_insights.appi.id]
  description         = "Health endpoint failing from a test location"
  severity            = local.is_prod ? 0 : 3
  tags                = local.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.health.id
    component_id          = azurerm_application_insights.appi.id
    failed_location_count = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.ops.id
  }
}
