#!/usr/bin/env bash
# deploy.sh — Full deployment for AWS Multi-Account Organization Bootstrap
# Run this from the repo root after filling in terraform/starter.tfvars
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${YELLOW}→${NC} $1"; }
pass()  { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗ ERROR:${NC} $1"; exit 1; }

echo "═══════════════════════════════════════════════════"
echo "  AWS Multi-Account Organization Bootstrap"
echo "  Deployment Script — $(date -u)"
echo "═══════════════════════════════════════════════════"
echo ""

# ── Step 1: Prerequisites ───────────────────
info "Step 1/6: Checking prerequisites..."

terraform version | grep -q "Terraform v1\.[789]\|Terraform v[2-9]" || \
  error "Terraform 1.7+ required. Install from https://developer.hashicorp.com/terraform/install"
pass "Terraform version OK"

aws --version &>/dev/null || error "AWS CLI v2 not found"
pass "AWS CLI found"

jq --version &>/dev/null || error "jq not found. Install: brew install jq / apt-get install jq"
pass "jq found"

IDENTITY=$(aws sts get-caller-identity --output json)
ACCOUNT_ID=$(echo "$IDENTITY" | jq -r '.Account')
info "Deploying from account: $ACCOUNT_ID"

# Verify this is not already part of an org (as a member)
ORG_STATUS=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text 2>/dev/null || echo "NONE")
if [[ "$ORG_STATUS" != "NONE" && "$ORG_STATUS" != "$ACCOUNT_ID" ]]; then
  error "This account ($ACCOUNT_ID) is already a MEMBER of org managed by $ORG_STATUS. Run only from a management account."
fi
pass "Account is a valid management account"

# ── Step 2: Bootstrap backend ───────────────
info "Step 2/6: Creating Terraform backend (S3 + DynamoDB)..."

STATE_BUCKET="org-bootstrap-tfstate-${ACCOUNT_ID}-us-east-1"
echo "  State bucket: $STATE_BUCKET"

cd terraform/modules/bootstrap

cat > terraform.tfvars <<EOF
state_bucket_name = "$STATE_BUCKET"
lock_table_name   = "terraform-state-lock"
EOF

terraform init -reconfigure &>/dev/null
terraform apply -auto-approve -var-file=terraform.tfvars
pass "Backend created: s3://$STATE_BUCKET"

# Update the backend config in root main.tf
cd ../../..
sed -i.bak "s/REPLACE_WITH_STATE_BUCKET_NAME/$STATE_BUCKET/g" terraform/main.tf
pass "Backend config updated in terraform/main.tf"

# ── Step 3: Init with remote backend ────────
info "Step 3/6: Initializing Terraform with remote backend..."
terraform -chdir=terraform init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="region=us-east-1" \
  -reconfigure
pass "Terraform initialized with remote backend"

# ── Step 4: Plan ─────────────────────────────
info "Step 4/6: Running terraform plan..."
TFVARS_FILE="terraform/examples/tfvars/starter.tfvars"
if [[ ! -f "$TFVARS_FILE" ]]; then
  error "Please fill in $TFVARS_FILE before deploying. See the README for required values."
fi

terraform -chdir=terraform plan \
  -var-file="../examples/tfvars/starter.tfvars" \
  -out=tfplan 2>&1 | tee /tmp/tfplan-output.txt

RESOURCE_COUNT=$(grep -o "Plan: [0-9]* to add" /tmp/tfplan-output.txt | grep -o "[0-9]*" || echo "0")
echo ""
echo "  Plan: $RESOURCE_COUNT resources to add"
echo ""
read -r -p "  Continue with apply? (yes/no): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || error "Deployment cancelled by user"

# ── Step 5: Apply ─────────────────────────────
info "Step 5/6: Applying... (account creation takes 8-12 minutes)"
terraform -chdir=terraform apply tfplan
pass "Terraform apply complete"

# ── Step 6: Save outputs ─────────────────────
info "Step 6/6: Saving deployment outputs..."
terraform -chdir=terraform output -json > deployment-outputs.json
pass "Outputs saved to deployment-outputs.json"

echo ""
echo "═══════════════════════════════════════════════════"
echo -e "  ${GREEN}DEPLOYMENT COMPLETE${NC}"
echo ""
echo "  Next step: Run the proof-gate verification:"
echo "    chmod +x scripts/verify.sh && ./scripts/verify.sh"
echo "═══════════════════════════════════════════════════"
