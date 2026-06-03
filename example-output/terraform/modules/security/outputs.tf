output "guardduty_detector_id" {
  description = "GuardDuty detector ID in the Security account (delegated admin)"
  value       = aws_guardduty_detector.security.id
}

output "guardduty_detector_arn" {
  description = "GuardDuty detector ARN in the Security account"
  value       = aws_guardduty_detector.security.arn
}

output "security_hub_arn" {
  description = "Security Hub ARN in the Security account"
  value       = aws_securityhub_account.security.id
}

output "macie_session_status" {
  description = "Status of the Macie session in the Security account"
  value       = aws_macie2_account.security.status
}

output "access_analyzer_arn" {
  description = "ARN of the organization-level IAM Access Analyzer"
  value       = aws_accessanalyzer_analyzer.org.arn
}

output "alerts_topic_arn" {
  description = "SNS topic ARN for CRITICAL/HIGH security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "alerts_topic_name" {
  description = "SNS topic name for security alerts"
  value       = aws_sns_topic.security_alerts.name
}
