data "aws_caller_identity" "management" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────
# StackSet: Cross-Account IAM Roles
# Deployed to ALL member accounts via Organizations
# ─────────────────────────────────────────────
resource "aws_cloudformation_stack_set" "cross_account_roles" {
  name             = "OrgCrossAccountRoles"
  description      = "Deploys standardized cross-account IAM roles to all member accounts"
  permission_model = "SERVICE_MANAGED"
  call_as          = "DELEGATED_ADMIN"

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  capabilities = ["CAPABILITY_NAMED_IAM"]

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description = "OrgBootstrap — Cross-account IAM roles for Security audit and CI/CD"

    Parameters = {
      ManagementAccountId = {
        Type        = "String"
        Description = "AWS Account ID of the management account"
      }
      SecurityAccountId = {
        Type        = "String"
        Description = "AWS Account ID of the Security account"
      }
      SharedServicesAccountId = {
        Type        = "String"
        Description = "AWS Account ID of the Shared Services account (CI/CD)"
      }
      CiCdExternalId = {
        Type        = "String"
        Description = "External ID required for CI/CD tool to assume TerraformExecutionRole"
        NoEcho      = true
      }
    }

    Resources = {
      # ── SecurityAuditRole ────────────────────
      # Read-only for Security team — assumed from Security account
      SecurityAuditRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "SecurityAuditRole"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { AWS = { "Fn::Sub" = "arn:aws:iam::${SecurityAccountId}:root" } }
              Action    = "sts:AssumeRole"
              Condition = {
                Bool              = { "aws:MultiFactorAuthPresent" = "true" }
                StringEquals      = { "sts:ExternalId" = "security-audit-readonly" }
              }
            }]
          }
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/SecurityAudit",
            "arn:aws:iam::aws:policy/ReadOnlyAccess"
          ]
          MaxSessionDuration = 3600
          Tags = [
            { Key = "Project",   Value = "OrgBootstrap" },
            { Key = "ManagedBy", Value = "Terraform" },
            { Key = "Purpose",   Value = "SecurityAuditReadOnly" }
          ]
        }
      }

      # ── TerraformExecutionRole ───────────────
      # For CI/CD pipelines running from Shared Services account
      TerraformExecutionRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "TerraformExecutionRole"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { AWS = { "Fn::Sub" = "arn:aws:iam::${SharedServicesAccountId}:root" } }
              Action    = "sts:AssumeRole"
              Condition = {
                StringEquals = { "sts:ExternalId" = { Ref = "CiCdExternalId" } }
                Bool         = { "aws:MultiFactorAuthPresent" = "false" } # CI/CD uses OIDC
              }
            }]
          }
          MaxSessionDuration = 3600
          Tags = [
            { Key = "Project",   Value = "OrgBootstrap" },
            { Key = "ManagedBy", Value = "Terraform" },
            { Key = "Purpose",   Value = "CICDPipelineExecution" }
          ]
        }
      }

      # Inline policy for TerraformExecutionRole
      # PowerUser minus dangerous IAM actions
      TerraformExecutionPolicy = {
        Type = "AWS::IAM::Policy"
        Properties = {
          PolicyName = "TerraformExecutionPolicy"
          Roles      = [{ Ref = "TerraformExecutionRole" }]
          PolicyDocument = {
            Version = "2012-10-17"
            Statement = [
              {
                Sid      = "AllowPowerUser"
                Effect   = "Allow"
                NotAction = [
                  "iam:CreateUser",
                  "iam:DeleteUser",
                  "iam:CreateAccessKey",
                  "iam:DeleteAccessKey",
                  "organizations:*",
                  "account:*"
                ]
                Resource = "*"
              },
              {
                Sid    = "AllowLimitedIAM"
                Effect = "Allow"
                Action = [
                  "iam:CreateRole",
                  "iam:DeleteRole",
                  "iam:AttachRolePolicy",
                  "iam:DetachRolePolicy",
                  "iam:PutRolePolicy",
                  "iam:DeleteRolePolicy",
                  "iam:TagRole",
                  "iam:UntagRole",
                  "iam:GetRole",
                  "iam:ListRoles",
                  "iam:PassRole"
                ]
                Resource = "*"
              },
              {
                Sid    = "DenyNonApprovedRegions"
                Effect = "Deny"
                Action = "*"
                Resource = "*"
                Condition = {
                  StringNotEquals = {
                    "aws:RequestedRegion" = var.approved_regions
                  }
                }
              }
            ]
          }
        }
      }

      # ── ReadOnlyRole ─────────────────────────
      # Generic read-only for developers — no sensitive data access
      ReadOnlyRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "OrgReadOnlyRole"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { AWS = { "Fn::Sub" = "arn:aws:iam::${ManagementAccountId}:root" } }
              Action    = "sts:AssumeRole"
              Condition = {
                Bool = { "aws:MultiFactorAuthPresent" = "true" }
              }
            }]
          }
          ManagedPolicyArns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
          MaxSessionDuration = 3600
          Tags = [
            { Key = "Project",   Value = "OrgBootstrap" },
            { Key = "ManagedBy", Value = "Terraform" },
            { Key = "Purpose",   Value = "DeveloperReadOnly" }
          ]
        }
      }
    }

    Outputs = {
      SecurityAuditRoleArn = {
        Description = "ARN of the SecurityAuditRole"
        Value       = { "Fn::GetAtt" = ["SecurityAuditRole", "Arn"] }
      }
      TerraformExecutionRoleArn = {
        Description = "ARN of the TerraformExecutionRole"
        Value       = { "Fn::GetAtt" = ["TerraformExecutionRole", "Arn"] }
      }
    }
  })

  tags = var.common_tags
}

# ─────────────────────────────────────────────
# Deploy StackSet to the entire organization
# ─────────────────────────────────────────────
resource "aws_cloudformation_stack_set_instance" "org_wide" {
  stack_set_name = aws_cloudformation_stack_set.cross_account_roles.name
  call_as        = "DELEGATED_ADMIN"

  deployment_targets {
    organizational_unit_ids = var.all_ou_ids
  }

  parameter_overrides = {
    ManagementAccountId     = data.aws_caller_identity.management.account_id
    SecurityAccountId       = var.security_account_id
    SharedServicesAccountId = var.shared_services_account_id
    CiCdExternalId          = var.cicd_external_id
  }

  operation_preferences {
    failure_tolerance_percentage = 20
    max_concurrent_percentage    = 50
    region_concurrency_type      = "SEQUENTIAL"
  }
}

# ─────────────────────────────────────────────
# Password policy for management account
# ─────────────────────────────────────────────
resource "aws_iam_account_password_policy" "management" {
  minimum_password_length        = 16
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
  hard_expiry                    = false
}
