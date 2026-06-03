variable "org_name" {
  description = "Short name prefix for your organization (e.g. 'acme')"
  type        = string
}

variable "security_account_email" {
  description = "Unique email for the Security account (must not be in use)"
  type        = string
}

variable "logging_account_email" {
  description = "Unique email for the Logging account (must not be in use)"
  type        = string
}

variable "shared_services_account_email" {
  description = "Unique email for the Shared Services account (must not be in use)"
  type        = string
}

variable "production_account_email" {
  description = "Unique email for the Production account (must not be in use)"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}
