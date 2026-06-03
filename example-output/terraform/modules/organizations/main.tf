# ─────────────────────────────────────────────
# Enable AWS Organizations (idempotent)
# ─────────────────────────────────────────────
resource "aws_organizations_organization" "root" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "guardduty.amazonaws.com",
    "macie.amazonaws.com",
    "securityhub.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "sso.amazonaws.com",
    "stacksets.cloudformation.amazonaws.com",
    "reporting.trustedadvisor.amazonaws.com",
  ]
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]
  feature_set = "ALL"
}

# ─────────────────────────────────────────────
# Organizational Units
# ─────────────────────────────────────────────
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.root.roots[0].id
  tags = merge(var.common_tags, { Name = "Security-OU" })
}

resource "aws_organizations_organizational_unit" "logging" {
  name      = "Logging"
  parent_id = aws_organizations_organization.root.roots[0].id
  tags = merge(var.common_tags, { Name = "Logging-OU" })
}

resource "aws_organizations_organizational_unit" "infrastructure" {
  name      = "Infrastructure"
  parent_id = aws_organizations_organization.root.roots[0].id
  tags = merge(var.common_tags, { Name = "Infrastructure-OU" })
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.root.roots[0].id
  tags = merge(var.common_tags, { Name = "Workloads-OU" })
}

# ─────────────────────────────────────────────
# Member Accounts
# ─────────────────────────────────────────────
resource "aws_organizations_account" "security" {
  name                       = "${var.org_name}-security"
  email                      = var.security_account_email
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.security.id
  role_name                  = "OrganizationAccountAccessRole"

  tags = merge(var.common_tags, {
    Name        = "${var.org_name}-security"
    Environment = "security"
    AccountType = "security"
  })

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "logging" {
  name                       = "${var.org_name}-logging"
  email                      = var.logging_account_email
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.logging.id
  role_name                  = "OrganizationAccountAccessRole"

  tags = merge(var.common_tags, {
    Name        = "${var.org_name}-logging"
    Environment = "logging"
    AccountType = "logging"
  })

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "shared_services" {
  name                       = "${var.org_name}-shared-services"
  email                      = var.shared_services_account_email
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.infrastructure.id
  role_name                  = "OrganizationAccountAccessRole"

  tags = merge(var.common_tags, {
    Name        = "${var.org_name}-shared-services"
    Environment = "shared"
    AccountType = "infrastructure"
  })

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "production" {
  name                       = "${var.org_name}-production"
  email                      = var.production_account_email
  iam_user_access_to_billing = "ALLOW"
  parent_id                  = aws_organizations_organizational_unit.workloads.id
  role_name                  = "OrganizationAccountAccessRole"

  tags = merge(var.common_tags, {
    Name        = "${var.org_name}-production"
    Environment = "production"
    AccountType = "workload"
  })

  lifecycle {
    ignore_changes = [role_name]
  }
}

# ─────────────────────────────────────────────
# Tag Policies (enforce tagging at org level)
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "tagging" {
  name        = "EnforceRequiredTags"
  description = "Requires Project, ManagedBy, and Environment tags on all resources"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      Project = {
        tag_key = {
          "@@assign" = "Project"
        }
        enforced_for = {
          "@@assign" = ["ec2:instance", "s3:bucket", "rds:db", "lambda:function"]
        }
      }
      Environment = {
        tag_key = {
          "@@assign" = "Environment"
        }
        tag_value = {
          "@@assign" = ["production", "staging", "development", "security", "logging", "shared"]
        }
        enforced_for = {
          "@@assign" = ["ec2:instance", "s3:bucket", "rds:db"]
        }
      }
    }
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "tagging_root" {
  policy_id = aws_organizations_policy.tagging.id
  target_id = aws_organizations_organization.root.roots[0].id
}
