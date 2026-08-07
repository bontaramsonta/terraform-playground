# Access levers: managing AWS role × account from Google Workspace

Correction-of-record research, 2026. Every claim below is sourced to an AWS official
doc, Google Workspace Admin Help, or the `awslabs/ssosync` repo. Sources are inline.

**Decision context:** AWS IAM Identity Center (org instance, us-east-1). Google Workspace
tenant `discreate.app` is the external SAML IdP. We are taking the **AWS-canonical route**:
use Google's pre-integrated catalog app **"Amazon Web Services"** for both IdC SAML SSO
and SCIM auto-provisioning, and retire the hand-built custom SAML app. An identity-store
user `souravdhar@discreate.app` was already manually created in IdC to make SAML sign-in
work; SCIM must **adopt** it, not collide.

Primary sources:
- AWS tutorial "Configure SAML and SCIM with Google Workspace and IAM Identity Center":
  https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html
- AWS "Attributes for access control": https://docs.aws.amazon.com/singlesignon/latest/userguide/attributesforaccesscontrol.html
- AWS "Attribute-based access control": https://docs.aws.amazon.com/singlesignon/latest/userguide/abac.html
- Google Workspace Admin Help "Configure Amazon Web Services user provisioning":
  https://support.google.com/a/answer/13047358 (now served at
  https://knowledge.workspace.google.com/admin/users/advanced/configure-amazon-web-services-user-provisioning)
- Google Workspace Admin Help "Amazon Web Services cloud application": https://support.google.com/a/answer/6194963
- `awslabs/ssosync`: https://github.com/awslabs/ssosync
- Identity Store CLI `create-group`: https://awscli.amazonaws.com/v2/documentation/api/latest/reference/identitystore/create-group.html

---

## 1. Canonical setup (Path B) — exact ordered steps

From gs-gwp.html. Do these in order; the ACS/EntityID only exist after you start the AWS side.

**Step 1 — Google: add the catalog SAML app.**
Google Admin console (super admin) → **Apps → Web and Mobile Apps** → **Add app → Search
for apps** → enter **"Amazon Web Services"** → select the **"Amazon Web Services (SAML)"**
app. On the **Google Identity Provider details** page, either *Download IdP metadata* or copy
the **SSO URL, Entity ID URL, and Certificate**. Leave the page open.
(gs-gwp.html, Step 1.)

**Step 2 — AWS: switch identity source + exchange metadata.**
IdC console → **Settings → Actions → Change identity source** → **External identity
provider → Next**. On **Configure external identity provider**, upload the Google SAML
metadata (or paste Google SSO URL → *IdP Sign-in URL*, Google Issuer URL → *IdP issuer URL*,
upload Google cert). Then **copy the IAM Identity Center ACS URL and the IAM Identity Center
issuer URL** — you paste these back into Google. (gs-gwp.html, Step 2, items 5–6.)

Back in Google on **Amazon Web Services – Service Provider details**:
- Paste IdC **ACS URL** → **ACS URL** field.
- Paste IdC **issuer URL** → **Entity ID** field.
- **Name ID format = EMAIL**; **Name ID = Basic Information > Primary email**. (gs-gwp.html, Step 2, "Name ID".)

Return to IdC → **Next → Review and Confirm** → type **ACCEPT** → **Change identity source**.

> **Legacy Role / RoleSessionName attribute template — remove/ignore for IdC.**
> The gs-gwp tutorial's Step 2 attribute-mapping sub-step tells you to map
> `https://aws.amazon.com/SAML/Attributes/RoleSessionName` and
> `https://aws.amazon.com/SAML/Attributes/Role`. **Those two attributes belong to the
> *legacy IAM SAML federation* flow** (`sts:AssumeRoleWithSAML` into per-account IAM roles —
> exactly the alopa `saml_readonly`/`saml_ops` model). **IAM Identity Center does not consume
> them.** In the IdC canonical flow, role×account selection is done by IdC *account
> assignments* (see §3), not by a `Role` SAML attribute. Mapping them is harmless but inert
> for IdC; you can leave them blank/unmapped. The only SAML attribute IdC actually cares about
> is the **NameID = Primary email** (the subject that must equal the SCIM `userName`), plus —
> optionally — the ABAC `AccessControl:{TagKey}` attributes (§3). Do **not** carry a real
> `Role` value expecting it to grant access under IdC; it won't.

**Step 3 — Google: turn the app ON.**
Google Admin → the AWS app → **User access** → **Service status → ON for everyone → Save**
(or ON for a specific OU/group). The auto-provisioning slider is disabled until the app is ON
for users. (gs-gwp.html, Step 3.)

**Step 4 — AWS: enable SCIM, capture endpoint + token.**
IdC console → **Settings → Automatic provisioning → Enable**. IdC displays the **SCIM
endpoint** (`https://scim.{Region}.amazonaws.com/{tenant-id}/scim/v2`) and a one-time
**access token** (**Show token**). *"This is the only time where you can obtain the SCIM
endpoint and access token."* Copy both. (gs-gwp.html, Step 4.)

**Step 5 — Google: configure auto-provisioning (SCIM).**
Google Admin → AWS app → **Auto provisioning → Configure auto provisioning** → paste the
**Access token**, then the **Endpoint URL** (SCIM endpoint). Verify all mandatory (`*`) IdC
attributes are mapped to Google directory attributes — this is where **Primary email → userName**
is confirmed (the mandatory `userName` maps to Google Primary email, matching the NameID). Set
**Provisioning scope** (optional: limit to a Google group) → set **Deprovisioning** timers →
**Finish** → flip the **Auto-provisioning** toggle **Inactive → Active → Turn on**.
(gs-gwp.html, Step 5; Google "Configure Amazon Web Services user provisioning".)

**Adopting the existing manual user (no collision).**
gs-gwp.html Considerations state, verbatim: *"If there is an existing user in Identity Center
directory with the same username and email, the user will be overwritten and synchronized
using SCIM from Google Workspace."* Because the manual IdC user was created with
`username == email == souravdhar@discreate.app`, SCIM will **match and take over** that record
rather than create a duplicate. Keep the manual user's `userName` exactly equal to the Google
Primary email; do not change it before the first sync. (This is the documented adopt path;
mismatched usernames are what produce the "duplicate user/group" error the troubleshooting
section covers.)

**Delete the custom SAML app — after, not before.**
There is **only one identity source at a time**. Switching to the catalog app *is* the cutover.
Sequence to avoid stranding the user:
1. Complete Steps 1–5 with the catalog app and confirm SCIM adopted `souravdhar@discreate.app`
   and that you can sign in through the catalog app.
2. **Only then** delete/disable the hand-built custom SAML app in Google.
Risk if you delete the custom app *first*: you lose the working SAML sign-in before the catalog
app is verified. The identity-store user object itself is not deleted by removing a SAML app
(SAML governs sign-in, SCIM governs the user record), but you would be locked out of the portal
until the new app works — so verify first, delete second.

---

## 2. Groups — does Google's native SCIM push them? (No.)

**Authoritative answer: Google Workspace SCIM provisions USERS ONLY, not groups or group
memberships.** Two verbatim sources:

- gs-gwp.html Considerations: *"SCIM automatic synchronization from Google Workspace is
  currently limited to user provisioning. Automatic group provisioning is not supported at this
  time. Groups can be manually created with AWS CLI Identity Store create-group command or AWS
  Identity and Access Management (IAM) API CreateGroup. Alternatively, you can use ssosync to
  synchronize Google Workspace users and groups into IAM Identity Center."*
- gs-gwp.html "Assign access" Note: *"SCIM automatic synchronization from Google Workspace only
  supports provisioning users. Automatic group provisioning is not supported at this time. You
  cannot create groups for your Google Workspace users using the AWS Management Console."*
- Google's own doc confirms the connector's object scope is users:
  *"Automated user provisioning operates only on active, suspended, or deleted users."* Its
  **Provisioning scope** feature lets you *limit provisioning to specific Google groups* — but
  that only selects **which users** sync; **the group objects are not created in IdC**.
  (https://knowledge.workspace.google.com/admin/users/advanced/configure-amazon-web-services-user-provisioning)

So group-based permission-set assignments require populating IdC groups **by some other
mechanism**. The three supported ways:

### 2a. AWS `ssosync` Lambda (awslabs/ssosync)

- **What it syncs:** **users, groups, AND group memberships**, Google → IdC, uni-directional.
  Nested groups are flattened into top-level groups; external users are ignored; group owners
  are treated as regular members. (https://github.com/awslabs/ssosync README.)
- **Auth to Google:** a **service account with domain-wide delegation**, plus a Workspace
  **admin email** to impersonate, using the **Admin SDK Directory API**. Exact read-only scopes:
  - `https://www.googleapis.com/auth/admin.directory.group.readonly`
  - `https://www.googleapis.com/auth/admin.directory.group.member.readonly`
  - `https://www.googleapis.com/auth/admin.directory.user.readonly`
- **Auth to IdC:** the IdC **SCIM endpoint URL + access token** for provisioning, plus the
  **Identity Store API** (IAM creds) for auto-detecting the Identity Store ID / Region
  (`ListInstances`; Region parsed from the SCIM endpoint URL).
- **Deployment:** **AWS Serverless Application Repository** (one-click, ~5-min, recommended),
  **AWS SAM** (`sam build` / `sam deploy --guided`), or the **CLI binary** for local/CI. v2.1.0+
  runs on `provided.al2` / ARM64 and IaC deploys need `CAPABILITY_NAMED_IAM`.
- **Scheduling:** as a Lambda it runs on a **CloudWatch Events / EventBridge schedule**,
  `ScheduleExpression` (default `rate(15 minutes)`).
- **Caveats (verbatim / near-verbatim from README):**
  - *"Groups do not get deleted in AWS SSO when deleted in the Google Directory."*
  - **Must be deployed in the IAM Identity Center delegated-administration account** (CLI needs
    creds from that account).
  - **Control Tower danger:** *"ssosync will make the IAM Identity Store match the subset …
    including removing … groups and users created by AWS Control Tower."* It will delete
    Control-Tower-managed principals to make IdC match Google. (Not a concern for this 2-account
    personal org with no Control Tower, but note it.)
  - Uni-directional only (Google is source of truth).
  - Open feature request (#179) to *ignore* manually-created IdC users/groups — meaning today
    ssosync assumes it owns the identity store.
- **Trade-off:** highest automation (Google groups become the single control plane for
  role×account), but real operational surface: a service account with domain-wide delegation, a
  Lambda in the delegated-admin account, and a tool that will prune IdC to match Google.

### 2b. Manual IdC groups (console)

Create groups directly in the IdC console (Identity Center directory) and add the
SCIM-provisioned users to them by hand, then assign groups to permission sets per account.
gs-gwp.html is explicit you **cannot** create groups for Google-sourced users *via the console
group-create-for-external* path historically — but standard IdC group management in the console
is the documented fallback the "Next steps" section points to (create groups, assign access to
groups so membership changes grant/revoke access dynamically).
**Trade-off:** simplest, zero extra infrastructure, no Google credentials — but membership is
maintained in two places (Google for identity, IdC for group membership); it does not
auto-track Google group changes.

### 2c. Identity Store API / CLI (scripted)

gs-gwp.html directs you to the **AWS CLI Identity Store `create-group`** and
`create-group-membership` (and IAM API `CreateGroup`) to script group + membership management.
Terraform equivalents: `aws_identitystore_group` / `aws_identitystore_group_membership`.
**Trade-off:** scriptable/reproducible (fits this repo's Terraform-owns-assignments model) and
no domain-wide-delegation footprint, but you author membership yourself — it does not read
Google. Good middle ground between 2a and 2b.

### Coexistence: does ssosync conflict with Google's user SCIM?

**They conflict — do not run both against the same identity store.** Both are *writers* to the
same IdC identity store over the same SCIM tenant. ssosync's design "make IdC match Google"
(and the open #179 that it does **not** yet ignore externally/otherwise-created objects) means
it treats the store as its own. If Google's native connector also provisions the same users,
you get two systems asserting authority over user records. **Pick one owner:**
- Either **ssosync owns users AND groups** (disable Google's native auto-provisioning; keep only
  Google SAML SSO), **or**
- **Google native SCIM owns users**, and you own **groups** via **2b (console)** or **2c
  (CLI/Terraform)** — the two don't overlap because Google never writes group objects. This is
  the clean split and the one that matches "adopt the existing user via Google SCIM, add groups
  yourself."
ssosync-owns-users + Google-SCIM-owns-users is **not** a valid split — same object type, two
owners.

---

## 3. Attributes / ABAC — correcting the mental model

The user's framing — *"manage a user's AWS role and which accounts they access by updating
their attributes"* — conflates two different mechanisms. Attributes do **not** grant
account/role access. Assignments do.

**What decides WHICH permission set on WHICH account a principal gets: account assignments.**
An **account assignment** = (principal: user *or* group) × (permission set) × (AWS account).
IdC provisions the permission set as an IAM role into that account and lets the principal assume
it. Nothing about a user's *attributes* creates or removes an assignment. gs-gwp.html's "Assign
access to AWS accounts" workflow is exactly this: pick account → **Assign users or groups** →
pick permission set. (Terraform: `aws_ssoadmin_account_assignment`, one per
principal×permission-set×account.)

**What "Attributes for access control" (ABAC) actually does.** From
attributesforaccesscontrol.html: *"IAM Identity Center passes the user's department attribute to
the account being accessed … When IAM Identity Center passes these attributes to the account,
they are sent as **session tags** that you can reference using the `aws:PrincipalTag/{tag-key}`
condition key in all relevant AWS IAM policy types."* So ABAC injects the user's attributes as
`aws:PrincipalTag/*` session tags into the assumed session, and your **permission-set policies**
(inline/managed) can `Condition` on them. **ABAC gates permissions *within* an account the user
is already assigned to — it does not itself grant the assignment.** (Details: abac.html.)

**How attributes get INTO IdC for ABAC** (external-IdP case, from attributesforaccesscontrol.html):
1. **Via SCIM-provisioned attributes** — *"If using SCIM, the IdP automatically synchronizes the
   attribute values into IAM Identity Center. You can then select these synchronized attributes
   on the Attributes for access control page to use them as session tags."* Map a Google field
   (e.g. Department) through the SCIM attribute mapping, then select it on the **Attributes for
   access control** page.
2. **Via SAML assertion attributes** — configure Google to send
   `https://aws.amazon.com/SAML/Attributes/AccessControl:{TagKey}`; *"IAM Identity Center passes
   the attribute name and value from the IdP through for policy evaluation."* gs-gwp.html's
   optional "Passing attributes for access control" section shows the exact
   `AttributeStatement` (e.g. `CostCenter = blue`). If both are configured for the same key, the
   **Identity Center directory value (option 1) takes precedence** over the SAML value.
   Google fields available: any Google Directory attribute you can map — Primary email,
   Department, Cost center, Employee title, plus custom attributes (custom schema).

**Can ABAC restrict/permit account-level access?** Only *within an assigned account*, as a
guardrail — not as the access grant. Pattern: assign a broad permission set to a group, then put
a `Condition: {StringEquals: {"aws:PrincipalTag/Department": "..."}}` (or a `Deny` unless the tag
matches) in the permission-set policy so the effective permissions vary by the user's attribute.
**Limit:** the user must **already have the assignment** for that account+permission set; ABAC
can only narrow what an assigned session can do. It cannot make an unassigned account appear in
the portal, and it cannot substitute for an assignment. A missing tag → the `Condition` fails →
the user has the role but no effective permissions (a confusing "assigned but can't do anything"
state), which is why ABAC is a *refinement* layer, not the account-selection layer.

---

## 4. Synthesis — practical patterns to manage role × account from Google

Each pattern: **{Google admin action} → {what happens in IdC} → {result on AWS access}.**

**Pattern A — Google GROUP membership drives assignments (via ssosync).**
- Google admin adds/removes a user in a **Google group** (e.g. `aws-readonly@`, `aws-ops@`).
- ssosync (scheduled Lambda) syncs the group + membership into IdC; the IdC **group** is
  pre-assigned (via console/Terraform, once) to permission sets per account:
  `aws-readonly` group → **ReadOnly** permission set on {mgmt, member}; `aws-ops` group →
  **Ops** permission set on {mgmt, member}.
- Result: changing a user's Google group membership **adds/removes their role×account access**
  on the next sync. Google group = the single lever. This reproduces the goal model
  (ReadOnly + Ops, group-driven, two accounts) with full automation.
- Cost: ssosync infra (service account + domain-wide delegation + delegated-admin Lambda) and
  ssosync owning the identity store (turn **off** Google native user SCIM to avoid the §2
  conflict).

**Pattern B — ABAC: a Google attribute drives permissions within permission sets.**
- Google admin sets a user attribute (e.g. **Department = analytics**, or a custom attribute).
- The attribute reaches IdC via SCIM mapping (or SAML `AccessControl:{TagKey}`) and is emitted
  as `aws:PrincipalTag/Department` in the session.
- Result: within accounts the user is **already assigned to**, permission-set policy
  `Condition`s on `aws:PrincipalTag/Department` widen/narrow effective permissions. Changing the
  Google attribute changes *what they can do*, not *which accounts/roles appear*. Complements A;
  does not replace it.

**Pattern C — per-user direct assignment in IdC (not Google-driven).**
- Admin assigns the **user** (not a group) to a permission set on an account, in the IdC console
  or Terraform (`aws_ssoadmin_account_assignment` with the user principal).
- Google's only role is providing the identity (SAML sign-in + SCIM user record).
- Result: access is managed entirely in AWS; Google changes don't move access. Contrast case —
  simplest for a tiny org, but no Google-side control plane.

### Recommendation for the stated goal (ReadOnly + Ops, group-driven, two accounts, 1-user learning org)

**Use Pattern C's assignment mechanism with manual/CLI groups (2b or 2c) — skip ssosync for now.**
Rationale: ssosync (Pattern A) is the right answer at scale, but for a **1-user learning org**
its cost (service-account domain-wide delegation, a delegated-admin Lambda, and a tool that
prunes IdC to match Google, per §2a) is disproportionate and adds a real footgun. Instead:
1. Let **Google native SCIM own the user** (adopts `souravdhar@discreate.app` per §1).
2. Create two **IdC groups** — `ReadOnly`, `Ops` — via **CLI/Terraform** (`aws_identitystore_group`
   + `_group_membership`, i.e. §2c) so it lives in this repo alongside the permission sets.
3. Author two **permission sets** (ReadOnly, Ops) and **4 assignments** (2 groups × 2 accounts)
   via `aws_ssoadmin_account_assignment`.
4. Add yourself to both groups (or just Ops) to exercise role×account selection in the portal.
This reproduces the alopa `saml_readonly`/`saml_ops` shape as **group-driven IdC assignments**,
proves the "one permission set → role provisioned into N accounts" property, and keeps the whole
thing in Terraform — **without** standing up ssosync. Revisit **Pattern A (ssosync)** only if/when
the org grows enough that hand-maintaining IdC group membership becomes the toil. Layer
**Pattern B (ABAC)** on top only if you want to demo attribute-gated permissions — it is
orthogonal and not needed to hit the stated goal.
