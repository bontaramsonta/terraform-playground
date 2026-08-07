# IAM Identity Center — Common Operations (personal org)

Practical, click-by-click runbook for the day-to-day tasks on the personal-org IdC setup.
This is the **landed** setup (see [issue #1](https://github.com/bontaramsonta/terraform-playground/issues/1)):
a single Google identity signing in via a custom SAML app, with access managed **directly in
IdC**. No SCIM, no Google-driven groups.

## Fixed facts

| Thing | Value |
|---|---|
| IdC region | `us-east-1` (instance `bontaramsonta`) |
| Access portal | https://bontaramsonta.awsapps.com/start |
| Mgmt (root) account | `bontaramsonta` — `275221839257` |
| Member account | `machine_learning` — `536697267595` |
| Identity source | External SAML IdP = Google Workspace (`discreate.app`), custom SAML app |
| Primary user | `souravdhar@discreate.app` |

### Signing in to run these operations

Almost everything below lives in the **IAM Identity Center** console in `us-east-1`, which needs
admin on the **management account**. Two ways in:

- **Portal (normal):** sign in at the access portal as `souravdhar@discreate.app` → open the
  `bontaramsonta` account with **AdministratorAccess** → console.
- **Break-glass (if SSO sign-in is broken):** sign in as the **root user** of `275221839257`
  (`bontaramsonta@gmail.com` + MFA). Use this whenever a change might lock you out of SSO.

> **Golden rule:** *which account × which role* a principal gets is always an **assignment made
> here in IdC** — never in Google. Google only supplies the identity. Keep that in mind reading
> the operations below.

---

## 1. Add a new account to the organization

Creates a brand-new AWS account inside the org. (To pull in an *existing* external account, use
**invite** instead of create — noted at the end.)

1. Console → **AWS Organizations** (from the mgmt account) → **AWS accounts** → **Add an account**.
2. **Create an account** → give it a **name** (e.g. `data_platform`) and a **unique email**
   (root email — must not already be a root email anywhere; a `+alias` on your domain works).
3. Leave the default **OrganizationAccountAccessRole** (this is the role Organizations creates so
   the mgmt account can administer the new account).
4. Create. Provisioning takes ~1–2 min; the account appears with a new **12-digit account ID**.

**Then make it usable in IdC** — a fresh account has *no* IdC assignments yet, so no one can sign
into it via the portal until you assign someone (see §2 / §4).

> **Invite an existing account instead:** Organizations → Add an account → **Invite an existing
> account** → enter its account ID/email → accept the invite from that account's root user.

---

## 2. Give an existing user access to one account with an existing permission set

The core operation — "assign a user to an account with a role." Use this to grant, e.g.,
`souravdhar@discreate.app` **AdministratorAccess** (or any existing permission set) on one account.

1. IdC → **AWS accounts** → tick the **one account** you want (e.g. `machine_learning`).
2. **Assign users or groups**.
3. **Users** tab → select `souravdhar@discreate.app` → **Next**.
   *(Prefer a **group** here if several people should share the access — assign the group once and
   manage membership instead of re-assigning per person. For one user, the user tab is fine.)*
4. Select the **permission set(s)** to grant on this account (e.g. `AdministratorAccess`,
   `S3Downloader`) → **Next** → **Submit**.
5. IdC provisions the corresponding IAM role into that account (a few seconds).

**Result:** next time the user opens the portal, that account tile appears with the granted
role(s) selectable.

> To grant on **multiple** accounts, repeat per account, or select several accounts at step 1 and
> assign the same principal+permission-set to all of them at once.

---

## 3. Create a new permission set (a scoped, login-selectable role)

A permission set is what shows up as a **role in the portal**. IdC provisions it as an IAM role
(`AWSReservedSSO_<name>_<hash>`) into each account it's assigned to.

**Predefined (managed policy):**
1. IdC → **Permission sets** → **Create permission set** → **Predefined permission set**.
2. Pick an AWS managed policy (e.g. `AdministratorAccess`, `ReadOnlyAccess`, `PowerUserAccess`)
   → **Next**.
3. Name it (keep it = the policy name for clarity), set **session duration** (1h default; the old
   admin set used 2h) → **Create**.

**Custom (scoped to a task) — e.g. "download files from one S3 bucket":**
1. IdC → **Permission sets** → **Create permission set** → **Custom permission set** → **Next**.
2. **Inline policy** → paste a tight policy, e.g.:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": ["s3:GetObject", "s3:ListBucket"],
       "Resource": [
         "arn:aws:s3:::my-bucket",
         "arn:aws:s3:::my-bucket/*"
       ]
     }]
   }
   ```
   (For Lambda: `"lambda:InvokeFunction"` on a specific function ARN, etc.)
3. Name it (e.g. `S3Downloader`), set a short **session duration** → **Create**.

A new permission set exists but grants nothing until you **assign** it to a user/group on an
account (§2). Once assigned, it appears as a selectable role in the portal, and as a CLI profile
(`sso_role_name = S3Downloader`) — so a script run under `--profile s3dl` is confined to exactly
that scope. Editing a permission set's policy auto-re-provisions it wherever it's assigned.

---

## 4. Give an existing user access to a single account (end-to-end)

The everyday grant, combining the pieces. Goal: `<user>` should be able to do `<task>` on
**one** account.

1. **Pick or make the role.** Is there an existing permission set with the right scope?
   - Yes → skip to step 2.
   - No → create one (§3) — predefined for broad access, custom for a scoped task.
2. **Assign it on that one account** (§2): IdC → **AWS accounts** → select the account →
   **Assign users or groups** → the user → the permission set → **Submit**.
3. **Verify:** user opens https://bontaramsonta.awsapps.com/start → the account tile shows the
   role → click to open the console, or use it from the CLI:
   ```ini
   # ~/.aws/config
   [sso-session bontaramsonta]
   sso_start_url = https://bontaramsonta.awsapps.com/start
   sso_region = us-east-1
   sso_registration_scopes = sso:account:access

   [profile myrole]
   sso_session = bontaramsonta
   sso_account_id = 536697267595      # the one account
   sso_role_name = ReadOnlyAccess     # the permission set name
   region = us-east-1
   ```
   ```bash
   aws sso login --sso-session bontaramsonta
   aws sts get-caller-identity --profile myrole
   ```

**To revoke:** IdC → AWS accounts → the account → find the assignment → **Remove access**. IdC
de-provisions the role from that account.

---

## Notes / gotchas

- **Assignment ≠ identity.** Creating/removing an *IdC assignment* changes AWS access. Removing a
  *user* from Google (or IdC) removes their identity entirely. Different levers.
- **Groups need manual management here.** Google Workspace groups do **not** sync into IdC (SCIM
  is users-only, and the custom SAML app can't do SCIM at all). If you want group-based access,
  create the group **in IdC** (console, or `aws identitystore create-group` /
  `create-group-membership`) and manage membership there.
- **Attributes can't grant access.** Google attributes (via SAML ABAC) can only refine permissions
  *within* an account a principal is already assigned to — they never create the assignment.
- **New account = no access by default.** After §1, nobody can enter the account via SSO until you
  do §2/§4.
