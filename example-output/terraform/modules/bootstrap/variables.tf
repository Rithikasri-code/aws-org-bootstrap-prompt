variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "org-bootstrap"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state"
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "terraform-state-lock"
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "OrgBootstrap"
    ManagedBy   = "Terraform"
  }
}
