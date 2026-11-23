variable "environment" {
  description = "dev or prod"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "prefix" {
  description = "Short unique prefix, lowercase letters and numbers only (used in global names)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.prefix))
    error_message = "prefix must be 3-10 lowercase letters or numbers."
  }
}

variable "location" {
  type    = string
  default = "uksouth"
}

variable "address_space" {
  description = "VNet range for this environment"
  type        = string
}

variable "app_service_sku" {
  description = "B1 for dev; P0v3 (supports deployment slots) for prod"
  type        = string
}

variable "enable_staging_slot" {
  description = "Create a staging slot for zero-downtime swap deployments"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "alert_email" {
  description = "Email address for monitoring alerts (set via TF_VAR_alert_email)"
  type        = string
}

variable "welcome_message" {
  description = "Demo secret stored in Key Vault and read by the app"
  type        = string
  default     = "Hello from Azure Key Vault"
  sensitive   = true
}
