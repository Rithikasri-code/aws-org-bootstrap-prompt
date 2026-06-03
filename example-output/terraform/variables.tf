variable "org_name" {
  description = "Short lowercase name for your org, used as resource prefix (e.g. 'acme')"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.org_name))
    error_message = "org_name must be 2-20 lowercase alphanumeric characters or hyphens"
  }
}

variable "primary_region" {
  description = "Primary AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "approved_regions" {
  description = "AWS regions where workloads are allowed (SCP-01 blocks all others)"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "security_account_email" {
  description = "Unique email address for the Security account"
  type        = string
}

variable "logging_account_email" {
  description = "Unique email address for the Logging account"
  type        = string
}

variable "shared_services_account_email" {
  description = "Unique email address for the Shared Services account"
  type        = string
}

variable "production_account_email" {
  description = "Unique email address for the Production account"
  type        = string
}

variable "security_alert_email" {
  description = "Email address to receive CRITICAL/HIGH security finding alerts"
  type        = string
}
