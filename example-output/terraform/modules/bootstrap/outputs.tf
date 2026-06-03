output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state"
  value       = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform remote state"
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for state bucket encryption"
  value       = aws_kms_key.tfstate.arn
}
