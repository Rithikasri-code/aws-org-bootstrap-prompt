variable "root_id" {
  description = "ID of the AWS Organizations root"
  type        = string
}

variable "workloads_ou_id" {
  description = "ID of the Workloads OU for workload-specific SCPs"
  type        = string
}

variable "management_account_id" {
  description = "AWS account ID of the management account"
  type        = string
}

variable "security_account_id" {
  description = "AWS account ID of the Security account"
  type        = string
}

variable "logging_account_id" {
  description = "AWS account ID of the Logging account"
  type        = string
}

variable "approved_regions" {
  description = "List of approved AWS regions for workloads"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}
