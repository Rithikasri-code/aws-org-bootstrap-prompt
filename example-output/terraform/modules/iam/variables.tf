variable "security_account_id" {
  description = "AWS account ID of the Security account"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_account_id))
    error_message = "security_account_id must be a 12-digit AWS account ID."
  }
}

variable "shared_services_account_id" {
  description = "AWS account ID of the Shared Services account (CI/CD origin)"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.shared_services_account_id))
    error_message = "shared_services_account_id must be a 12-digit AWS account ID."
  }
}

variable "all_ou_ids" {
  description = "List of all OU IDs to deploy cross-account roles into"
  type        = list(string)
}

variable "approved_regions" {
  description = "Approved AWS regions — TerraformExecutionRole is denied outside these"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "cicd_external_id" {
  description = "External ID for CI/CD tool to assume TerraformExecutionRole (keep secret)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.cicd_external_id) >= 16
    error_message = "cicd_external_id must be at least 16 characters for security."
  }
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}
