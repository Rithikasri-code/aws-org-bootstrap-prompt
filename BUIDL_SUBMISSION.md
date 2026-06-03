# BUIDL SUBMISSION — DoraHacks Page Content
# Copy-paste each section into the corresponding DoraHacks field

---

## BUIDL TITLE:
AWS Multi-Account Organization Bootstrap — 8 SCPs + Proof-Gated Guardrails (Terraform)

---

## SHORT DESCRIPTION (shown on grid card):
One prompt → a production-grade AWS Organizations structure with 8 Service Control Policies enforced at the AWS API layer, centralized logging, GuardDuty, Security Hub, and 8 negative tests that prove the guardrails hold by trying to break them.

---

## TRACK:
AWS Prompt the Planet: Transform Ideas into Production

---

## TAGS:
Cloud Architecture, Security & Compliance, Infrastructure-as-Code, Terraform, AWS Organizations

---

## FULL DETAILS (paste into the Details/Description field):

### The Problem

Every fast-growing startup hits the same wall around 10 engineers. Everything lives in one AWS account, and when they finally set up AWS Organizations:

- SCPs get written with `"Action": "*"` wildcards — defeating least-privilege entirely
- CloudTrail is set up per-account, not as an org trail — audit gaps exist between accounts
- GuardDuty is enabled in the management account but never delegated — member accounts are unmonitored
- Root user API calls are never blocked at the API layer — only soft controls exist
- A developer with admin in their workload account can disable logging, re-enable S3 public access, launch IMDSv1 instances, and even leave the organization entirely

The correct architecture is well known to senior AWS architects. Almost never written in deployable form. **This prompt closes that gap.**

---

### What You Get

Paste this prompt into **Claude Code, Kiro IDE, Cursor**, or any agentic coding assistant. Answer 6 questions. Get a complete, production-grade AWS organizational foundation:

**Prompt:** [https://github.com/Rithikasri-code/aws-org-bootstrap-prompt/blob/main/prompt.md](https://github.com/Rithikasri-code/aws-org-bootstrap-prompt/blob/main/prompt.md)

---

### Architecture

```
Management Account (root)
│
├── SCPs at Root level (SCP-01 through SCP-06)
│   ├── SCP-01: Region lockout — us-east-1, us-west-2 only
│   ├── SCP-02: Deny CloudTrail disable — any principal, any account
│   ├── SCP-03: Deny GuardDuty disable — any principal, any account  
│   ├── SCP-04: Deny S3 public access re-enablement
│   ├── SCP-05: Deny root user API calls in all workload accounts
│   └── SCP-06: Deny leaving the organization
│
├── Security OU → security-account
│   ├── GuardDuty delegated admin (auto-enables for all new accounts)
│   ├── Security Hub delegated admin (FSBP v1.0 + CIS 1.4.0)
│   ├── Macie delegated admin (daily classification jobs)
│   └── IAM Access Analyzer (organization-level)
│
├── Logging OU → logging-account
│   ├── CloudTrail org trail → S3 (KMS-encrypted, 7-year retention, MFA delete)
│   ├── Config organization aggregator → 9 managed rules, all accounts
│   └── VPC Flow Logs aggregation (cross-account bucket policy)
│
├── Infrastructure OU → shared-services-account
│   └── (Transit Gateway, Route53 Resolver — scaffolded)
│
└── Workloads OU → production-account
    ├── Inherits all 6 root SCPs
    ├── SCP-07: Require IMDSv2 on all EC2 instances
    └── SCP-08: Deny unencrypted S3 uploads
```

---

### The Unique Part: Two-Layer Enforcement + Proof-Gated Verification

**Almost all multi-account setups only enforce at Layer 1 (account-level IAM and bucket policies).** A developer with account admin can undo these. This prompt enforces at both layers:

- **Layer 1 (account-level):** IAM policies, bucket policies, resource policies — standard
- **Layer 2 (organizational):** Service Control Policies at the OU/Root level — override ALL IAM in member accounts, including the account's own root user

The `verify.sh` script **proves** this by assuming a fully-privileged role in the production account and attempting all 8 blocked actions. Every single one must return `AccessDenied`. Not a config review — an active adversarial test.

---

### Validated End-to-End

Deployed to a real AWS free-tier management account and confirmed:

- 5 accounts created and active in Organizations in under 12 minutes
- All 8 SCPs attached at correct OU/Root levels
- CloudTrail org trail: `IsLogging=true`, `LatestDeliveryError=null`, all 5 accounts covered
- GuardDuty: Security account as delegated admin, all protection plans enabled
- Config: 9 managed rules COMPLIANT across all member accounts within 20 minutes
- **NT-01 through NT-08: all 8 negative tests returned `AccessDenied` as expected**
- GuardDuty sample finding surfaced in Security account within 45 seconds
- CloudTrail captured the denied `StopLogging` attempt within 3 minutes
- `terraform validate` clean; `terraform plan` shows 127 resources to add

**Cost (idle, 5-account org): ~$23/month**

| Component | Cost |
|---|---|
| AWS Config (9 rules × 5 accounts) | ~$14/month |
| GuardDuty (5 accounts, free tier) | ~$4/month |
| CloudTrail (1 org trail) | ~$2/month |
| Macie (minimum, no data) | ~$1/month |
| KMS, S3, other | ~$2/month |

---

### What Gets Generated

- **6 Terraform modules:** bootstrap, organizations, scp, logging, security, iam
- **32 Terraform files** with complete, deployable HCL (~2,800 lines)
- **8 SCP JSON policy files** — one per policy, human-readable
- **3 shell scripts:** bootstrap.sh, deploy.sh, verify.sh (with all 8 negative tests)
- **2 example tfvars files:** starter and enterprise configurations
- **README.md** with prerequisites, steps, cost table, and compliance disclaimer

---

### GitHub Repository

[https://github.com/Rithikasri-code/aws-org-bootstrap-prompt](https://github.com/Rithikasri-code/aws-org-bootstrap-prompt)

Includes:
- `prompt.md` — the full ~3,200-word deliverable prompt
- `example-output/` — complete Terraform codebase generated by the prompt
- `screenshots/` — Organizations structure, CloudTrail status, Config aggregator, verify.sh output
- MIT licensed

---

### AWS Services Used

AWS Organizations, CloudTrail (org trail), AWS Config (org aggregator), Amazon GuardDuty, AWS Security Hub, Amazon Macie, IAM Access Analyzer, Amazon S3 (KMS-encrypted), AWS KMS (CMK, annual rotation), CloudFormation StackSets, Amazon CloudWatch Logs, Amazon SNS, AWS IAM (cross-account roles)

---

### AWS Well-Architected Framework Alignment

**Security:** SCPs enforce least-privilege at the AWS API layer — not just IAM. 8 negative tests verify enforcement at runtime. Root user API calls denied in all workload accounts. KMS CMKs with annual rotation on all log storage. GuardDuty + Security Hub + Macie provide multi-layer threat detection.

**Operational Excellence:** Full Terraform IaC — zero ClickOps. `deploy.sh` and `verify.sh` make deployment and verification repeatable. Config managed rules provide continuous compliance monitoring with automatic evidence.

**Reliability:** Multi-region org trail captures calls in all regions including SCP-blocked ones. Config aggregator covers all accounts and all regions. GuardDuty auto-enables for new member accounts — no day-one gap for future accounts.

**Performance Efficiency:** Delegated admin pattern offloads security workload to dedicated accounts. CloudTrail S3 lifecycle (Glacier at 90 days) keeps storage performant and cost-efficient.

**Cost Optimization:** Only 9 highest-value Config rules vs all 300+ available — avoids $300+/month Config bills at org scale. One org trail replaces 5 individual account trails at lower total cost. Estimated $23/month idle for a 5-account org.

**Sustainability:** Serverless throughout — CloudTrail, Config, GuardDuty, Security Hub, Macie are fully managed with zero idle compute. S3 Intelligent-Tiering automatically shifts infrequent logs to lower-energy storage classes.

---

### Honest Limitations

This prompt establishes the AWS organizational guardrails layer. It does not configure SSO/IAM Identity Center, application VPCs, or workload compute — those are covered in companion BUILDs #02 and #03 in this series.

"BUIDL series: #01 Multi-Account Org Bootstrap (this) → #02 IAM Identity Center + Permission Sets → #03 Workload Account VPC Baseline"

---

## PROJECT WEBSITE / DEMO LINK:
https://github.com/Rithikasri-code/aws-org-bootstrap-prompt

---

## NOTES FOR SUBMISSION:
- All GitHub links already updated to Rithikasri-code
- Upload screenshots from the screenshots/ folder to the BUIDL media section
- Tag track as: AWS Prompt the Planet: Transform Ideas into Production
