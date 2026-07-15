# Wiregene Portal

This folder defines the operating boundary for `portal.wiregene.com`.
The source code still lives in the shared Next.js app under `src/`.

## Purpose

- Dedicated runtime for site launch, identity administration, and account
  management.
- UI entry: `src/components/PortalDashboard.tsx`
- Account UI: `src/components/AccountManagementPanel.tsx`
- Account data: `src/lib/portal-accounts.ts`
- API boundary: `src/app/api/admin/**`

## Runtime Mode

For the Synology Docker project, set:

```text
WIREGENE_APP_MODE=portal
APP_BASE_URL=https://portal.wiregene.com
WIREGENE_ADMIN_EMAILS=admin@example.com
```

Use `APP_BASIC_AUTH_USER`/`APP_BASIC_AUTH_PASSWORD` or
`APP_BASIC_AUTH_USERS` for the actual login secret. Do not commit the password.

## Connected Sites

The Portal first screen shows the site launcher before account management. The
current user-facing registry is maintained in `src/lib/portal-accounts.ts` and
includes Portal, Homepage, Homepage Admin, AGI, Search, Omni, Protocol, Meta,
Finance, Music, HyunLab, Hyun Lab Homepage, SCI Experiment, SCI BBB AI, ARIM
Human, and Diabetic Foot Screening.

The shared Master entry ID is `rhhyun`. Supply the Master password only at
runtime through `IDENTITY_PASSWORD`; do not store it in source, docs, or
`backup.md`.

## Deployment

Use the Synology Docker package in:

```text
synology/docker/portal
```

The Docker package mounts the shared source directory and starts the same app
with `WIREGENE_APP_MODE=portal`.

Portal Vercel builds fail by default because member management requires the
Synology persistent `local-json` volume. A time-boxed read-only emergency build
requires `PORTAL_ALLOW_VERCEL_EMERGENCY_DEPLOY=true`; it is not a production
account-management runtime.

DSM Task Scheduler boot-time/update command:

```text
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

Automatic identity setup for `rhhyun`:

```text
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && IDENTITY_PASSWORD='<provided master password>' /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
```

## Boundary Rules

The shared proxy allows only these paths in portal mode:

```text
/
/api/auth/logout
/api/admin/*
```

Portal-created admin accounts receive all registered site permissions. The
shared Basic Auth proxy still reads `APP_BASIC_AUTH_*` values for runtime login.
