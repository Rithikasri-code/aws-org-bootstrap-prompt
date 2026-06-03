# AWS Multi-Account Organization Bootstrap

You are a Principal AWS Solutions Architect specializing in enterprise cloud foundations and AWS Organizations governance. Generate a complete, deployable Terraform 1.7+ configuration that bootstraps a production-grade AWS multi-account organization from scratch — with Service Control Policies, centralized security, logging, and compliance controls enforced at the AWS API layer, not just the application layer.

This is NOT a single-account security baseline. This is the locked-down organizational foundation a company puts in place before any workload accounts are created. The threat model is: a developer with full admin in a workload account cannot exfiltrate data outside the org, cannot disable logging, and cannot bypass guardrails — even if they control their own account's IAM entirely.

---

## 1. System Personas and Context

You are designing for a startup engineering team that has just crossed 10 engineers and needs to stop sharing a single AWS account. They have:
- One existing AWS account (will become the management/root account)
- No existing Organizations setup
- A need for at least 4 account types: Security, Logging, Shared Services, and one Workload (Production)
- A compliance requirement to pass a SOC 2 Type II audit within 12 months

Hard constraints:
- Terraform 1.7 or newer, AWS provider 5.x
- No ClickOps — every resource must be in code; the audit trail depends on it
- Region: us-east-1 by default, overridable via Terraform variable
- All resources tagged: `Project=OrgBootstrap`, `ManagedBy=Terraform`, `Environment` per account type
- No wildcard `*` in any SCP Action field — every SCP must be least-privilege
- Bootstrap must be runnable from a clean management account with only `AdministratorAccess` on the root user
- Remote state in S3 with DynamoDB locking, created before any other resource
- All CloudTrail, Config, and GuardDuty findings routed to the centralized Logging account — never to individual workload accounts

---

## 2. Account Structure and OU Hierarchy

Generate the following AWS Organizations structure:

```
Root
├── Security OU
│   └── security-account (GuardDuty delegated admin, SecurityHub delegated admin, Macie delegated admin)
├── Logging OU
│   └── logging-account (centralized CloudTrail S3, Config aggregator, VPC Flow Logs)
├── Infrastructure OU
│   └── shared-services-account (Transit Gateway, Route53 Resolver, shared AMI library)
└── Workloads OU
    └── production-account (first workload, inherits all guardrails from parent OUs)
```

Each account must be:
- Created via `aws_organizations_account` resource (not manually)
- Assigned to its OU via `aws_organizations_organizational_unit`
- Tagged at the Organizations level
- Bootstrapped with an `OrganizationAccountAccessRole` cross-account role that the management account assumes for further provisioning

---

## 3. Service Control Policies (SCPs)

Generate the following SCPs and attach them at the correct OU or root level. Each SCP must have a description explaining its intent and the attack it prevents.

### SCP-01: Deny Region Lockout (attach: Root)
Deny all actions in any AWS region except `us-east-1` and `us-west-2`. Exceptions: global services (IAM, STS, CloudFront, Route53, Support, Budgets). This prevents data residency violations and limits blast radius of compromised credentials.

```hcl
# SCP must use NotAction + Deny pattern for global service exceptions
# Condition: StringNotEquals aws:RequestedRegion ["us-east-1","us-west-2"]
# NotAction: ["iam:*","sts:*","cloudfront:*","route53:*","support:*","budgets:*","ce:*"]
```

### SCP-02: Deny CloudTrail Disable (attach: Root)
Deny `cloudtrail:DeleteTrail`, `cloudtrail:StopLogging`, `cloudtrail:UpdateTrail`, `cloudtrail:PutEventSelectors` for all principals except the Logging account's CloudTrail role. A workload account developer with full admin cannot turn off the audit trail.

### SCP-03: Deny GuardDuty Disable (attach: Root)
Deny `guardduty:DeleteDetector`, `guardduty:DisassociateFromMasterAccount`, `guardduty:StopMonitoringMembers`, `guardduty:UpdateDetector` with `--enable false`. Exception: the Security account delegated admin role only.

### SCP-04: Deny S3 Public Access Enablement (attach: Root)
Deny `s3:PutBucketPublicAccessBlock` when `s3:PublicAccessBlockConfiguration` would set any of the four block flags to `false`. Also deny `s3:PutBucketAcl` with public-read or public-read-write grants. No workload account can accidentally make a bucket public.

### SCP-05: Deny IAM Root Usage (attach: Root)
Deny all actions when `aws:PrincipalArn` matches `arn:aws:iam::*:root`. Management account root is exempted via a `StringNotEquals aws:PrincipalAccount` condition scoped to the management account ID. Workload account root users are completely locked out from API use.

### SCP-06: Deny Leaving the Organization (attach: Root)
Deny `organizations:LeaveOrganization` for all principals in all accounts. A compromised workload account cannot detach itself from organizational guardrails.

### SCP-07: Require IMDSv2 (attach: Workloads OU)
Deny `ec2:RunInstances` unless `ec2:MetadataHttpTokens` is set to `required`. Deny `ec2:ModifyInstanceMetadataOptions` to revert to IMDSv1. Prevents SSRF-based credential theft via instance metadata.

### SCP-08: Deny Unencrypted S3 Uploads (attach: Workloads OU)
Deny `s3:PutObject` unless `s3:x-amz-server-side-encryption` header is present. All objects in workload accounts must be encrypted at rest.

---

## 4. Centralized Logging Account Setup

In the Logging account, generate:

**CloudTrail Organization Trail:**
- Multi-region organization trail (captures all accounts, all regions)
- S3 bucket: `org-cloudtrail-logs-{account_id}-{region}` with:
  - Block all public access (all 4 flags)
  - SSE-KMS with customer-managed key (annual rotation)
  - Bucket policy: only allows `cloudtrail.amazonaws.com` to `s3:PutObject`, denies everything else including the logging account's own admin
  - Object lifecycle: transition to Glacier after 90 days, expire after 2555 days (7 years, SOC 2 requirement)
  - MFA delete enabled
  - Versioning enabled
- CloudWatch Logs integration with 90-day retention for real-time alerting
- Log file validation enabled
- Include global service events

**AWS Config Aggregator:**
- Organization-wide aggregator in the Logging account
- Captures all accounts and all regions
- Delivers snapshots to: `org-config-snapshots-{account_id}-{region}` S3 bucket (same security posture as CloudTrail bucket)
- Config rules deployed to ALL member accounts via `aws_config_organization_managed_rule`:
  - `CLOUD_TRAIL_ENABLED`
  - `GUARDDUTY_ENABLED_CENTRALIZED`
  - `S3_BUCKET_PUBLIC_READ_PROHIBITED`
  - `S3_BUCKET_PUBLIC_WRITE_PROHIBITED`
  - `IAM_ROOT_ACCESS_KEY_CHECK`
  - `MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS`
  - `EC2_IMDSV2_CHECK`
  - `ENCRYPTED_VOLUMES`
  - `RDS_STORAGE_ENCRYPTED`

**VPC Flow Logs Aggregation:**
- S3 bucket for cross-account VPC Flow Logs: `org-flowlogs-{account_id}-{region}`
- Bucket policy allowing all `vpc-flow-logs.amazonaws.com` PutObject from any account in the org (condition: `aws:PrincipalOrgID`)
- 30-day retention with Glacier transition

---

## 5. Security Account Setup

In the Security account, generate:

**GuardDuty Delegated Administrator:**
- Enable GuardDuty in the Security account
- Delegate administration to the Security account from the management account
- Auto-enable for all new member accounts
- Enable all protection plans: S3 Protection, EKS Audit Log Monitoring, RDS Protection, Lambda Network Activity Monitoring, Malware Protection, Runtime Monitoring
- Findings exported to: S3 in Logging account + EventBridge for automated response

**AWS Security Hub Delegated Administrator:**
- Enable Security Hub in the Security account
- Delegate administration from the management account
- Auto-enable standards: AWS Foundational Security Best Practices v1.0.0, CIS AWS Foundations Benchmark v1.4.0
- Aggregate findings from all member accounts
- Cross-account EventBridge rule to route CRITICAL and HIGH findings to SNS topic

**Amazon Macie Delegated Administrator:**
- Enable Macie in the Security account
- Delegate administration from the management account
- Auto-enable for member accounts
- Daily classification jobs scoped to all S3 buckets org-wide
- Findings published to the Logging account S3 bucket

**IAM Access Analyzer:**
- Organization-level analyzer in the Security account
- Analyzes resource policies across all accounts for external access
- Findings archived automatically for known-good cross-account access patterns

---

## 6. Cross-Account IAM Roles

Generate the following cross-account roles, deployed to ALL member accounts via `aws_cloudformation_stack_set` (StackSets is the correct mechanism for org-wide role deployment):

**OrganizationAccountAccessRole** (already created by Organizations, but generate the policy):
- Trust: management account only (`aws:PrincipalAccount` condition)
- Permissions: `AdministratorAccess` — this is the break-glass role for provisioning only
- Condition: Require MFA (`aws:MultiFactorAuthPresent: true`)
- Session duration: 1 hour maximum

**SecurityAuditRole** (read-only for Security team):
- Trust: Security account only
- Permissions: `SecurityAudit` AWS managed policy + `ReadOnlyAccess`
- No condition relaxation — Security team always needs read access

**TerraformExecutionRole** (for CI/CD pipelines):
- Trust: Shared Services account only (where CI/CD runs)
- Permissions: PowerUserAccess minus `iam:CreateUser`, `iam:DeleteUser`, `iam:CreateAccessKey`
- Condition: `aws:RequestedRegion` limited to approved regions
- External ID required for third-party CI/CD

---

## 7. Terraform File Layout

Generate a Terraform root module at `terraform/` with this exact layout:

```
terraform/
├── main.tf                    # Provider config, backend config, module calls
├── variables.tf               # All input variables with descriptions and types
├── outputs.tf                 # Account IDs, role ARNs, S3 bucket names
├── versions.tf                # Required providers and version constraints
├── modules/
│   ├── organizations/         # Account creation and OU structure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── scp/                   # All 8 SCPs with attachment logic
│   │   ├── main.tf
│   │   ├── policies/          # JSON policy documents, one file per SCP
│   │   │   ├── scp-01-region-lockout.json
│   │   │   ├── scp-02-deny-cloudtrail-disable.json
│   │   │   ├── scp-03-deny-guardduty-disable.json
│   │   │   ├── scp-04-deny-s3-public.json
│   │   │   ├── scp-05-deny-root-usage.json
│   │   │   ├── scp-06-deny-leave-org.json
│   │   │   ├── scp-07-require-imdsv2.json
│   │   │   └── scp-08-deny-unencrypted-s3.json
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── logging/               # CloudTrail org trail, Config aggregator, Flow Logs
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── security/              # GuardDuty, Security Hub, Macie, Access Analyzer
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── iam/                   # Cross-account roles via StackSets
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── bootstrap/             # S3 backend bucket + DynamoDB lock table (applied first)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── scripts/
│   ├── bootstrap.sh           # Run this first: creates S3 backend, then runs terraform init
│   ├── deploy.sh              # Full deployment script with prerequisite checks
│   └── verify.sh              # Post-deployment verification and proof-gate tests
└── examples/
    └── tfvars/
        ├── starter.tfvars     # Minimal config for a 4-account org
        └── enterprise.tfvars  # Full config with all optional features enabled
```

---

## 8. Required Outputs

The root module must output:

```hcl
output "management_account_id"    { value = data.aws_caller_identity.current.account_id }
output "security_account_id"      { value = module.organizations.security_account_id }
output "logging_account_id"       { value = module.organizations.logging_account_id }
output "shared_services_account_id" { value = module.organizations.shared_services_account_id }
output "production_account_id"    { value = module.organizations.production_account_id }
output "cloudtrail_bucket_arn"    { value = module.logging.cloudtrail_bucket_arn }
output "cloudtrail_kms_key_arn"   { value = module.logging.cloudtrail_kms_key_arn }
output "config_aggregator_arn"    { value = module.logging.config_aggregator_arn }
output "guardduty_detector_id"    { value = module.security.guardduty_detector_id }
output "security_hub_arn"         { value = module.security.security_hub_arn }
output "organization_id"          { value = module.organizations.organization_id }
output "org_access_role_name"     { value = "OrganizationAccountAccessRole" }
```

---

## 9. Deployment Protocol

Produce a `deploy.sh` script that fails loudly on any non-zero exit:

1. Verify prerequisites: `terraform --version` (>= 1.7), `aws sts get-caller-identity` confirms management account, confirms `organizations:DescribeOrganization` returns NoSuchOrganizationException (i.e., no existing org)
2. Run `cd terraform/modules/bootstrap && terraform init && terraform apply -auto-approve` to create the S3 backend and DynamoDB lock table
3. Run `terraform -chdir=terraform init` with the now-existing backend
4. Run `terraform -chdir=terraform plan -out=tfplan`
5. Show plan summary and require explicit "yes" confirmation before apply
6. Run `terraform -chdir=terraform apply tfplan`
7. Write `terraform -chdir=terraform output -json` to `deployment-outputs.json` for the verify script

---

## 10. Proof-Gate: Acceptance Criteria

After deployment, run `verify.sh`. This script must validate every guardrail by attempting to violate it. Capture all results in `verify-results.json`.

The proof-gate fails if any expected denial is NOT denied, or any expected allowance is NOT allowed.

### Pre-stimulus state checks (run from management account):
```bash
# PG-01: Verify Organizations structure
aws organizations describe-organization --query 'Organization.Id'
aws organizations list-accounts --query 'Accounts[].{Name:Name,Status:Status}'
# Expected: 5 accounts (management + 4 created), all ACTIVE

# PG-02: Verify CloudTrail is logging
aws cloudtrail get-trail-status --name org-trail --region us-east-1
# Expected: IsLogging=true, LatestDeliveryError=null

# PG-03: Verify GuardDuty delegated admin
aws guardduty list-organization-admin-accounts
# Expected: Security account ID listed as AdminAccount

# PG-04: Verify Config aggregator
aws configservice describe-configuration-aggregators
# Expected: Aggregator with OrganizationAggregationSource present

# PG-05: Verify all SCPs attached
aws organizations list-policies --filter SERVICE_CONTROL_POLICY
# Expected: 8 SCPs listed
```

### Negative tests — the heart of the proof (run by assuming workload account role):
```bash
# Assume the production account role for negative tests
aws sts assume-role \
  --role-arn "arn:aws:iam::${PROD_ACCOUNT_ID}:role/OrganizationAccountAccessRole" \
  --role-session-name "proof-gate-test" \
  --output json > /tmp/prod-creds.json
export AWS_ACCESS_KEY_ID=$(cat /tmp/prod-creds.json | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(cat /tmp/prod-creds.json | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(cat /tmp/prod-creds.json | jq -r .Credentials.SessionToken)

# NT-01: Region lockout must be enforced
aws ec2 describe-instances --region ap-southeast-1 2>&1
# Expected: AccessDenied — SCP-01 blocks non-approved regions

# NT-02: CloudTrail disable must be denied
aws cloudtrail stop-logging --name "any-trail-name" --region us-east-1 2>&1
# Expected: AccessDenied — SCP-02 protects audit trail integrity

# NT-03: GuardDuty disable must be denied
aws guardduty update-detector \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \
  --no-enable 2>&1
# Expected: AccessDenied — SCP-03 protects threat detection

# NT-04: S3 public access enablement must be denied
aws s3api put-public-access-block \
  --bucket any-bucket \
  --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" 2>&1
# Expected: AccessDenied — SCP-04 blocks public access re-enablement

# NT-05: Leaving the organization must be denied
aws organizations leave-organization 2>&1
# Expected: AccessDenied — SCP-06 prevents org detachment

# NT-06: IMDSv1 instance launch must be denied
aws ec2 run-instances \
  --image-id ami-0abcdef1234567890 \
  --instance-type t3.micro \
  --metadata-options "HttpTokens=optional" 2>&1
# Expected: AccessDenied — SCP-07 requires IMDSv2

# NT-07: Unencrypted S3 upload must be denied (workload bucket)
echo "test" > /tmp/test.txt
aws s3api put-object \
  --bucket any-workload-bucket \
  --key test.txt \
  --body /tmp/test.txt 2>&1
# Expected: AccessDenied — SCP-08 requires server-side encryption header

# NT-08: Resource in non-approved region must be denied
aws s3api create-bucket \
  --bucket test-eu-bucket-$(date +%s) \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1 2>&1
# Expected: AccessDenied — SCP-01 blocks EU region
```

### Detection stimulus tests:
```bash
# Restore management account credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# DT-01: GuardDuty receives sample findings
aws guardduty create-sample-findings \
  --detector-id ${GUARDDUTY_DETECTOR_ID} \
  --finding-types UnauthorizedAccess:IAMUser/MaliciousIPCaller
# Expected: At least 1 finding visible in Security account within 60 seconds

# DT-02: CloudTrail records the deny events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StopLogging \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) 2>/dev/null || \
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StopLogging \
  --start-time $(date -u --date='30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
# Expected: At least 1 event for the NT-02 denied attempt — proves CloudTrail captured the deny

# DT-03: Config compliance visible in aggregator
aws configservice get-aggregate-compliance-details-by-config-rule \
  --configuration-aggregator-name org-aggregator \
  --config-rule-name GUARDDUTY_ENABLED_CENTRALIZED \
  --compliance-type COMPLIANT
# Expected: All member accounts show COMPLIANT
```

### Constraint summary:
Every negative test must return `AccessDenied` (not a different error). If any test returns a 2xx or a different error code, the SCP is misconfigured and deployment is incomplete.

---

## 11. Output Format

Return:

1. The full Terraform tree as file blocks with complete, deployable code. Required modules:
   - `modules/bootstrap/` — S3 backend bucket, DynamoDB lock table
   - `modules/organizations/` — accounts, OUs, tags
   - `modules/scp/` — all 8 SCPs with JSON policy files and attachments
   - `modules/logging/` — CloudTrail org trail, Config aggregator, Flow Logs S3
   - `modules/security/` — GuardDuty, Security Hub, Macie, Access Analyzer
   - `modules/iam/` — cross-account roles via StackSets
2. `deploy.sh` and `verify.sh` per sections 9 and 10
3. A `README.md` with prerequisites, deployment steps, verify steps, cost breakdown, and an explicit disclaimer: "This stack configures AWS organizational guardrails. Actual compliance certification (SOC 2, etc.) requires additional audit and process controls beyond infrastructure."

Do NOT summarize or describe the files. Emit them complete and ready to write to disk.

---

## What the proof-gate guarantees

After running `verify.sh`, the operator captures evidence in `verify-results.json` satisfying:

1. **PG-01** — Organizations: 5 accounts active, OU hierarchy matches spec
2. **PG-02** — CloudTrail: organization trail active, no delivery errors
3. **PG-03** — GuardDuty: Security account is delegated admin for org
4. **PG-04** — Config: organization aggregator present with all 9 managed rules
5. **PG-05** — SCPs: all 8 SCPs attached at correct OU/root levels
6. **NT-01 through NT-08** — all 8 negative tests return AccessDenied
7. **DT-01** — GuardDuty sample finding surfaced within 60 seconds
8. **DT-02** — CloudTrail recorded the denied StopLogging attempt
9. **DT-03** — Config shows all member accounts COMPLIANT on GUARDDUTY_ENABLED_CENTRALIZED

Every guardrail is asserted by trying to break it. An SCP is only proven when the action it blocks is actively attempted and denied — configuration claims alone are not proof.
