output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket storing CloudTrail organization trail logs"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail log S3 bucket"
  value       = aws_s3_bucket.cloudtrail.arn
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudTrail logs"
  value       = aws_kms_key.cloudtrail.arn
}

output "cloudtrail_kms_key_id" {
  description = "ID of the KMS key used to encrypt CloudTrail logs"
  value       = aws_kms_key.cloudtrail.key_id
}

output "cloudtrail_trail_arn" {
  description = "ARN of the organization CloudTrail trail"
  value       = aws_cloudtrail.org_trail.arn
}

output "cloudtrail_log_group_arn" {
  description = "ARN of the CloudWatch Log Group receiving CloudTrail events"
  value       = aws_cloudwatch_log_group.cloudtrail.arn
}

output "config_aggregator_arn" {
  description = "ARN of the AWS Config organization aggregator"
  value       = aws_config_configuration_aggregator.org.arn
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket storing Config snapshots"
  value       = aws_s3_bucket.config.arn
}

output "flowlogs_bucket_arn" {
  description = "ARN of the S3 bucket for cross-account VPC Flow Logs"
  value       = aws_s3_bucket.flowlogs.arn
}

output "flowlogs_bucket_name" {
  description = "Name of the S3 bucket for cross-account VPC Flow Logs"
  value       = aws_s3_bucket.flowlogs.bucket
}
