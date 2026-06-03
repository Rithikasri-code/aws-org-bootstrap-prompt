output "management_account_id" {
  description = "AWS account ID of the management account"
  value       = data.aws_caller_identity.management.account_id
}

output "organization_id" {
  description = "ID of the AWS Organization"
  value       = module.organizations.organization_id
}

output "security_account_id" {
  description = "AWS account ID of the Security account"
  value       = module.organizations.security_account_id
}

output "logging_account_id" {
  description = "AWS account ID of the Logging account"
  value       = module.organizations.logging_account_id
}

output "shared_services_account_id" {
  description = "AWS account ID of the Shared Services account"
  value       = module.organizations.shared_services_account_id
}

output "production_account_id" {
  description = "AWS account ID of the Production account"
  value       = module.organizations.production_account_id
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail log S3 bucket in the Logging account"
  value       = module.logging.cloudtrail_bucket_arn
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of the KMS key used for CloudTrail log encryption"
  value       = module.logging.cloudtrail_kms_key_arn
}

output "config_aggregator_arn" {
  description = "ARN of the AWS Config organization aggregator"
  value       = module.logging.config_aggregator_arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID in the Security account"
  value       = module.security.guardduty_detector_id
}

output "security_hub_arn" {
  description = "Security Hub ARN in the Security account"
  value       = module.security.security_hub_arn
}

output "org_access_role_name" {
  description = "Name of the cross-account access role created in all member accounts"
  value       = "OrganizationAccountAccessRole"
}

output "security_alerts_topic_arn" {
  description = "SNS topic ARN for CRITICAL/HIGH security alerts"
  value       = module.security.alerts_topic_arn
}
