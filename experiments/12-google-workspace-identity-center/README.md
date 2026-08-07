# 12 — Google Workspace → IAM Identity Center (personal org)

**Status:** handoff / not started. Investigation + experiment plan. No Terraform applied yet.

Two goals, in order:
1. **Answer a design question about alopa:** why does the estate use a per-account SAML
   federation (`saml_readonly` / `saml_ops` roles in every account) instead of one
   IAM Identity Center instance pointed at the corporate IdP?
2. **Build the alternative** in my personal AWS org (2 accounts, existing Google Workspace)
   so I can compare it hands-on and judge the tradeoff for myself.

---

## Part 1 — What alopa does today (grounded, so the comparison is fair)

Verified in `~/alopa/infra` on 2026-07-24:

- **No IAM Identity Center anywhere.** Zero `aws_ssoadmin_*` / `aws_identitystore_*`
  resources across the whole workspace.
- **Per-account SAML roles instead.** `common-infra/Common_modules/global-security/main.tf`
  defines exactly two federated roles — `saml_readonly` and `saml_ops` — whose trust policy is:
  ```hcl
  Principal = { Federated = "arn:aws:iam::${account_id}:saml-provider/${var.idp-name}" }
  Action    = "sts:AssumeRoleWithSAML"
  Condition = { StringEquals = { "SAML:aud" = "https://signin.aws.amazon.com/saml" } }
  ```
  `idp-name = "AmalgamRX"` (see `common-infra/Amalgam-master/main.tf:84`).
- **This module is instantiated in EVERY account** — every product repo's `Account/main.tf`
  calls `../../common-infra/Common_modules/global-security`. So the two roles are replicated
  into all ~29 accounts.
- **The SAML provider resource itself is NOT in Terraform.** The roles *reference*
  `saml-provider/AmalgamRX`, but there is no `aws_iam_saml_provider` resource anywhere in the
  code — the IdP metadata XML is uploaded **out-of-band / clickops, per account**. (Confirm how:
  a script in `tfscripts`? manual console upload? This is worth pinning down — it's the manual
  step Identity Center would eliminate.)

**So the current model is:** the IdP (whatever "AmalgamRX" points at) has one SAML app **per
account**, each account carries its own `saml-provider` registration + the fixed 2-role set, and a
user signs in at `signin.aws.amazon.com/saml` and picks an account+role. Adding an account means:
register the SAML provider in it, apply `global-security`, and add another SAML app on the IdP side.

### The AWS-prescribed answer (state this first, on its own)

For a multi-account org, AWS prescribes **one organization instance of IAM Identity Center** in the
management account, identity source = the corporate IdP (SAML + SCIM), **permission sets**
provisioned as IAM roles into each account, and **assignments** (user/group × permission set ×
account). One identity connection, one place to see/revoke access, roles that update in lockstep
when the permission set changes. (Lesson 05, §4; AWS SRA — Identity Management.)

### Why might alopa have gone the other way? (hypotheses to test, each labelled)

Don't assume it's a mistake — name the constraint and label it. Candidates:

| Hypothesis | Label to assign once tested |
|---|---|
| **Predates IdC / historical inertia.** The per-account SAML pattern was set up before IdC was mature (AWS SSO GA 2017, but org-instance + external-IdP ergonomics improved a lot since). Migrating 29 live accounts is real work with no user-facing win. | likely **defensible deviation** (migration cost) — but check |
| **Google Workspace SCIM limitation.** Google Workspace supports SCIM provisioning of **users only, not groups** (AWS SRA states this explicitly). If access is group-driven, IdC + Google loses group auto-provisioning — a genuine friction point. | **defensible deviation** IF true and if they're group-driven |
| **Per-account role customization.** `saml_ops` carries account-specific policies (Athena workgroup denies, SNS, SSH-into-ECS, OpsGenie). IdC permission sets *can* do customer-managed policies per account, but the current model bakes per-account nuance directly into the role. Is that nuance real or incidental? | **gap worth fixing** if incidental; **defensible** if genuinely per-account |
| **Region/DR concern.** IdC was single-Region until Feb 2026 (now multi-Region for external-IdP org instances). A pre-2026 "IdC is a single-Region SPOF for all console access" worry is now largely obsolete. | probably **stale rationale** now — worth retiring |
| **Break-glass simplicity.** Per-account SAML means no dependency on one IdC instance being up. But IdC + a SAML break-glass path gives the same resilience. | weak — **not a real blocker** |

**The question to actually answer:** is the per-account model a *defensible deviation* (name the
binding constraint — most likely migration cost + Google group-SCIM) or a *gap worth fixing* (it's
just inertia and the group problem has a workaround)? The experiment below is how I find out
without guessing.

---

## Part 2 — The experiment: Google Workspace → IdC in my personal org

**Environment:** personal AWS org, 2 accounts (management + 1 member), existing Google Workspace.

**Why this is mostly clickops, not Terraform:** enabling the IdC instance, connecting an external
SAML IdP, and the SCIM handshake are all console operations on *both* sides (AWS + Google Admin).
Terraform only owns the **permission sets and assignments** once the identity source is live. Plan
for that split — don't try to `terraform apply` the whole thing.

### Prerequisites
- [ ] Confirm the personal org has **all features** enabled (not billing-only) — IdC needs it.
- [ ] Management-account access (IdC instance must be enabled from there).
- [ ] Google Workspace **super admin** access (to add the SAML app + turn on autoprovisioning).
- [ ] Pick a home Region for IdC and note it.

### Part A — Google Workspace side (Google Admin console)
- [ ] Admin console → **Apps → Web and mobile apps → Add app**. Search for the pre-integrated
      **"AWS IAM Identity Center"** app if present; otherwise **Add custom SAML app**.
- [ ] Download **Google's IdP metadata** (SSO URL, Entity ID, X.509 cert) — you'll hand this to AWS.
- [ ] Leave attribute mapping for after you have AWS's ACS URL (Part B produces it).

### Part B — AWS IAM Identity Center side (management account console)
- [ ] **Enable** IAM Identity Center (organization instance) in the chosen Region.
- [ ] **Settings → Identity source → Change to External identity provider.**
- [ ] Upload **Google's metadata** (from Part A). Download **IdC's SAML metadata** (ACS URL, issuer).
- [ ] Go back to the Google SAML app and paste in IdC's ACS URL + entity ID; finish attribute mapping
      (NameID = primary email is the usual baseline).
- [ ] **Enable automatic provisioning (SCIM):** IdC issues a **SCIM endpoint + bearer token**.
      Configure autoprovisioning for the app on the Google side with those values.
      ⚠️ **Google Workspace provisions USERS only via SCIM, not groups** — so expect to create any
      **groups inside IdC** (or via the SDK/Terraform `aws_identitystore_group`) and manage
      membership there, since Google won't push group objects. **This is the crux of hypothesis #2 —
      confirm it bites, and how much.**
- [ ] Register a **delegated administrator** member account if you want to mimic the prescribed
      Security-Tooling split (optional at 2 accounts, but good practice to try).

### Part C — What to put in Terraform (this folder)
Once the identity source is live and users are syncing, author here:
- [ ] `aws_ssoadmin_permission_set` — e.g. a `ReadOnly` and an `Admin` set (mirror `saml_readonly`
      / `saml_ops` so the comparison is apples-to-apples). Set `session_duration`.
- [ ] `aws_ssoadmin_managed_policy_attachment` (and/or customer-managed / inline) per set.
- [ ] `aws_ssoadmin_account_assignment` — **one per (principal × permission set × account)**.
      With 2 accounts this makes the "no OU target, N accounts = N assignments" constraint concrete —
      note how it'd feel at 29.
- [ ] Data sources: `aws_ssoadmin_instances` for the instance ARN,
      `aws_identitystore_user` / `_group` to resolve the synced principals by name.

Standard play conventions (see `play/README.md`): own state key
`terraform/play/12-google-workspace-identity-center.tfstate`, apply with
`AWS_PROFILE=<personal>`, **destroy when done poking**. Note: destroying the Terraform removes the
permission sets/assignments cleanly, but **disabling the IdC instance + the Google app is manual** —
add a teardown checklist below when you get there.

### Success criteria
- [ ] A Google Workspace user (me) signs into the **AWS access portal**, sees both accounts, and can
      open each with the right permission set — **no per-account SAML app, no `saml-provider` upload**.
- [ ] Changing a permission set's policy updates the provisioned role in **both** accounts with no
      per-account edit — the property the alopa model lacks.
- [ ] I can articulate, from the console experience, exactly how many manual steps IdC removes vs the
      per-account SAML model, and where Google's group-SCIM gap forces a workaround.

---

## Part 3 — Open questions to resolve (write the verdict here when done)

1. **How is alopa's `saml-provider/AmalgamRX` actually created per account?** (script vs manual)
   — this is the toil IdC eliminates; quantify it. Check `tfscripts/` and any account-vending script.
2. **Is alopa's IdP already Google Workspace, or Okta/other?** `idp-name = "AmalgamRX"` is opaque.
   If it's *already* Google, the migration to IdC is much shorter (same source of truth).
3. **Does the Google group-SCIM limitation actually block alopa's access model?** i.e. is their
   access group-driven or role-name-driven? If role-name-driven, the limitation is moot.
4. **Are the per-account `saml_ops` policy nuances genuinely per-account, or copy-paste?** If the
   latter, they collapse into a handful of IdC permission sets cleanly — evidence for "gap worth
   fixing" over "defensible deviation."
5. **Final label:** per-account SAML = _defensible deviation_ (name the constraint) or _gap worth
   fixing_? Decide only after the experiment, not before.

---

## Notes / links
- This doubles as the **hands-on IdM material that lesson 05 (study repo) delivered but didn't test**
  — permission-set → role provisioning and the "assignments target accounts, not OUs" constraint were
  chapter-only. Doing this closes that gap. (See the study repo's SERVICE_RADAR entry for IAM Identity
  Center, held at 📖 pending exactly this.)
- AWS SRA — Identity Management (the prescribed shape):
  https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture-identity-management/
- IdC org vs account instances:
  https://docs.aws.amazon.com/singlesignon/latest/userguide/identity-center-instances.html
- Google Workspace SCIM = users only (the group gotcha) — stated in the SRA "Connecting your existing
  identity source" section.
- alopa reference: `common-infra/Common_modules/global-security/main.tf` (lines ~169–210 for the two
  SAML roles), called from every `*/Account/main.tf`.
