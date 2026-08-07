# SCIM auto-provisioning requires Google's pre-integrated AWS app (not a custom SAML app)

Research date: 2026-07-25. Sources are AWS official docs (`docs.aws.amazon.com`) and
Google Workspace Admin Help (`knowledge.workspace.google.com`, the current host for
`support.google.com/a`).

## TL;DR / Decision

- The custom SAML app shows no **Auto-provisioning** option because **Google auto-provisioning (SCIM)
  is only available for apps in Google's pre-integrated catalog** — custom/hand-built SAML apps
  cannot do SCIM. This is expected, not a misconfiguration.
- The pre-integrated catalog app is named **"Amazon Web Services"** in Google's catalog. That single
  app provides **both** SAML SSO into IAM Identity Center (IdC) **and** SCIM auto-provisioning. There
  is **no separately-named "AWS IAM Identity Center" catalog app** distinct from it — AWS's own tutorial
  uses this one app and refers to it interchangeably as the "AWS IAM Identity Center application".
- In IdC, **SAML and SCIM are independent channels.** SCIM uses a dedicated endpoint + bearer token
  generated in the IdC console; it does not know or care which Google app produced the SAML assertion.
- **Recommended clean path:** add the pre-integrated **"Amazon Web Services"** catalog app and use it
  for **both** SAML and SCIM, then delete the custom SAML app. Set SAML **NameID = EMAIL → Primary email**
  and let SCIM **userName = Primary email**. Because the target IdC identity-store user
  (`souravdhar@discreate.app`) already exists with a matching username+email, SCIM **adopts/overwrites**
  it rather than colliding (see Q4).

---

## Q1 — Does SCIM require a pre-integrated catalog app? Do custom SAML apps support it?

**Confirmed: yes, catalog app required; no, custom SAML apps do not support auto-provisioning.**

Google's "About automated user provisioning" page lists provisioning as available only for its
**supported (pre-integrated) apps**, and states the prerequisite is to *"Set up SSO, using Google as
your IdP, for any of our supported apps."* It never references custom SAML apps — configuration is
always via per-app guides for apps on Google's supported list. Custom SAML apps built under
**Apps > Web and mobile apps > Add custom SAML app** simply do not expose an Auto-provisioning
section, which is why your custom app shows none.

- https://knowledge.workspace.google.com/admin/users/advanced/about-automated-user-provisioning

## Q2 — The catalog app, and the official AWS setup path

**Catalog app name:** In Google's pre-integrated catalog the app is **"Amazon Web Services"**
(Google's official provisioning page is titled "Configure Amazon Web Services user provisioning").
This one pre-integrated app supports **both**:
- **SAML SSO** into IAM Identity Center, and
- **SCIM auto-provisioning** into the IdC identity store.

AWS's whats-new post describes it as *"the AWS cloud application available in Google's pre-integrated
apps catalog"* used to configure both auto-provisioning and the SAML connection. Note: AWS's tutorial
text is internally loose — Step 1 says search **"Amazon Web Services"** and select
**"Amazon Web Services (SAML)"**, while later steps call it the **"AWS IAM Identity Center application."**
These refer to the same single catalog app; there is not a second, distinctly-named "AWS IAM Identity
Center" app.

**Official AWS setup path** — "Configure SAML and SCIM with Google Workspace and IAM Identity Center":
1. Google Admin: add the **Amazon Web Services** catalog app; copy Google IdP metadata (SSO URL, Entity ID, certificate).
2. IdC console: **Settings > Actions > Change identity source > External identity provider**; upload Google metadata; copy the IdC **ACS URL** and **issuer URL** back into the Google app's Service Provider details.
   - Set **Name ID format = EMAIL**, **Name ID = Basic Information > Primary email**.
3. Google Admin: turn the app **ON** for users (Service status).
4. IdC console: **Settings > Automatic provisioning > Enable** → generates the **SCIM endpoint** and **bearer access token** (shown once).
5. Google Admin: the app's **Auto-provisioning** section → paste token + endpoint, verify mandatory attribute mappings, set deprovisioning, toggle **Active**.

- https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html
- https://aws.amazon.com/about-aws/whats-new/2023/06/aws-iam-identity-center-automated-user-provisioning-google-workspace
- https://knowledge.workspace.google.com/admin/users/advanced/configure-amazon-web-services-user-provisioning

## Q3 — Migration / coexistence: custom app for SAML + catalog app for SCIM?

**IdC treats SAML and SCIM as independent channels — confirmed.**
- **SAML** is established by exchanging metadata (Google IdP metadata into IdC; IdC ACS/issuer URLs into Google).
- **SCIM** is a separate inbound channel authenticated only by the **SCIM endpoint + bearer token** generated
  in the IdC console (Step 4 above). The token authenticates the *provisioning* connection; it has no
  binding to, and no awareness of, which Google app sends SAML assertions.

Implications:
- You **can** technically attach SCIM via the catalog app while keeping the custom app for SAML — IdC won't
  object, because the SCIM token doesn't validate SAML origin. But this leaves you maintaining two Google apps
  and two attribute-mapping surfaces.
- The catalog app **can also take over SAML**, letting you delete the custom app.

**Recommended clean path:** replace the custom SAML app with the pre-integrated **"Amazon Web Services"**
catalog app and use it for **both** SAML and SCIM. Keep **NameID = Primary email** so the SAML subject
continues to match the existing identity-store user, and let SCIM userName = Primary email so provisioning
adopts that same user. Rotating to a single catalog app is the officially documented, supported topology
(the AWS tutorial configures SAML and SCIM on the one app).

- https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html

## Q4 — SCIM `userName` attribute and adopting the existing identity-store user

**SCIM `userName` = the user's Primary email.** In the Google app's auto-provisioning attribute mapping,
the mandatory `userName` maps to **Basic Information > Primary email** (Google requires you verify all
asterisked mandatory attributes are mapped before activating). This matches the SAML **NameID = Primary email**,
so both channels key on the same identifier.

**Adoption vs collision — the key AWS-documented behavior.** From the AWS tutorial's Considerations:

> "If there is an existing user in Identity Center directory with the same username and email, the user
> will be overwritten and synchronized using SCIM from Google Workspace."

So the manually-created identity-store user `souravdhar@discreate.app` will be **adopted (overwritten in
place)** by SCIM — **provided both its username AND email match** the incoming Google user's Primary email
(`souravdhar@discreate.app`). This is the desired outcome, not a duplicate.

**Gotcha:** if the existing store user's **username and email do not both match** (e.g. username was set to
something other than the email, or case/domain differs), SCIM will not match it and you can hit a
**"Duplicate user or group"** provisioning error instead of adoption. Before enabling SCIM, verify the existing
IdC user's **username == primary email == `souravdhar@discreate.app`** exactly. Also ensure the Google user
has single-valued attributes and populated First/Last/Display name, or the SCIM sync for that user fails.

- https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html  (Considerations; Troubleshooting: "Duplicate user or group error")
- https://knowledge.workspace.google.com/admin/users/advanced/configure-amazon-web-services-user-provisioning

---

## Sources

- AWS — Configure SAML and SCIM with Google Workspace and IAM Identity Center:
  https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html
- AWS whats-new — automated user provisioning from Google Workspace (2023-06):
  https://aws.amazon.com/about-aws/whats-new/2023/06/aws-iam-identity-center-automated-user-provisioning-google-workspace
- Google — About automated user provisioning:
  https://knowledge.workspace.google.com/admin/users/advanced/about-automated-user-provisioning
- Google — Configure Amazon Web Services user provisioning:
  https://knowledge.workspace.google.com/admin/users/advanced/configure-amazon-web-services-user-provisioning
