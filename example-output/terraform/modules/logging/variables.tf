variable "management_account_id" {
  description = "AWS account ID of the management account (used in CloudTrail bucket policy)"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "management_account_id must be a 12-digit AWS account ID."
  }
}

variable "organization_id" {
  description = "AWS Organizations ID (used in Config bucket policy aws:SourceOrgID condition)"
  type        = string
  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must match pattern o-xxxxxxxxxx."
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
