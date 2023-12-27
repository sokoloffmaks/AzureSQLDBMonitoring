provider "azurerm" {
  features {}
}
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    azapi = {
      source = "Azure/azapi"
    }
  }
}

resource "random_password" "password" {
  length  = 16
  special = true
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "example" {
  name     = "RG-sql-monitoring-01"
  location = var.location
}


resource "azurerm_key_vault" "example" {
  name                     = "kv-sql-monitoring-01"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.example.name
  tenant_id                = data.azurerm_client_config.current.tenant_id
  purge_protection_enabled = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
      "Delete",
      "Update",
      "Purge",
      "List"
    ]

    secret_permissions = [
      "Get",
      "Delete",
      "Purge",
      "List",
      "Set"
    ]
  }
}

resource "azurerm_key_vault_secret" "example" {
  name         = "sql-monitoring-db-password"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.example.id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "azurerm_log_analytics_workspace" "example" {
  name                = "my-log-analytics-workspace"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  sku                 = "PerGB2018"
}

resource "azurerm_mssql_server" "example" {
  name                         = "sql-myazuresqlserver-01"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.example.name
  version                      = "12.0"
  administrator_login          = "adminuser"
  administrator_login_password = azurerm_key_vault_secret.example.value
}

resource "azurerm_mssql_database" "example" {
  for_each = toset(var.databases)

  name      = each.value
  server_id = azurerm_mssql_server.example.id
  sku_name  = "S0"                           //Optional
  collation = "SQL_Latin1_General_CP1_CI_AS" //Optional
}

resource "azurerm_monitor_diagnostic_setting" "example" {
  for_each                   = toset(var.databases)
  name                       = "diagnostic-setting-${each.value}"
  target_resource_id         = azurerm_mssql_database.example[each.value].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id

  dynamic "log" {
    for_each = var.log_categories
    content {
      category = log.value

      retention_policy {
        days    = 0
        enabled = false
      }
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      days    = 0
      enabled = false
    }
  }
}
resource "azurerm_monitor_action_group" "alert_action_group" {
  name                = "database-alert-action-group"
  resource_group_name = azurerm_resource_group.example.name
  short_name          = "dbalerts"
  #location            = "global" # optional

  dynamic "email_receiver" {
    for_each = var.alert_emails
    content {
      name          = "email_${email_receiver.key}"
      email_address = email_receiver.value
    }
  }
}

locals {
  combined_list = flatten([for db in var.databases : [for metric in var.alert_metrics : { db = db, metric = metric }]])
  combined_map  = { for item in local.combined_list : "${item.db}-${item.metric.metric_type}" => item }

}


resource "azurerm_monitor_metric_alert" "db_metrics_alert" {
  for_each = local.combined_map

  name                = "${each.value.metric.metric_type} - ${each.value.db}"
  resource_group_name = azurerm_resource_group.example.name
  scopes              = [azurerm_mssql_database.example[each.value.db].id]
  description         = each.value.metric.alert_description

  severity    = each.value.metric.severity
  window_size = each.value.metric.window_size
  frequency   = each.value.metric.frequency

  criteria {
    metric_namespace = "Microsoft.Sql/servers/databases"
    metric_name      = each.value.metric.metric_name
    aggregation      = each.value.metric.aggregation
    operator         = each.value.metric.operator
    threshold        = each.value.metric.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.alert_action_group.id
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert" "long_running_queries" {
  name                = "long-running-queries"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  trigger {
    operator  = "GreaterThan"
    threshold = 0

  }

  action {
    action_group           = [azurerm_monitor_action_group.alert_action_group.id]
    email_subject          = "Long Running Query Detected"
    custom_webhook_payload = "{}"
  }

  data_source_id = azurerm_log_analytics_workspace.example.id
  description    = "This alert rule checks for long-running queries."
  enabled        = true

  query       = <<-QUERY
    let LongRunningQueries = 10m; // Define long-running query threshold
    AzureDiagnostics
    | where Category == "SQLSecurityAuditEvents" and statement_succeeded_succeeded == "True"
    | where toint(query_duration_s) > LongRunningQueries
    | summarize Count = count() by bin(timestamp, 5m), serverName_s, databaseName_s, client_IP_s, statement_s
    | where Count > 0
  QUERY
  severity    = 3
  frequency   = 5
  time_window = 5
}

resource "azurerm_monitor_scheduled_query_rules_alert" "deadlocks" {
  name                = "deadlocks"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  trigger {
    operator  = "GreaterThan"
    threshold = 0

  }

  action {
    action_group           = [azurerm_monitor_action_group.alert_action_group.id]
    email_subject          = "Deadlock Detected"
    custom_webhook_payload = "{}"
  }

  data_source_id = azurerm_log_analytics_workspace.example.id
  description    = "This alert rule checks for deadlocks."
  enabled        = true

  query       = <<-QUERY
    let LongRunningQueries = 10m; // Define long-running query threshold
AzureDiagnostics
| where Category == "SQLSecurityAuditEvents" and OperationName == "StatementCompleted"
| where toint(duration_s) > 120000 // Change threshold as needed (e.g., 2 minutes)
| summarize Count = count() by bin(TimeGenerated, 5m), serverName_s, databaseName_s, client_IP_s, statement_s
| where Count > 0
  QUERY
  severity    = 3
  frequency   = 5
  time_window = 5
}

resource "azapi_update_resource" "mssql_database_autotuning_create_index" {
  for_each    = { for db in var.databases : db => db }
  type        = "Microsoft.Sql/servers/databases/advisors@2014-04-01"
  resource_id = "${azurerm_mssql_database.example[each.key].id}/advisors/CreateIndex"

  body = jsonencode({
    properties : {
      autoExecuteValue : var.create_index_auto_execute_value
    }
  })
}

resource "azapi_update_resource" "mssql_database_autotuning_force_last_good_plan" {
  for_each    = { for db in var.databases : db => db }
  type        = "Microsoft.Sql/servers/databases/advisors@2014-04-01"
  resource_id = "${azurerm_mssql_database.example[each.key].id}/advisors/ForceLastGoodPlan"

  body = jsonencode({
    properties : {
      autoExecuteValue : var.force_last_good_plan_auto_execute_value
    }
  })
}

resource "azapi_update_resource" "mssql_database_autotuning_drop_index" {
  for_each    = { for db in var.databases : db => db }
  type        = "Microsoft.Sql/servers/databases/advisors@2014-04-01"
  resource_id = "${azurerm_mssql_database.example[each.key].id}/advisors/DropIndex"

  body = jsonencode({
    properties : {
      autoExecuteValue : var.drop_index_auto_execute_value
    }
  })
}
