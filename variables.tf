
variable "databases" {
  default = ["db1"]
}

# Azure General
variable "resource_group_name" {
  description = "Name of the Azure Resource Group to deploy resources into."
  type        = string
  default     = "RG-sql-monitoring-01"
}

variable "location" {
  description = "Azure region for deployment."
  default     = "australiaeast"
  type        = string
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}

variable "administrator_login" {
  description = "Administrator login name for Azure SQL Server."
  default     = "adminuser"
  type        = string
}

# Alerting & Monitoring
variable "alert_emails" {
  description = "List of email addresses to notify for alerts."
  type        = list(string)
  default     = ["sokoloffmaks@gmail.com", "maxim2000_2000@mail.ru"]
}

variable "alert_metrics" {
  description = "List of metrics and their associated configurations for alerting."
  type = list(object({
    metric_type       = string
    metric_name       = string
    aggregation       = string
    operator          = string
    threshold         = number
    severity          = number
    window_size       = string
    frequency         = string
    alert_description = string
  }))
  default = [
    {
      metric_type       = "SQL DB Instance Memory Usage"
      metric_name       = "sql_instance_memory_percent"
      aggregation       = "Average"
      operator          = "GreaterThan"
      threshold         = 90
      severity          = 4
      window_size       = "PT15M"
      frequency         = "PT15M"
      alert_description = "Action will be triggered when memory usage is greater than 90%."
    },
    {
      metric_type       = "SQL DB Instance CPU Percentage"
      metric_name       = "sql_instance_cpu_percent"
      aggregation       = "Average"
      operator          = "GreaterThan"
      threshold         = 80
      severity          = 4
      window_size       = "PT15M"
      frequency         = "PT15M"
      alert_description = "Action will be triggered when CPU percent is greater than 80%."
    },
    {
      metric_type       = "SQL DB Instance Session Percentage"
      metric_name       = "sessions_percent"
      aggregation       = "Average"
      operator          = "GreaterThan"
      threshold         = 80
      severity          = 4
      window_size       = "PT15M"
      frequency         = "PT15M"
      alert_description = "Action will be triggered when session percentage exceeds 80%."
    },
    {
      metric_type       = "SQL DB Instance Workers Percentage"
      metric_name       = "workers_percent"
      aggregation       = "Average"
      operator          = "GreaterThan"
      threshold         = 80
      severity          = 4
      window_size       = "PT15M"
      frequency         = "PT15M"
      alert_description = "Action will be triggered when workers percentage exceeds 80%."
    },
    {
      metric_type       = "SQL DB Instance In-Memory Storage Percentage"
      metric_name       = "xtp_storage_percent"
      aggregation       = "Average"
      operator          = "GreaterThan"
      threshold         = 80
      severity          = 4
      window_size       = "PT15M"
      frequency         = "PT15M"
      alert_description = "Action will be triggered when in-memory storage usage exceeds 80%."
    }
  ]
  validation {
    condition     = alltrue([for metric in var.alert_metrics : metric.severity >= 0 && metric.severity <= 4])
    error_message = "Each metric's severity must be between 0 and 4."
  }

  validation {
    condition     = alltrue([for metric in var.alert_metrics : metric.threshold > 0])
    error_message = "Each metric's threshold must be greater than 0."
  }
}

# Random Password
variable "password_length" {
  description = "Length of the randomly generated password."
  default     = 16
  type        = number
}

variable "password_special" {
  description = "Whether to include special characters in the password."
  default     = true
  type        = bool
}

variable "log_categories" {
  type = list(string)
  default = [
    "SQLSecurityAuditEvents",
    "DatabaseWaitStatistics",
    "Deadlocks",
    "Blocks",
    "Timeouts"
    // Add all other categories you are interested in
  ]
}
