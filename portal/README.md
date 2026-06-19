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

For the shared Vercel project, leave `WIREGENE_APP_MODE` empty. The app
detects `portal.wiregene.com` from the request host.

For a separate Docker or Vercel project, set:

```text
WIREGENE_APP_MODE=portal
APP_BASE_URL=https://portal.wiregene.com
WIREGENE_ADMIN_EMAILS=admin@example.com
```

Use `APP_BASIC_AUTH_USER`/`APP_BASIC_AUTH_PASSWORD` or
`APP_BASIC_AUTH_USERS` for the actual login secret. Do not commit the password.

## Deployment

Use the Synology Docker package in:

```text
synology/docker/portal
```

The Docker package mounts the shared source directory and starts the same app
with `WIREGENE_APP_MODE=portal`.

DSM Task Scheduler boot-time/update command:

```text
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

Automatic identity setup for `rhhyun`:

```text
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
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
