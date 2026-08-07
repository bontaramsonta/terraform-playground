# Research — Identity-source-switch mechanics & Google SCIM constraints

Resolves GitHub issue [#2](https://github.com/bontaramsonta/terraform-playground/issues/2).
Primary sources only (AWS IAM Identity Center user guide, Google Workspace admin help). Every claim is cited.
Date: 2026-07-24.

---

## TL;DR

- Switching an **organization instance** from the built-in **Identity Center directory** to an **external SAML IdP** is **less destructive than assumed**. AWS's primary docs say it **preserves** the identity-store users/groups **and** the assignments/memberships — provided the new IdP's SAML `NameID` matches the *existing* IdC usernames/group names. What it *does* remove is the **permission-set IAM roles** provisioned into member accounts (re-created on next assignment sync). The **instance ARN, identity store ID, and access-portal URL survive** (only *Active Directory* transitions change the identity store ID / portal URL).
- **Practical catch for this org:** the native user is `sourav_dhar_47` (a username, not an email). Google sends `NameID = primary email`. Those **won't match**, so the pre-existing user is effectively stranded and SCIM provisions a **fresh** user. So in practice you rebuild users/assignments even though AWS doesn't technically "delete" them.
- **Google SCIM provisions users only, not groups** — confirmed by AWS's own tutorial. After enabling SCIM, groups must be made via CLI/API (`identitystore create-group`) or `ssosync`.
- **Editions:** *all* Google Workspace editions include the AWS auto-provisioning feature. Business Starter / Frontline Starter cap at **3** provisioning apps; Business Standard, Business Plus, Frontline Standard/Plus, and Enterprise allow **100**.
- **Ordering:** **SAML/SSO first, SCIM second.** Google's auto-provisioning activation slider is disabled until the AWS SSO app is turned on for users; AWS's tutorial sequences SAML (Steps 1–3) before enabling SCIM (Steps 4–5).

---

## 1. Identity-source switch: deleted vs preserved (IdC directory → external SAML IdP)

### The warning AWS shows on the change screen (verbatim)

From **Change your identity source** ([docs](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-change.html)):

> **Warning**
> Depending on your current deployment, this change removes any user and group assignments that you configured in IAM Identity Center. This change will also remove permission set IAM roles from your AWS accounts. As a result, you may need to update your resource policies, and should ensure this will not disrupt your access to AWS KMS keys and Amazon EKS clusters. […]
> When this occurs, all users and groups, including the administrative user in IAM Identity Center, will lose single sign-on access to their AWS accounts and applications.

Note the qualifier **"Depending on your current deployment"** — the deployment-specific behavior is spelled out in **Considerations for changing your identity source** ([docs](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-considerations.html)), which distinguishes the transition types.

### What the considerations page says for **IdC directory → external IdP** (verbatim)

> **Changing from IAM Identity Center to an external IdP**
> - **Assignments and memberships work with correct assertions** – your user assignments, group assignments, and group memberships continue to work as long as the new IdP sends the correct assertions (for example, SAML nameIDs). These assertions must match the user names and groups in IAM Identity Center.
> - **No outbound synchronization** – IAM Identity Center doesn't support outbound synchronization […]
> - **SCIM provisioning** – if you are using SCIM provisioning, changes to users and groups in your identity provider reflect only in IAM Identity Center after your identity provider sends those changes […]
> - **Rollback** – you can revert your identity source back to using IAM Identity Center at any time.

Contrast with the **Active Directory** transitions, where the doc is explicit that data is deleted:

> **Changing between Active Directory and an external IdP** […] **Users, groups, and assignments are deleted** – All users, groups, and assignments are deleted from IAM Identity Center.

> **Changing between IAM Identity Center directory and Active Directory** […] **Assignments removed and users and groups deleted** – Changing your identity source to Active Directory deletes your users and groups from the Identity Center directory. This change also removes your assignments.

### Item-by-item answer

| Item | IdC directory → external SAML IdP | Source |
|---|---|---|
| **Permission sets** (the definitions in IdC) | **Preserved.** Permission sets are IdC-level objects, independent of identity source; the docs never list them as deleted. | [considerations](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-considerations.html) (absence of deletion) |
| **Permission-set IAM roles in member accounts** | **Removed** from the AWS accounts (re-provisioned when you re-assign / SCIM re-syncs). This is the concrete meaning of the change-screen warning. | [change](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-change.html) Warning |
| **Assignments** (user/group × permission set × account) | **Preserved** by the switch itself — "continue to work as long as the new IdP sends the correct assertions… must match the user names and groups in IAM Identity Center." | [considerations](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-considerations.html) |
| **Users / groups in the identity store** | **Not deleted** by an IdC-directory→external-IdP switch (deletion is documented only for AD transitions). | [considerations](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-considerations.html) |
| **Instance ARN** | **Survives** — the IdC instance is not torn down by an identity-source change. | (instance not deleted; docs describe only source change) |
| **Identity store ID** | **Survives** for this transition. It **changes only** when switching *to/from Active Directory*. | [considerations — Important box](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-considerations.html) |
| **Access-portal URL** | **Survives** for this transition. It **changes only** on AD transitions (because the identity store ID changes). | [considerations](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-considerations.html) |

The AD-only "Important" box, verbatim, showing *why* the portal URL changes there but not here:

> **Important**
> When changing your identity source type in IAM Identity Center to or from Active Directory be aware that the Identity Store ID will change. […] Your default AWS access portal URL will change. […] For instance, in the Identity Store ARN "arn:aws:identitystore::123456789012:identitystore/d-922763e9b3", "d-922763e9b3" is the Identity Store ID.

### The practical correction for this org

The map (#1) records the current native user as **`sourav_dhar_47`** (a username, not an email) and assumes the switch "deletes existing users/groups/assignments." AWS's actual behavior is subtler: the switch **preserves** those objects, but assignments only keep working if the new IdP's `NameID` **matches** the existing IdC username. Because Google will assert `NameID = primary email` (`souravdhar@discreate.app`) and the native username is `sourav_dhar_47`, **the assertion won't match** — so the old identity is effectively stranded and SCIM creates a new user. **Net effect matches the map's "rebuild" expectation, but the mechanism is mismatch-orphaning + SCIM re-create, not deletion.** The instance ARN / identity store ID / portal URL (`https://bontaramsonta.awsapps.com/start`) all stay put.

---

## 2. Google SCIM = users only; edition coverage

### Users only, not groups (verbatim, from AWS's Google tutorial)

From **Configure SAML and SCIM with Google Workspace and IAM Identity Center** ([docs](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html)):

> SCIM automatic synchronization from Google Workspace is currently limited to user provisioning. Automatic group provisioning is not supported at this time. Groups can be manually created with AWS CLI Identity Store create-group command or AWS Identity and Access Management (IAM) API CreateGroup. Alternatively, you can use ssosync to synchronize Google Workspace users and groups into IAM Identity Center.

And later:

> SCIM automatic synchronization from Google Workspace only supports provisioning users. Automatic group provisioning is not supported at this time. You cannot create groups for your Google Workspace users using the AWS Management Console.

Implication for a **group-driven** access model (which is the map's goal): groups are *not* auto-synced. You must create the IdC groups out-of-band (`aws identitystore create-group` / `ssosync`) and add the SCIM-provisioned users to them, then assign permission sets to those groups. This is the exact friction the map flagged as a candidate "defensible deviation" for alopa's per-account SAML pattern — **confirmed real.**

### Editions that include AWS auto-provisioning

From Google's **About automated user provisioning** ([Workspace admin help](https://support.google.com/a/answer/7681608), now at [knowledge.workspace.google.com](https://knowledge.workspace.google.com/admin/users/advanced/about-automated-user-provisioning)):

> Business Starter and Frontline Starter customers can configure up to 3 apps for automated user provisioning. The Business Standard, Business Plus, Frontline Standard, Frontline Plus, and Enterprise editions can configure up to 100 apps.

**Answer:** *all* listed Google Workspace editions include the auto-provisioning (SCIM) feature — it is **not** an Enterprise-only gate. The only edition difference is the **app count cap**:

| Edition | Auto-provisioning apps allowed |
|---|---|
| Business Starter, Frontline Starter | up to **3** |
| Business Standard, Business Plus, Frontline Standard, Frontline Plus, Enterprise | up to **100** |

(The page does not list Cloud Identity Premium in the limits table.) For this org (single AWS SSO app), even Business Starter's 3-app cap is sufficient — **any paid edition works**. Prerequisite noted by Google: "you need to set up SSO for Amazon Web Services" first (see ordering, §4).

---

## 3. Baseline SAML attribute mapping + SCIM handshake shape

### SAML — is `NameID` = primary email the baseline? **Yes.**

From the AWS Google tutorial, Step 2 (Service provider / Name ID config), verbatim:

> On the **Service provider details** page, complete the fields under **Name ID** as follows:
> - For **Name ID format**, select **EMAIL**
> - For **Name ID**, select **Basic Information > Primary email**

Baseline attribute mappings on the Google side (tutorial Step 2, Attribute Mapping):

| AWS SAML app attribute | Google Directory attribute |
|---|---|
| `NameID` (Subject) | Basic Information → **Primary email** (format `EMAIL`) |
| `https://aws.amazon.com/SAML/Attributes/RoleSessionName` | Basic Information → **Primary Email** |
| `https://aws.amazon.com/SAML/Attributes/Role` | any attribute (tutorial suggests **Department**) |

So the standard baseline is **NameID = primary email, format EMAIL**. Source: [gs-gwp](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html).

### SCIM handshake — IdC issues endpoint + bearer token, Google consumes

From the same tutorial:

> You configure this connection in Google Workspace using your SCIM endpoint for IAM Identity Center and an IAM Identity Center bearer token.

Enabling automatic provisioning in the IdC console (Step 4) surfaces both values:

> This immediately enables automatic provisioning in IAM Identity Center and displays the necessary SCIM endpoint and access token information.
> - **SCIM endpoint** — e.g. `https://scim.{Region}.amazonaws.com/{instance-id}/scim/v2` (IPv4) or `https://scim.{Region}.api.aws/{instance-id}/scim/v2` (dual-stack)
> - **Access token** — Choose **Show token** to copy the value.
> **Warning:** This is the only time where you can obtain the SCIM endpoint and access token. Ensure you copy these values before moving forward.

Google then consumes them (Step 5): paste **Access token** into Google's *Access token* field and the **SCIM endpoint** into Google's *Endpoint URL* field. Protocol is **SCIM 2.0** ([gs-gwp](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html)). Note: the endpoint/token are single-reveal — if lost, regenerate in the IdC console.

---

## 4. Ordering constraint: SAML before SCIM

**SAML/SSO must be established first; SCIM auto-provisioning second.** Evidence:

- AWS tutorial sequence: Step 1–2 configure the **SAML** app + change identity source; Step 3 turns the AWS app **ON for users**; only then Step 4 **enables SCIM** (endpoint+token) and Step 5 wires it into Google. ([gs-gwp](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html))
- Google enforces this: the auto-provisioning activation toggle is gated on SSO being on —
  > The activation slider is disabled if IAM Identity Center isn't turned on for users. Choose **User access** and turn the app on to enable the slider.
- Google's help repeats the prerequisite: "Before setting up automated user provisioning, you need to set up SSO for Amazon Web Services." ([Workspace admin help](https://support.google.com/a/answer/13047358))

So the mandated order is: **(1) change identity source to Google SAML → (2) enable the AWS app for users in Google → (3) enable SCIM in IdC (get endpoint+token) → (4) configure & activate auto-provisioning in Google.**

---

## Sources

- AWS — Change your identity source: https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-change.html
- AWS — Considerations for changing your identity source: https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-considerations.html
- AWS — Configure SAML and SCIM with Google Workspace and IAM Identity Center: https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html
- AWS — Provision users and groups using SCIM: https://docs.aws.amazon.com/singlesignon/latest/userguide/provision-automatically.html
- Google Workspace — About automated user provisioning: https://support.google.com/a/answer/7681608 (redirects to https://knowledge.workspace.google.com/admin/users/advanced/about-automated-user-provisioning)
- Google Workspace — Configure Amazon Web Services user provisioning: https://support.google.com/a/answer/13047358
