# AWS Multi-Account Organization Bootstrap

**One prompt → a production-grade AWS Organizations structure with 8 SCPs, centralized logging, GuardDuty, Security Hub, Macie, and 8 proof-gated negative tests that verify every guardrail by attempting to break it.**

Prompt: [prompt.md](./prompt.md)

**GitHub:** https://github.com/Rithikasri-code/aws-org-bootstrap-prompt

---

## The Problem

Every fast-growing startup hits the same wall around 10 engineers: everything lives in one AWS account, and the "fix it later" approach to account separation has accumulated years of blast radius. When they finally try to set up AWS Organizations:

- SCPs get written with `"Action": "*"` wildcards — defeating least-privilege entirely
- CloudTrail gets set up per-account, not as an org trail — gaps exist between accounts
- GuardDuty is enabled in the management account but never delegated — member accounts are unwatched
- Root user MFA is checked manually — no enforcement at the API layer
- A developer with admin in their workload account can turn off logging, re-enable S3 public access, launch IMDSv1 instances, and in extreme cases leave the organization entirely

The correct architecture is well known to senior AWS architects. This prompt closes the gap — one prompt, a production-grade organizational foundation.

---

## What You Get

Paste this prompt into Claude Code, Kiro IDE, Cursor, or any agentic coding assistant. Answer 6 questions (org name, management account ID, approved regions, alert email, environment tag, whether to enable Macie). Get:

- Complete Terraform 1.7+ codebase (~2,800 lines across 30+ files)
- 5 AWS accounts created and organized into 4 OUs
- 8 Service Control Policies enforced at the AWS API layer
- Organization-wide CloudTrail trail (7-year retention, KMS-encrypted, tamper-proof)
- AWS Config organization aggregator with 9 managed rules across all accounts
- GuardDuty, Security Hub, and Macie with delegated administration to Security account
- Cross-account IAM roles via CloudFormation StackSets
- `deploy.sh` and `verify.sh` with 8 negative tests that prove the guardrails hold

---

## Architecture

```
Management Account (root)
│
├── SCPs attached at Root (SCP-01 through SCP-06)
│   ├── SCP-01: Region lockout (us-east-1, us-west-2 only)
│   ├── SCP-02: Deny CloudTrail disable (any principal)
│   ├── SCP-03: Deny GuardDuty disable (any principal)
│   ├── SCP-04: Deny S3 public access re-enablement
│   ├── SCP-05: Deny root user API calls in workload accounts
│   └── SCP-06: Deny leaving the organization
│
├── Security OU → security-account
│   ├── GuardDuty delegated admin (all org members)
│   ├── Security Hub delegated admin (FSBP + CIS 1.4.0)
│   ├── Macie delegated admin
│   └── IAM Access Analyzer (org-level)
│
├── Logging OU → logging-account
│   ├── CloudTrail org trail → S3 (KMS, 7yr retention, MFA delete)
│   ├── Config organization aggregator → S3
│   └── VPC Flow Logs aggregation bucket (cross-account)
│
├── Infrastructure OU → shared-services-account
│   └── (Transit Gateway, Route53 Resolver — scaffolded, not deployed)
│
└── Workloads OU → production-account
    ├── Inherits SCP-01 through SCP-06 from Root
    └── Also inherits SCP-07 (require IMDSv2) + SCP-08 (deny unencrypted S3 uploads)
```

---

## The Unique Part: Two-Layer Enforcement

Most multi-account guides configure guardrails at the application layer (bucket policies, IAM policies). This prompt enforces at **both** layers:

**Layer 1: IAM/bucket policies** in each account — standard approach, breakable by an account admin.

**Layer 2: Service Control Policies at the OU/Root level** — these override all IAM policies in member accounts. Even an account's own root user (except the management account's root) cannot bypass them. SCP-02 means no principal in any workload account can call `cloudtrail:StopLogging` — not developers, not account admins, not the account's own root user.

The verify script proves this by assuming a role in the production account (with full admin) and attempting all 8 blocked actions. Every one must return `AccessDenied`.

---

## Validated End-to-End

Deployed to a real AWS free-tier eligible management account and confirmed:

- 5 accounts created and active in Organizations within 8 minutes
- All 8 SCPs attached at correct levels (verified via `aws organizations list-targets-for-policy`)
- CloudTrail org trail active across all 5 accounts (`IsLogging=true`, `LatestDeliveryError=null`)
- GuardDuty: Security account listed as `ENABLED` delegated admin
- Config aggregator: 9 managed rules showing COMPLIANT across all member accounts within 20 minutes
- NT-01 through NT-08: all 8 negative tests returned `AccessDenied` as expected
- DT-01: GuardDuty sample finding surfaced in Security account within 45 seconds
- DT-02: CloudTrail lookup returned the denied `StopLogging` event within 3 minutes
- `terraform validate` passed clean; `terraform plan` showed 127 resources to add

Cost (idle, no workloads): ~$23/month
- AWS Config: ~$14/month (9 rules × 5 accounts × ~100 evaluations/day)
- CloudTrail: ~$2/month (1 org trail, low activity)
- GuardDuty: ~$4/month (5 accounts, free tier applies per account)
- Macie: ~$1/month (minimum charge, no data classified yet)
- VPC endpoints: $0 (none created in this bootstrap)

---

## What Gets Generated

- **Terraform modules (6):** bootstrap, organizations, scp, logging, security, iam
- **Terraform files (~32 total):** main.tf, variables.tf, outputs.tf, versions.tf per module
- **SCP policy JSON files (8):** one per policy, human-readable with inline comments
- **Shell scripts (3):** bootstrap.sh (backend setup), deploy.sh (full deployment), verify.sh (proof-gate)
- **Example tfvars (2):** starter.tfvars (4 accounts), enterprise.tfvars (all options)
- **README.md:** prerequisites, deployment steps, verify steps, cost breakdown, disclaimer
- **Total:** ~2,800 lines of Terraform HCL + ~400 lines of shell scripts

---

## GitHub Repository

This repo includes:
- `prompt.md` — the full deliverable prompt (~3,200 words, copy-paste ready)
- `example-output/` — full Terraform codebase generated by the prompt on Claude Sonnet 4.5
- `screenshots/` — AWS Console showing Organizations structure, CloudTrail trail status, GuardDuty delegated admin, Config aggregator, and `verify.sh` output with all 8 NT tests passing
- MIT licensed

---

## AWS Services Used

| Service | Role |
|---|---|
| AWS Organizations | Account creation, OU hierarchy, SCP management |
| AWS CloudTrail | Organization-wide API audit trail |
| AWS Config | Compliance rules across all accounts |
| Amazon GuardDuty | Threat detection, delegated to Security account |
| AWS Security Hub | Findings aggregation, FSBP + CIS standards |
| Amazon Macie | PII/PHI discovery in S3 |
| IAM Access Analyzer | External access detection org-wide |
| Amazon S3 | CloudTrail logs, Config snapshots, Flow Logs |
| AWS KMS | Encryption for all log buckets |
| CloudFormation StackSets | Cross-account IAM role deployment |
| Amazon CloudWatch Logs | Real-time CloudTrail alerting |
| Amazon SNS | CRITICAL/HIGH Security Hub finding alerts |

---

## AWS Well-Architected Framework Alignment

**Security**
SCPs enforce least-privilege at the API layer — not just IAM policies. Root user API calls denied in all workload accounts. All 8 negative tests verify enforcement at runtime, not just configuration. KMS CMKs with annual rotation on all log storage. GuardDuty + Security Hub + Macie provide defense-in-depth threat detection.

**Operational Excellence**
Full Terraform IaC — no ClickOps anywhere. `deploy.sh` and `verify.sh` make deployment and validation repeatable and auditable. Config managed rules provide continuous compliance monitoring. Organizations structure enforced as code with version-controlled state.

**Reliability**
Organization trail is multi-region — captures API calls in all regions including regions blocked by SCP. Config aggregator covers all accounts and regions. GuardDuty auto-enables for new accounts via Organizations integration — zero day-one coverage gaps.

**Performance Efficiency**
Delegated admin pattern: Security and Logging account handle org-wide services, leaving workload accounts free of administrative overhead. CloudTrail S3 lifecycle rules (Glacier at 90 days) minimize ongoing storage cost without losing retention compliance.

**Cost Optimization**
Config rules targeted to the 9 highest-value checks rather than all 300+ available — avoids $300+/month Config bills at scale. CloudTrail org trail replaces 5 individual account trails at lower total cost. Macie on-demand classification (not continuous) for cost control. Estimated $23/month idle for a 5-account org.

**Sustainability**
Serverless throughout: CloudTrail, Config, GuardDuty, Security Hub, Macie are all managed services with no idle compute. S3 Intelligent-Tiering on log buckets automatically moves infrequently accessed logs to lower-energy storage tiers. No NAT Gateway, no always-on EC2 in this bootstrap.

---

## Honest Limitations

This prompt establishes the AWS organizational and infrastructure guardrails. It does NOT:
- Create application workloads, VPCs, or compute resources in workload accounts (intentional — those belong in workload-specific prompts)
- Configure SSO/IAM Identity Center (a separate prompt handles human access management)
- Constitute a SOC 2 certification — that requires business process controls, vendor assessments, and a third-party auditor
- Handle account vending automation for future accounts beyond the 4 created here

Part of a 3-prompt series:
- **#01 AWS Multi-Account Organization Bootstrap** ← this submission
- **#02 AWS IAM Identity Center + Permission Sets** — human access to the org (separate BUIDL)
- **#03 AWS Workload Account VPC Baseline** — production-ready VPC in a member account (separate BUIDL)

---

## Prerequisites

- AWS management account with `AdministratorAccess` on the root user
- Terraform 1.7+ installed locally
- AWS CLI v2 configured with management account credentials
- `jq` installed (used by verify.sh)
- 4 unique email addresses for the 4 new accounts (AWS requires unique email per account)
- Approximately 15–20 minutes for full deployment (account creation is the bottleneck)

**Disclaimer:** This stack configures AWS organizational guardrails. Actual compliance certification (SOC 2, ISO 27001, etc.) requires additional audit, process controls, and third-party assessment beyond infrastructure configuration.
