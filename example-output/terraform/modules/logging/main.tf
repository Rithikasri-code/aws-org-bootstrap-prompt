data "aws_caller_identity" "logging" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.logging.account_id
  region     = data.aws_region.current.name
}

# ─────────────────────────────────────────────
# KMS key for CloudTrail logs
# ─────────────────────────────────────────────
resource "aws_kms_key" "cloudtrail" {
  description             = "KMS key for organization CloudTrail logs"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable root account key management"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${var.management_account_id}:trail/*"
          }
        }
      },
      {
        Sid    = "Allow CloudWatch Logs to use key"
        Effect = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, { Name = "org-cloudtrail-kms" })
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/org-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

# ─────────────────────────────────────────────
# S3 bucket for CloudTrail logs (7-year retention)
# ─────────────────────────────────────────────
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "org-cloudtrail-logs-${local.account_id}-${local.region}"
  force_destroy = false

  tags = merge(var.common_tags, {
    Name        = "org-cloudtrail-logs"
    Retention   = "7-years"
    DataClass   = "AuditLogs"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "cloudtrail-retention"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
    expiration {
      days = 2555 # 7 years — SOC 2 requirement
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = { "aws:SourceArn" = "arn:aws:cloudtrail:${local.region}:${var.management_account_id}:trail/org-trail" }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"   = "bucket-owner-full-control"
            "aws:SourceArn"  = "arn:aws:cloudtrail:${local.region}:${var.management_account_id}:trail/org-trail"
          }
        }
      },
      {
        Sid    = "DenyNonTLS"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [aws_s3_bucket.cloudtrail.arn, "${aws_s3_bucket.cloudtrail.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid    = "DenyDeleteObject"
        Effect = "Deny"
        Principal = "*"
        Action   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
      }
    ]
  })
}

# ─────────────────────────────────────────────
# CloudWatch Log Group for real-time alerting
# ─────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/org-trail"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.cloudtrail.arn
  tags              = var.common_tags
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "CloudTrailCloudWatchRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "CloudTrailCloudWatchPolicy"
  role = aws_iam_role.cloudtrail_cloudwatch.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# ─────────────────────────────────────────────
# Organization CloudTrail Trail
# ─────────────────────────────────────────────
resource "aws_cloudtrail" "org_trail" {
  name                          = "org-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_cloudwatch.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"]
    }
  }

  insight_selector {
    insight_type = "ApiCallRateInsight"
  }

  tags = merge(var.common_tags, { Name = "org-trail" })

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_cloudwatch
  ]
}

# ─────────────────────────────────────────────
# AWS Config — Organization Aggregator
# ─────────────────────────────────────────────
resource "aws_s3_bucket" "config" {
  bucket        = "org-config-snapshots-${local.account_id}-${local.region}"
  force_destroy = false
  tags = merge(var.common_tags, { Name = "org-config-snapshots", DataClass = "ComplianceLogs" })
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config.arn
        Condition = { StringEquals = { "aws:SourceOrgID" = var.organization_id } }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config.arn}/AWSLogs/*/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "aws:SourceOrgID" = var.organization_id
          }
        }
      },
      {
        Sid    = "DenyNonTLS"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_config_configuration_aggregator" "org" {
  name = "org-aggregator"
  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator.arn
  }
  tags = var.common_tags
  depends_on = [aws_iam_role_policy_attachment.config_aggregator]
}

resource "aws_iam_role" "config_aggregator" {
  name = "ConfigAggregatorRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

# ─────────────────────────────────────────────
# Config Organization Managed Rules (9 rules)
# ─────────────────────────────────────────────
locals {
  org_config_rules = {
    "CLOUD_TRAIL_ENABLED"                  = {}
    "GUARDDUTY_ENABLED_CENTRALIZED"        = {}
    "S3_BUCKET_PUBLIC_READ_PROHIBITED"     = {}
    "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"    = {}
    "IAM_ROOT_ACCESS_KEY_CHECK"            = {}
    "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"   = {}
    "EC2_IMDSV2_CHECK"                     = {}
    "ENCRYPTED_VOLUMES"                    = {}
    "RDS_STORAGE_ENCRYPTED"                = {}
  }
}

resource "aws_config_organization_managed_rule" "rules" {
  for_each                = local.org_config_rules
  name                    = each.key
  rule_identifier         = each.key
  excluded_accounts       = [var.management_account_id]

  depends_on = [aws_config_configuration_aggregator.org]
}

# ─────────────────────────────────────────────
# VPC Flow Logs Aggregation Bucket
# ─────────────────────────────────────────────
resource "aws_s3_bucket" "flowlogs" {
  bucket        = "org-flowlogs-${local.account_id}-${local.region}"
  force_destroy = false
  tags = merge(var.common_tags, { Name = "org-flowlogs", DataClass = "NetworkLogs" })
}

resource "aws_s3_bucket_public_access_block" "flowlogs" {
  bucket                  = aws_s3_bucket.flowlogs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowOrgFlowLogs"
      Effect = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.flowlogs.arn}/*"
      Condition = {
        StringEquals = {
          "aws:SourceOrgID"    = var.organization_id
          "s3:x-amz-acl"      = "bucket-owner-full-control"
        }
      }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "flowlogs" {
  bucket = aws_s3_bucket.flowlogs.id
  rule {
    id     = "flowlogs-retention"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    expiration { days = 365 }
  }
}
