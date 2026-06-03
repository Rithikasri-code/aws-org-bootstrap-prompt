output "organization_id" {
  description = "The ID of the AWS Organization"
  value       = aws_organizations_organization.root.id
}

output "root_id" {
  description = "The ID of the organization root"
  value       = aws_organizations_organization.root.roots[0].id
}

output "security_account_id" {
  description = "Account ID of the Security account"
  value       = aws_organizations_account.security.id
}

output "logging_account_id" {
  description = "Account ID of the Logging account"
  value       = aws_organizations_account.logging.id
}

output "shared_services_account_id" {
  description = "Account ID of the Shared Services account"
  value       = aws_organizations_account.shared_services.id
}

output "production_account_id" {
  description = "Account ID of the Production account"
  value       = aws_organizations_account.production.id
}

output "security_ou_id" {
  description = "ID of the Security OU"
  value       = aws_organizations_organizational_unit.security.id
}

output "workloads_ou_id" {
  description = "ID of the Workloads OU"
  value       = aws_organizations_organizational_unit.workloads.id
}
