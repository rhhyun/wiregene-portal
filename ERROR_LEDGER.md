# Wiregene Portal Error Ledger

## WG-PORTAL-AUTH-STALE-MASTER

- Date: 2026-07-15
- Symptom: `wiregene` can log in across sites, but `rhhyun` cannot, or the UI
  still reports that a password change is required after saving a new password.
- Root cause: The identity automation did not reliably update existing
  `rhhyun` entries. In particular, comma-delimited auth values without a final
  newline could miss the last entry and append a duplicate stale/fresh pair.
- Correct fix: Upsert `rhhyun` in `APP_BASIC_AUTH_USERS` and ARIM professor
  account env values. Supply the intended Master password at runtime through
  `IDENTITY_PASSWORD`.
- Prevention rule: Auth automation must update existing target identities and
  must parse comma-delimited env values correctly even without a trailing
  newline.
- Verification command:

```sh
IDENTITY_PASSWORD='<provided master password>' /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
```

- Affected files:
  - `scripts/synology-auto-wiregene-identity.sh`
  - `AUTH_RUNBOOK.md`
  - `backup.md`

## WG-PORTAL-SUBSITE-MISSING-LAUNCHER

- Date: 2026-07-15
- Symptom: New Wiregene services such as AGI, Music, or DMFoot are not visible
  on the Portal first screen or in the admin site permission list.
- Root cause: The launcher UI and admin permission list used fixed site arrays
  that had to be updated when new domains were added.
- Correct fix: Register new user-facing sites in `src/lib/portal-accounts.ts`
  and render the first-screen launcher from that registry.
- Prevention rule: Add each new user-facing `wiregene.com` subdomain to the
  Portal registry and admin site list before deployment.
- Verification command:

```sh
npm.cmd run build
```

- Affected files:
  - `src/lib/portal-accounts.ts`
  - `src/lib/basic-auth-users.ts`
  - `src/components/PortalDashboard.tsx`
