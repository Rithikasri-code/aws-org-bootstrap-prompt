output "stackset_id" {
  description = "CloudFormation StackSet ID for cross-account roles"
  value       = aws_cloudformation_stack_set.cross_account_roles.id
}

output "stackset_arn" {
  description = "CloudFormation StackSet ARN"
  value       = aws_cloudformation_stack_set.cross_account_roles.arn
}

output "password_policy_minimum_length" {
  description = "Minimum password length enforced in the management account"
  value       = aws_iam_account_password_policy.management.minimum_password_length
}
