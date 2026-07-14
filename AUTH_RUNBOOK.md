# Wiregene Portal Auth Runbook

This runbook covers the current Portal authentication and identity propagation
rules. Do not store plaintext passwords in this repository.

## Master Entry Policy

- Master login ID: `rhhyun`.
- The Master password is supplied at runtime through `IDENTITY_PASSWORD`; it is
  never committed, printed, or written to `backup.md`.
- `portal.wiregene.com` remains the control surface for account creation,
  deletion, password changes, site permissions, and site launch links.
- `APP_BASIC_AUTH_USERS` is the bootstrap/runtime Basic Auth source. The
  Synology automation updates existing `rhhyun` entries instead of leaving stale
  passwords in place.

## Connected Site Scope

The Portal site registry currently includes:

- `portal.wiregene.com`
- `www.wiregene.com`
- `admin.wiregene.com`
- `agi.wiregene.com`
- `music.wiregene.com`
- `search.wiregene.com`
- `omni.wiregene.com`
- `protocol.wiregene.com`
- `meta.wiregene.com`
- `finance.wiregene.com`
- `hyunlab.wiregene.com`
- `hyun.wiregene.com`
- `sci-experiment.wiregene.com`
- `sci-bbb.wiregene.com`
- `sci-bbb-ai.wiregene.com`
- `arim.wiregene.com`
- `dmfoot.wiregene.com`

Internal worker, preview, test, and typo-alias hosts are not promoted as normal
first-screen user links unless their service becomes a user-facing site.

## Synology Identity Setup

Run this on demand after pulling the latest source. Replace the placeholder with
the Master password provided out-of-band:

```sh
cd /volume1/docker/wiregene-portal
git pull --ff-only origin main
IDENTITY_PASSWORD='<provided master password>' /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
```

The script updates:

- `/volume1/docker/portal/.env`
- known subsite `.env` files under `/volume1/docker`
- `APP_BASIC_AUTH_USERS`
- `APP_BASIC_AUTH_SITE_ACCESS=wiregene=search`
- `WIREGENE_ADMIN_EMAILS`
- `PORTAL_AUTH_CHECK_SECRET`
- `WIREGENE_AUTH_CHECK_SECRET`
- `PORTAL_AUTH_CHECK_URL`

For Music, the script also writes:

- `MUSIC_AUTH_USER=rhhyun`
- `MUSIC_AUTH_PASSWORD_SHA256=<sha256 of runtime password>`
- `MUSIC_AUTH_SECRET=<existing or generated secret>`

Finance Brain is listed as Portal-aligned. If that service is deployed with its
own web password environment variable, set it from the same out-of-band Master
password; do not commit the plaintext value.

AGI is listed by Portal, but AGI-specific login support depends on that service's
own auth implementation. If AGI uses provider/OAuth variables rather than Basic
Auth, its application code must support Portal-shared auth before the same
Master password can work there.

## DSM Scheduler

Use this scheduler command for regular Portal updates:

```sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh
```

Run identity setup separately when the Master credential changes or a new
subsite env file must be synchronized.

## Verification

Local verification:

```sh
npm.cmd run lint -- --max-warnings=0
npm.cmd run build
sh -n scripts/synology-auto-wiregene-identity.sh
```

Synology verification:

```sh
cd /volume1/docker/wiregene-portal
git pull --ff-only origin main
IDENTITY_PASSWORD='<provided master password>' /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
```

Then test `rhhyun` login on Portal and each site whose auth implementation is
connected to `APP_BASIC_AUTH_USERS`, Portal auth check, ARIM professor accounts,
or Music SHA-256 password auth.
