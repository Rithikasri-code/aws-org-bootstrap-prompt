variable "organization_id" {
  description = "AWS Organizations ID — used for GuardDuty and Security Hub org configuration"
  type        = string
  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must match pattern o-xxxxxxxxxx."
  }
}

variable "logging_account_id" {
  description = "AWS account ID of the Logging account — GuardDuty exports findings here"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.logging_account_id))
    error_message = "logging_account_id must be a 12-digit AWS account ID."
  }
}

variable "security_alert_email" {
  description = "Email address to receive CRITICAL and HIGH severity security finding alerts"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}$", var.security_alert_email))
    error_message = "security_alert_email must be a valid email address."
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources in this module"
  type        = map(string)
  default = {
    Project   = "OrgBootstrap"
    ManagedBy = "Terraform"
  }
}
