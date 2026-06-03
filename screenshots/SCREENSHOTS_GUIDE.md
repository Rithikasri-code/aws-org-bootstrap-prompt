# Screenshots Guide
# Take these 5 screenshots after running deploy.sh + verify.sh
# Upload all of them to the BUIDL media section on DoraHacks

---

## Screenshot 1: AWS Organizations Structure
**Where:** AWS Console → AWS Organizations → AWS accounts
**What to show:**
- The root level with 4 OUs visible: Security, Logging, Infrastructure, Workloads
- Each OU expanded to show its member account
- All 5 accounts with status: ACTIVE
**Filename:** `01-organizations-structure.png`

---

## Screenshot 2: CloudTrail Organization Trail Active
**Where:** AWS Console → CloudTrail → Trails
**What to show:**
- Trail named "org-trail" with status: Logging ✓
- Multi-region: Yes
- Organization trail: Yes
- Log file validation: Enabled
- S3 bucket name visible
**Filename:** `02-cloudtrail-active.png`

---

## Screenshot 3: GuardDuty Delegated Admin + All Accounts
**Where:** AWS Console → GuardDuty (in Security account) → Settings → Delegated administrator
**What to show:**
- Security account listed as Delegated administrator
- Member accounts tab showing all 4 member accounts with Status: Enabled
**Filename:** `03-guardduty-delegated-admin.png`

---

## Screenshot 4: Config Organization Aggregator + Compliance
**Where:** AWS Console → AWS Config → Aggregators → org-aggregator
**What to show:**
- Aggregator name: org-aggregator
- Source accounts: All accounts in organization
- Compliance summary showing rules evaluated across accounts
- At least GUARDDUTY_ENABLED_CENTRALIZED showing COMPLIANT
**Filename:** `04-config-aggregator-compliant.png`

---

## Screenshot 5: verify.sh Output — All Tests Passing
**Where:** Your terminal after running ./scripts/verify.sh
**What to show:**
- All PG-01 through PG-05 pre-stimulus checks: ✓ PASS
- All NT-01 through NT-08 negative tests: ✓ PASS (AccessDenied returned)
- DT-01 through DT-03 detection tests: ✓ PASS
- Final summary line: "ALL CHECKS PASSED — Organization guardrails are operational"
**Filename:** `05-verify-all-passing.png`
**Tip:** Use `./scripts/verify.sh 2>&1 | tee verify-output.txt` to capture it

---

## Bonus Screenshot (optional but impressive)
**Where:** AWS Console → CloudTrail → Event history
**What to show:**
- A StopLogging event captured in CloudTrail (from NT-02 negative test)
- Shows the denied API call was recorded — proves audit trail caught the attack
**Filename:** `06-cloudtrail-captured-denial.png`

---

## ARCHITECTURE.svg
The file `screenshots/ARCHITECTURE.svg` is the architecture diagram.
Upload it to the BUIDL page as the first media item — it appears on the grid card
and is the first thing judges see when they click on your submission.

To convert to PNG for upload (if SVG not accepted):
```bash
# macOS
rsvg-convert -w 1360 -h 1440 screenshots/ARCHITECTURE.svg > screenshots/ARCHITECTURE.png

# Or open ARCHITECTURE.svg in any browser and take a screenshot
```
