terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "REPLACE_WITH_STATE_BUCKET_NAME"
    key            = "org-bootstrap/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = local.common_tags
  }
}

# Assume role into logging account for logging module
provider "aws" {
  alias  = "logging"
  region = var.primary_region
  assume_role {
    role_arn = "arn:aws:iam::${module.organizations.logging_account_id}:role/OrganizationAccountAccessRole"
  }
  default_tags { tags = local.common_tags }
}

# Assume role into security account for security module
provider "aws" {
  alias  = "security"
  region = var.primary_region
  assume_role {
    role_arn = "arn:aws:iam::${module.organizations.security_account_id}:role/OrganizationAccountAccessRole"
  }
  default_tags { tags = local.common_tags }
}

data "aws_caller_identity" "management" {}

locals {
  common_tags = {
    Project   = "OrgBootstrap"
    ManagedBy = "Terraform"
  }
}

# ─────────────────────────────────────────────
# Module: Organizations — accounts + OUs
# ─────────────────────────────────────────────
module "organizations" {
  source = "./modules/organizations"

  org_name                      = var.org_name
  security_account_email        = var.security_account_email
  logging_account_email         = var.logging_account_email
  shared_services_account_email = var.shared_services_account_email
  production_account_email      = var.production_account_email
  common_tags                   = local.common_tags
}

# ─────────────────────────────────────────────
# Module: SCPs — all 8 policies + attachments
# ─────────────────────────────────────────────
module "scp" {
  source = "./modules/scp"

  root_id               = module.organizations.root_id
  workloads_ou_id       = module.organizations.workloads_ou_id
  management_account_id = data.aws_caller_identity.management.account_id
  security_account_id   = module.organizations.security_account_id
  logging_account_id    = module.organizations.logging_account_id
  approved_regions      = var.approved_regions
  common_tags           = local.common_tags

  depends_on = [module.organizations]
}

# ─────────────────────────────────────────────
# Module: Logging — CloudTrail, Config, FlowLogs
# ─────────────────────────────────────────────
module "logging" {
  source = "./modules/logging"
  providers = { aws = aws.logging }

  management_account_id = data.aws_caller_identity.management.account_id
  organization_id       = module.organizations.organization_id
  common_tags           = local.common_tags

  depends_on = [module.organizations, module.scp]
}

# ─────────────────────────────────────────────
# Module: Security — GuardDuty, SecurityHub, Macie
# ─────────────────────────────────────────────
module "security" {
  source = "./modules/security"
  providers = { aws = aws.security }

  organization_id      = module.organizations.organization_id
  security_alert_email = var.security_alert_email
  logging_account_id   = module.organizations.logging_account_id
  common_tags          = local.common_tags

  depends_on = [module.organizations, module.scp]
}
