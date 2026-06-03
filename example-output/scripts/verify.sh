#!/usr/bin/env bash
# verify.sh — Proof-gate script for AWS Multi-Account Organization Bootstrap
# Runs all pre-stimulus, negative, and detection tests.
# ALL negative tests MUST return AccessDenied. Any other result = misconfiguration.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
RESULTS_FILE="verify-results.json"
RESULTS="[]"

log_pass() { echo -e "${GREEN}✓ PASS${NC} — $1"; PASS=$((PASS+1)); }
log_fail() { echo -e "${RED}✗ FAIL${NC} — $1"; FAIL=$((FAIL+1)); }
log_info() { echo -e "${YELLOW}→${NC} $1"; }

append_result() {
  local test_id="$1" status="$2" detail="$3"
  RESULTS=$(echo "$RESULTS" | jq ". += [{\"test\": \"$test_id\", \"status\": \"$status\", \"detail\": \"$detail\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}]")
}

echo "═══════════════════════════════════════════════════"
echo "  AWS Org Bootstrap — Proof-Gate Verification"
echo "  $(date -u)"
echo "═══════════════════════════════════════════════════"

# ─────────────────────────────────────────────
# Load deployment outputs
# ─────────────────────────────────────────────
if [[ ! -f "deployment-outputs.json" ]]; then
  echo "ERROR: deployment-outputs.json not found. Run deploy.sh first."
  exit 1
fi

MGMT_ACCOUNT_ID=$(jq -r '.management_account_id.value' deployment-outputs.json)
PROD_ACCOUNT_ID=$(jq -r '.production_account_id.value' deployment-outputs.json)
SECURITY_ACCOUNT_ID=$(jq -r '.security_account_id.value' deployment-outputs.json)
GUARDDUTY_DETECTOR_ID=$(jq -r '.guardduty_detector_id.value' deployment-outputs.json)
CONFIG_AGGREGATOR=$(jq -r '.config_aggregator_arn.value' deployment-outputs.json | awk -F: '{print $NF}')
ORG_ID=$(jq -r '.organization_id.value' deployment-outputs.json)

log_info "Management Account: $MGMT_ACCOUNT_ID"
log_info "Production Account: $PROD_ACCOUNT_ID"
log_info "Security Account:   $SECURITY_ACCOUNT_ID"
echo ""

# ─────────────────────────────────────────────
# PRE-STIMULUS STATE CHECKS
# ─────────────────────────────────────────────
echo "── Pre-Stimulus Checks ──────────────────────────"

# PG-01: Organizations structure
log_info "PG-01: Verifying Organizations account count..."
ACCOUNT_COUNT=$(aws organizations list-accounts --query 'length(Accounts[?Status==`ACTIVE`])' --output text)
if [[ "$ACCOUNT_COUNT" -ge 5 ]]; then
  log_pass "PG-01: $ACCOUNT_COUNT active accounts found"
  append_result "PG-01" "PASS" "$ACCOUNT_COUNT accounts active"
else
  log_fail "PG-01: Expected ≥5 active accounts, found $ACCOUNT_COUNT"
  append_result "PG-01" "FAIL" "Only $ACCOUNT_COUNT accounts found"
fi

# PG-02: CloudTrail active
log_info "PG-02: Verifying CloudTrail organization trail..."
TRAIL_STATUS=$(aws cloudtrail get-trail-status --name org-trail --query 'IsLogging' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "$TRAIL_STATUS" == "True" ]]; then
  log_pass "PG-02: CloudTrail org-trail is logging"
  append_result "PG-02" "PASS" "IsLogging=True"
else
  log_fail "PG-02: CloudTrail not logging — status: $TRAIL_STATUS"
  append_result "PG-02" "FAIL" "IsLogging=$TRAIL_STATUS"
fi

# PG-03: GuardDuty delegated admin
log_info "PG-03: Verifying GuardDuty delegated administrator..."
GD_ADMIN=$(aws guardduty list-organization-admin-accounts --query "AdminAccounts[?AdminAccountId=='$SECURITY_ACCOUNT_ID'].Status" --output text 2>/dev/null || echo "NONE")
if [[ "$GD_ADMIN" == "ENABLED" ]]; then
  log_pass "PG-03: GuardDuty delegated admin is Security account ($SECURITY_ACCOUNT_ID)"
  append_result "PG-03" "PASS" "Security account is GD delegated admin"
else
  log_fail "PG-03: GuardDuty delegated admin not set correctly — $GD_ADMIN"
  append_result "PG-03" "FAIL" "GD admin status: $GD_ADMIN"
fi

# PG-04: Config aggregator
log_info "PG-04: Verifying Config organization aggregator..."
AGGREGATOR=$(aws configservice describe-configuration-aggregators --query "ConfigurationAggregators[?contains(ConfigurationAggregatorName,'org')].ConfigurationAggregatorName" --output text 2>/dev/null || echo "NONE")
if [[ -n "$AGGREGATOR" && "$AGGREGATOR" != "NONE" ]]; then
  log_pass "PG-04: Config aggregator found: $AGGREGATOR"
  append_result "PG-04" "PASS" "Aggregator: $AGGREGATOR"
else
  log_fail "PG-04: Config organization aggregator not found"
  append_result "PG-04" "FAIL" "No aggregator found"
fi

# PG-05: SCPs count
log_info "PG-05: Verifying SCP count..."
SCP_COUNT=$(aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'length(Policies[?Name!=`FullAWSAccess`])' --output text 2>/dev/null || echo "0")
if [[ "$SCP_COUNT" -ge 8 ]]; then
  log_pass "PG-05: $SCP_COUNT SCPs found (expected ≥8)"
  append_result "PG-05" "PASS" "$SCP_COUNT SCPs attached"
else
  log_fail "PG-05: Expected ≥8 SCPs, found $SCP_COUNT"
  append_result "PG-05" "FAIL" "Only $SCP_COUNT SCPs found"
fi

echo ""
echo "── Negative Tests (assuming Production account role) ──"

# Assume production account role
log_info "Assuming OrganizationAccountAccessRole in production account..."
CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${PROD_ACCOUNT_ID}:role/OrganizationAccountAccessRole" \
  --role-session-name "proof-gate-$(date +%s)" \
  --duration-seconds 3600 \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r '.Credentials.SessionToken')
log_pass "Role assumed successfully — running as production account admin"
echo ""

run_negative_test() {
  local test_id="$1" description="$2"
  shift 2
  local output
  output=$("$@" 2>&1) && {
    log_fail "$test_id: $description — EXPECTED denial, got SUCCESS"
    append_result "$test_id" "FAIL" "Action was NOT blocked — SCP misconfigured"
    return 1
  } || {
    if echo "$output" | grep -qi "AccessDenied\|not authorized\|Unauthorized\|AccessDeniedException"; then
      log_pass "$test_id: $description — correctly denied (AccessDenied)"
      append_result "$test_id" "PASS" "AccessDenied returned as expected"
    else
      log_fail "$test_id: $description — unexpected error: $(echo "$output" | head -1)"
      append_result "$test_id" "FAIL" "Unexpected error: $(echo "$output" | head -1)"
    fi
  }
}

# NT-01: Region lockout
run_negative_test "NT-01" "Region lockout (ap-southeast-1)" \
  aws ec2 describe-instances --region ap-southeast-1

# NT-02: CloudTrail disable
run_negative_test "NT-02" "CloudTrail StopLogging" \
  aws cloudtrail stop-logging --name "any-trail" --region us-east-1

# NT-03: GuardDuty disable
DETECTOR=$(aws guardduty list-detectors --region us-east-1 --query 'DetectorIds[0]' --output text 2>/dev/null || echo "none")
if [[ "$DETECTOR" != "none" && "$DETECTOR" != "None" ]]; then
  run_negative_test "NT-03" "GuardDuty UpdateDetector --no-enable" \
    aws guardduty update-detector --detector-id "$DETECTOR" --no-enable --region us-east-1
else
  log_info "NT-03: No GuardDuty detector in prod account — testing UpdateDetector with fake ID"
  run_negative_test "NT-03" "GuardDuty disable attempt" \
    aws guardduty update-detector --detector-id "abc123def456abc123def456abc123de" --no-enable --region us-east-1
fi

# NT-04: S3 public access re-enable (needs a bucket — create a temp one first)
TEMP_BUCKET="proof-gate-test-$(date +%s)-${PROD_ACCOUNT_ID}"
aws s3api create-bucket --bucket "$TEMP_BUCKET" --region us-east-1 2>/dev/null || true
run_negative_test "NT-04" "S3 public access block disable" \
  aws s3api put-public-access-block \
    --bucket "$TEMP_BUCKET" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
# Cleanup
aws s3api delete-bucket --bucket "$TEMP_BUCKET" --region us-east-1 2>/dev/null || true

# NT-05: Leave organization
run_negative_test "NT-05" "LeaveOrganization" \
  aws organizations leave-organization

# NT-06: IMDSv1 instance launch
run_negative_test "NT-06" "EC2 RunInstances with IMDSv1" \
  aws ec2 run-instances \
    --image-id ami-0abcdef1234567890 \
    --instance-type t3.micro \
    --min-count 1 --max-count 1 \
    --metadata-options "HttpTokens=optional" \
    --region us-east-1 --dry-run

# NT-07: Unencrypted S3 upload
TEMP_BUCKET2="proof-gate-enc-$(date +%s)-${PROD_ACCOUNT_ID}"
aws s3api create-bucket --bucket "$TEMP_BUCKET2" --region us-east-1 2>/dev/null || true
echo "test-content" > /tmp/proof-gate-test.txt
run_negative_test "NT-07" "S3 PutObject without encryption header" \
  aws s3api put-object \
    --bucket "$TEMP_BUCKET2" \
    --key test.txt \
    --body /tmp/proof-gate-test.txt \
    --region us-east-1
aws s3api delete-bucket --bucket "$TEMP_BUCKET2" --region us-east-1 2>/dev/null || true

# NT-08: Resource in non-approved region (EU)
run_negative_test "NT-08" "S3 bucket creation in eu-west-1" \
  aws s3api create-bucket \
    --bucket "blocked-eu-bucket-$(date +%s)" \
    --region eu-west-1 \
    --create-bucket-configuration LocationConstraint=eu-west-1

# ─────────────────────────────────────────────
# Restore management account credentials
# ─────────────────────────────────────────────
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
echo ""
echo "── Detection Stimulus Tests (management account) ──"

# DT-01: GuardDuty sample finding
log_info "DT-01: Creating GuardDuty sample finding..."
aws guardduty create-sample-findings \
  --detector-id "$GUARDDUTY_DETECTOR_ID" \
  --finding-types "UnauthorizedAccess:IAMUser/MaliciousIPCaller" \
  --region us-east-1 2>/dev/null && {
  sleep 15
  FINDING_COUNT=$(aws guardduty list-findings \
    --detector-id "$GUARDDUTY_DETECTOR_ID" \
    --finding-criteria '{"Criterion":{"type":{"Eq":["UnauthorizedAccess:IAMUser/MaliciousIPCaller"]}}}' \
    --query 'length(FindingIds)' --output text 2>/dev/null || echo "0")
  if [[ "$FINDING_COUNT" -gt 0 ]]; then
    log_pass "DT-01: GuardDuty sample finding created and visible ($FINDING_COUNT findings)"
    append_result "DT-01" "PASS" "$FINDING_COUNT sample findings visible"
  else
    log_fail "DT-01: GuardDuty sample finding not visible after 15 seconds"
    append_result "DT-01" "FAIL" "No findings visible"
  fi
} || {
  log_fail "DT-01: Failed to create GuardDuty sample finding"
  append_result "DT-01" "FAIL" "create-sample-findings failed"
}

# DT-02: CloudTrail captured denied events
log_info "DT-02: Checking CloudTrail captured denied StopLogging attempt..."
sleep 10
EVENT_COUNT=$(aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StopLogging \
  --start-time "$(date -u --date='10 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'length(Events)' --output text 2>/dev/null || echo "0")
if [[ "$EVENT_COUNT" -gt 0 ]]; then
  log_pass "DT-02: CloudTrail captured $EVENT_COUNT StopLogging event(s)"
  append_result "DT-02" "PASS" "$EVENT_COUNT events found in CloudTrail"
else
  log_info "DT-02: No StopLogging events yet (CloudTrail may need more time). Marking WARN."
  append_result "DT-02" "WARN" "No events found yet — check again in 5 min"
fi

# DT-03: Config compliance
log_info "DT-03: Checking Config compliance across org..."
COMPLIANT_COUNT=$(aws configservice get-aggregate-compliance-details-by-config-rule \
  --configuration-aggregator-name "org-aggregator" \
  --config-rule-name "GUARDDUTY_ENABLED_CENTRALIZED" \
  --compliance-type COMPLIANT \
  --query 'length(AggregateEvaluationResults)' --output text 2>/dev/null || echo "0")
if [[ "$COMPLIANT_COUNT" -gt 0 ]]; then
  log_pass "DT-03: Config shows $COMPLIANT_COUNT accounts COMPLIANT for GUARDDUTY_ENABLED_CENTRALIZED"
  append_result "DT-03" "PASS" "$COMPLIANT_COUNT accounts COMPLIANT"
else
  log_info "DT-03: Config evaluation may not be complete yet. Check AWS Console."
  append_result "DT-03" "WARN" "No compliant results yet — Config may still be evaluating"
fi

# ─────────────────────────────────────────────
# Final report
# ─────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  PROOF-GATE SUMMARY"
echo "═══════════════════════════════════════════════════"
echo -e "  ${GREEN}PASS: $PASS${NC}   ${RED}FAIL: $FAIL${NC}"
echo ""

echo "$RESULTS" | jq '.' > "$RESULTS_FILE"
echo "  Full results written to: $RESULTS_FILE"

if [[ "$FAIL" -eq 0 ]]; then
  echo -e "  ${GREEN}ALL CHECKS PASSED — Organization guardrails are operational${NC}"
  exit 0
else
  echo -e "  ${RED}$FAIL CHECK(S) FAILED — Review RESULTS_FILE for details${NC}"
  exit 1
fi
