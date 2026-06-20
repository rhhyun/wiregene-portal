# Portal Security Model

`portal.wiregene.com` is the control plane for Wiregene subsite identity and
site-specific access records. Treat it as a privileged administration surface.

## Identity Sources

Portal supports two identity sources.

- Environment Basic Auth:
  `APP_BASIC_AUTH_USER`, `APP_BASIC_AUTH_PASSWORD`, and `APP_BASIC_AUTH_USERS`
  are bootstrap and break-glass credentials. They can sign in to protected
  Wiregene sites, but they are not automatically Portal administrators. Non-admin
  environment users are limited by `APP_BASIC_AUTH_SITE_ACCESS`; the shared
  `wiregene` account defaults to `search` only.
- Portal account storage:
  Accounts stored in `portal-accounts.json` are the normal managed Portal
  accounts. They have explicit role, site access, disabled state, password hash,
  and password-reset state.

## Administrator Rule

A user can administer Portal only when one of these is true:

- the user is a Portal account with `role=admin` and access to `portal`
- the user is an environment credential and the username is explicitly listed in
  `WIREGENE_ADMIN_EMAILS`, `APP_ADMIN_USERS`, or `APP_ADMIN_USER`

Do not treat every valid Basic Auth credential as an administrator.

Do not grant the shared `wiregene` account full administration. It may remain
available for `search.wiregene.com` only. Portal ignores `wiregene` in admin
environment variables even if an old deployment still contains it there. All
other subsites should use their own Portal-managed ID/PW records, and those
passwords should be rotated before being used operationally.

## Subsite Login Rule

Subsites should call:

```text
POST https://portal.wiregene.com/api/auth/check
x-wiregene-auth-check-secret: <shared secret>

{ "username": "...", "password": "...", "site": "<portal site id>" }
```

The shared secret must be identical between Portal and the subsite. The endpoint
returns access only when the credential is valid and the account includes the
requested site ID.

## Site-Specific ID/PW Records

The `siteCredentials` records are for site-specific login IDs and password
rotation tracking. Passwords are never returned after storage. The admin flow can
generate a strong password or accept a manual password that meets the policy.

Manual site passwords must be at least 12 characters, cannot start/end with
whitespace, and cannot contain line breaks. Leaving the PW field blank generates
a strong temporary password.

## Mutation Protection

Admin mutations (`POST`, `PATCH`, `DELETE` on `/api/admin/accounts`) require:

- Portal mode
- authenticated Portal admin
- same-origin or same-site browser request, when Origin or Fetch Metadata
  headers are present
- writable account storage

Cross-site account-management requests are rejected.

## Deployment Checklist

- `APP_BASIC_AUTH_USERS` contains emergency accounts only.
- `APP_BASIC_AUTH_SITE_ACCESS=wiregene=search` is set unless a narrower
  emergency policy is intentionally chosen.
- `rhhyun` or another admin is listed in `WIREGENE_ADMIN_EMAILS`,
  `APP_ADMIN_USERS`, or `APP_ADMIN_USER`.
- `PORTAL_AUTH_CHECK_SECRET` / `WIREGENE_AUTH_CHECK_SECRET` is set and shared
  only with trusted subsites.
- Production identity storage should run from Synology with
  `PORTAL_ACCOUNT_STORAGE_BACKEND=local-json`.
- Google Drive is a backup mirror only when
  `PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP=true`.
- Vercel deployments are emergency/temporary access only. They should not be
  the long-term source of truth for Portal ID/PW records.
- Run `npm.cmd run lint -- --max-warnings=0`, `npx.cmd tsc --noEmit --pretty
  false`, and `npm.cmd run build` before deployment.
