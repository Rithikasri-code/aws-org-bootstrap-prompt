data "aws_caller_identity" "security" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────
# GuardDuty — Delegated Administrator
# ─────────────────────────────────────────────
resource "aws_guardduty_detector" "security" {
  enable = true

  datasources {
    s3_logs { enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { enable = true }
      }
    }
  }

  tags = merge(var.common_tags, { Name = "org-guardduty-delegated-admin" })
}

resource "aws_guardduty_organization_admin_account" "security" {
  admin_account_id = data.aws_caller_identity.security.account_id
  depends_on       = [aws_guardduty_detector.security]
}

resource "aws_guardduty_organization_configuration" "security" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.security.id

  datasources {
    s3_logs { auto_enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { auto_enable = true }
      }
    }
  }

  depends_on = [aws_guardduty_organization_admin_account.security]
}

# GuardDuty findings export to SNS for critical alerts
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "guardduty-high-severity"
  description = "Capture HIGH and CRITICAL GuardDuty findings"
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

resource "aws_sns_topic" "security_alerts" {
  name              = "org-security-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.common_tags
}

resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.security_alert_email
}

# ─────────────────────────────────────────────
# Security Hub — Delegated Administrator
# ─────────────────────────────────────────────
resource "aws_securityhub_account" "security" {}

resource "aws_securityhub_organization_admin_account" "security" {
  admin_account_id = data.aws_caller_identity.security.account_id
  depends_on       = [aws_securityhub_account.security]
}

resource "aws_securityhub_organization_configuration" "security" {
  auto_enable           = true
  auto_enable_standards = "DEFAULT"
  depends_on            = [aws_securityhub_organization_admin_account.security]
}

# Enable CIS AWS Foundations Benchmark v1.4.0
resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.security]
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.security]
}

# Route CRITICAL/HIGH findings to SNS
resource "aws_cloudwatch_event_rule" "securityhub_critical" {
  name        = "securityhub-critical-findings"
  description = "Route Security Hub CRITICAL and HIGH findings to SNS"
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = { Label = ["CRITICAL", "HIGH"] }
        Workflow  = { Status = ["NEW"] }
        RecordState = ["ACTIVE"]
      }
    }
  })
  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "securityhub_sns" {
  rule      = aws_cloudwatch_event_rule.securityhub_critical.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn
}

# ─────────────────────────────────────────────
# Amazon Macie — Delegated Administrator
# ─────────────────────────────────────────────
resource "aws_macie2_account" "security" {
  finding_publishing_frequency = "SIX_HOURS"
  status                       = "ENABLED"
}

resource "aws_macie2_organization_admin_account" "security" {
  admin_account_id = data.aws_caller_identity.security.account_id
  depends_on       = [aws_macie2_account.security]
}

# ─────────────────────────────────────────────
# IAM Access Analyzer — Organization Level
# ─────────────────────────────────────────────
resource "aws_accessanalyzer_analyzer" "org" {
  analyzer_name = "org-access-analyzer"
  type          = "ORGANIZATION"

  tags = merge(var.common_tags, { Name = "org-access-analyzer" })
}
