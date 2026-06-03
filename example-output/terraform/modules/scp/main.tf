# ─────────────────────────────────────────────
# SCP-01: Region Lockout (attach: Root)
# Prevents data residency violations and limits
# blast radius of compromised credentials
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_01_region_lockout" {
  name        = "SCP-01-RegionLockout"
  description = "Deny all actions outside approved regions. Global services exempted."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyNonApprovedRegions"
      Effect = "Deny"
      NotAction = [
        "iam:*", "sts:*", "cloudfront:*", "route53:*",
        "support:*", "budgets:*", "ce:*", "globalaccelerator:*",
        "organizations:*", "account:*", "health:*"
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:RequestedRegion" = var.approved_regions
        }
        ArnNotLike = {
          "aws:PrincipalArn" = [
            "arn:aws:iam::${var.management_account_id}:root"
          ]
        }
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_01" {
  policy_id = aws_organizations_policy.scp_01_region_lockout.id
  target_id = var.root_id
}

# ─────────────────────────────────────────────
# SCP-02: Deny CloudTrail Disable (attach: Root)
# Protects audit trail integrity across all accounts
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_02_protect_cloudtrail" {
  name        = "SCP-02-ProtectCloudTrail"
  description = "Deny CloudTrail modification by any principal except the logging account role"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyCloudTrailModification"
      Effect = "Deny"
      Action = [
        "cloudtrail:DeleteTrail",
        "cloudtrail:StopLogging",
        "cloudtrail:UpdateTrail",
        "cloudtrail:PutEventSelectors",
        "cloudtrail:PutInsightSelectors",
        "cloudtrail:RemoveTags",
        "cloudtrail:DeleteEventDataStore"
      ]
      Resource = "*"
      Condition = {
        ArnNotLike = {
          "aws:PrincipalArn" = [
            "arn:aws:iam::${var.logging_account_id}:role/CloudTrailAdminRole",
            "arn:aws:iam::${var.management_account_id}:root"
          ]
        }
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_02" {
  policy_id = aws_organizations_policy.scp_02_protect_cloudtrail.id
  target_id = var.root_id
}

# ─────────────────────────────────────────────
# SCP-03: Deny GuardDuty Disable (attach: Root)
# Protects threat detection across all accounts
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_03_protect_guardduty" {
  name        = "SCP-03-ProtectGuardDuty"
  description = "Deny GuardDuty disable/disassociation except from Security account delegated admin"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyGuardDutyDisable"
      Effect = "Deny"
      Action = [
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromAdministratorAccount",
        "guardduty:DisassociateMembers",
        "guardduty:StopMonitoringMembers",
        "guardduty:DeleteMembers",
        "guardduty:DeclineInvitations"
      ]
      Resource = "*"
      Condition = {
        ArnNotLike = {
          "aws:PrincipalArn" = [
            "arn:aws:iam::${var.security_account_id}:role/GuardDutyAdminRole",
            "arn:aws:iam::${var.management_account_id}:root"
          ]
        }
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_03" {
  policy_id = aws_organizations_policy.scp_03_protect_guardduty.id
  target_id = var.root_id
}

# ─────────────────────────────────────────────
# SCP-04: Deny S3 Public Access (attach: Root)
# Prevents accidental data exposure via S3
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_04_deny_s3_public" {
  name        = "SCP-04-DenyS3PublicAccess"
  description = "Deny re-enabling S3 public access or setting public ACLs"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicAccessBlockDisable"
        Effect = "Deny"
        Action = ["s3:PutBucketPublicAccessBlock"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:PublicAccessBlockConfiguration/BlockPublicAcls"       = "false"
            "s3:PublicAccessBlockConfiguration/BlockPublicPolicy"     = "false"
            "s3:PublicAccessBlockConfiguration/IgnorePublicAcls"      = "false"
            "s3:PublicAccessBlockConfiguration/RestrictPublicBuckets" = "false"
          }
        }
      },
      {
        Sid    = "DenyPublicACLs"
        Effect = "Deny"
        Action = ["s3:PutBucketAcl", "s3:PutObjectAcl"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = ["public-read", "public-read-write", "authenticated-read"]
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_04" {
  policy_id = aws_organizations_policy.scp_04_deny_s3_public.id
  target_id = var.root_id
}

# ─────────────────────────────────────────────
# SCP-05: Deny Root IAM Usage (attach: Root)
# Root user API calls blocked in workload accounts
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_05_deny_root" {
  name        = "SCP-05-DenyRootUsage"
  description = "Deny all API actions performed as the root user in member accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyRootAPIAccess"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        StringLike = {
          "aws:PrincipalArn" = ["arn:aws:iam::*:root"]
        }
        StringNotEquals = {
          "aws:PrincipalAccount" = var.management_account_id
        }
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_05" {
  policy_id = aws_organizations_policy.scp_05_deny_root.id
  target_id = var.root_id
}

# ─────────────────────────────────────────────
# SCP-06: Deny Leaving Organization (attach: Root)
# Prevents accounts from detaching from guardrails
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_06_deny_leave_org" {
  name        = "SCP-06-DenyLeaveOrganization"
  description = "Prevent any account from leaving the organization and bypassing guardrails"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyLeaveOrganization"
      Effect   = "Deny"
      Action   = ["organizations:LeaveOrganization"]
      Resource = "*"
    }]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_06" {
  policy_id = aws_organizations_policy.scp_06_deny_leave_org.id
  target_id = var.root_id
}

# ─────────────────────────────────────────────
# SCP-07: Require IMDSv2 (attach: Workloads OU)
# Prevents SSRF-based credential theft
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_07_require_imdsv2" {
  name        = "SCP-07-RequireIMDSv2"
  description = "Deny EC2 launches without IMDSv2 required. Prevents SSRF metadata theft."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIMDSv1Launch"
        Effect = "Deny"
        Action = ["ec2:RunInstances"]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          StringNotEquals = {
            "ec2:MetadataHttpTokens" = "required"
          }
        }
      },
      {
        Sid    = "DenyIMDSv1Revert"
        Effect = "Deny"
        Action = ["ec2:ModifyInstanceMetadataOptions"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Attribute/HttpTokens" = "optional"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_07" {
  policy_id = aws_organizations_policy.scp_07_require_imdsv2.id
  target_id = var.workloads_ou_id
}

# ─────────────────────────────────────────────
# SCP-08: Deny Unencrypted S3 Uploads (Workloads OU)
# All objects in workload accounts must be encrypted
# ─────────────────────────────────────────────
resource "aws_organizations_policy" "scp_08_deny_unencrypted_s3" {
  name        = "SCP-08-DenyUnencryptedS3Uploads"
  description = "Deny S3 PutObject without server-side encryption header in workload accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyUnencryptedObjectUploads"
      Effect = "Deny"
      Action = ["s3:PutObject"]
      Resource = "*"
      Condition = {
        "Null" = {
          "s3:x-amz-server-side-encryption" = "true"
        }
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_organizations_policy_attachment" "scp_08" {
  policy_id = aws_organizations_policy.scp_08_deny_unencrypted_s3.id
  target_id = var.workloads_ou_id
}
