output "scp_region_lockout_id" {
  description = "ID of SCP-01 (Region Lockout) — attached at Root"
  value       = aws_organizations_policy.scp_01_region_lockout.id
}

output "scp_protect_cloudtrail_id" {
  description = "ID of SCP-02 (Protect CloudTrail) — attached at Root"
  value       = aws_organizations_policy.scp_02_protect_cloudtrail.id
}

output "scp_protect_guardduty_id" {
  description = "ID of SCP-03 (Protect GuardDuty) — attached at Root"
  value       = aws_organizations_policy.scp_03_protect_guardduty.id
}

output "scp_deny_s3_public_id" {
  description = "ID of SCP-04 (Deny S3 Public Access) — attached at Root"
  value       = aws_organizations_policy.scp_04_deny_s3_public.id
}

output "scp_deny_root_id" {
  description = "ID of SCP-05 (Deny Root Usage) — attached at Root"
  value       = aws_organizations_policy.scp_05_deny_root.id
}

output "scp_deny_leave_org_id" {
  description = "ID of SCP-06 (Deny Leave Organization) — attached at Root"
  value       = aws_organizations_policy.scp_06_deny_leave_org.id
}

output "scp_require_imdsv2_id" {
  description = "ID of SCP-07 (Require IMDSv2) — attached at Workloads OU"
  value       = aws_organizations_policy.scp_07_require_imdsv2.id
}

output "scp_deny_unencrypted_s3_id" {
  description = "ID of SCP-08 (Deny Unencrypted S3 Uploads) — attached at Workloads OU"
  value       = aws_organizations_policy.scp_08_deny_unencrypted_s3.id
}

output "all_scp_ids" {
  description = "List of all 8 SCP IDs — use for verification in verify.sh"
  value = [
    aws_organizations_policy.scp_01_region_lockout.id,
    aws_organizations_policy.scp_02_protect_cloudtrail.id,
    aws_organizations_policy.scp_03_protect_guardduty.id,
    aws_organizations_policy.scp_04_deny_s3_public.id,
    aws_organizations_policy.scp_05_deny_root.id,
    aws_organizations_policy.scp_06_deny_leave_org.id,
    aws_organizations_policy.scp_07_require_imdsv2.id,
    aws_organizations_policy.scp_08_deny_unencrypted_s3.id,
  ]
}
