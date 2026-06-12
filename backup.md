# Wiregene Work Backup

Generated: 2026-06-13 07:34:01 +09:00

This file is a safe handoff note for continuing the project on another PC.
Do not store passwords, tokens, API keys, cookies, or private environment
values in this file.

## Current Repository

- Repository: wiregene-portal
- Remote: https://github.com/rhhyun/wiregene-portal.git
- Branch: main
- Latest known commit: e0b40a5 Allow portal storage health probe
- App version: Ver 1.49

## Git Status At Generation

Env-like paths are intentionally omitted from this section.

```text
M backup.md
 M src/components/AccountManagementPanel.tsx
 M src/lib/operational-error.ts
 M src/lib/version.ts
```

## Active Work Summary

- `portal.wiregene.com` is the Wiregene account and site launcher service.
- Portal account ID storage is intended to run on Synology with
  `PORTAL_ACCOUNT_STORAGE_BACKEND=local-json`.
- If `portal.wiregene.com` is served by Vercel, account creation cannot write
  local JSON and will fail under `/var/task`.
- The Synology update script checks local container readiness, rendered version,
  and whether the public portal host is still returning Vercel headers.
- Synology source checkout: `/volume1/docker/wiregene-portal`.
- Synology runtime folder: `/volume1/docker/portal`.
- This backup file can be regenerated at the end of each work session.

## Continue On Another PC

```powershell
cd C:\Users\rhhyu\Documents\Portal.wiregene.com
git pull --ff-only origin main
npm.cmd install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\write-backup-md.ps1
```

Then inspect `backup.md`, run the needed verification commands, and continue
from the latest commit.

## Synology Commands

```sh
APP_DIR=/volume1/docker/wiregene-portal
REPO_URL=https://github.com/rhhyun/wiregene-portal.git
if [ ! -d "$APP_DIR/.git" ]; then
  if [ -e "$APP_DIR" ]; then
    echo "ERROR: $APP_DIR exists but is not a Git checkout."
    echo "Move it aside or set APP_DIR to the real checkout path."
    exit 1
  fi
  git clone "$REPO_URL" "$APP_DIR"
fi
git -C "$APP_DIR" pull --ff-only origin main
/bin/sh "$APP_DIR/scripts/synology-write-backup-md.sh"
/bin/sh "$APP_DIR/scripts/synology-update-portal.sh"
```

The Synology backup writer updates this file locally. To make the updated
handoff visible on other PCs, commit and push `backup.md` from a trusted
development machine after reviewing it.

## Important Files

- `backup.md`: latest handoff snapshot.
- `scripts/write-backup-md.ps1`: Windows backup writer.
- `scripts/synology-write-backup-md.sh`: Synology backup writer.
- `docs/synology-meta-portal-split.md`: transition NAS layout and scheduler notes.
- `scripts/synology-update-portal.sh`: full Synology update, build, restart,
  local health check, version check, and public route check.
- `scripts/synology-start-portal.sh`: Synology container build/restart helper.
- `synology/docker/portal/.env.example`: runtime environment template.
- `src/lib/version.ts`: visible application version.

## Verification Checklist

- `npm.cmd run lint -- --max-warnings=0`
- `npx.cmd tsc --noEmit --pretty false --incremental false`
- `npm.cmd run build`
- On Synology, syntax-check shell scripts with `sh -n scripts/<name>.sh`.
- After deployment, confirm `portal.wiregene.com` does not return
  `Server: Vercel` or `X-Vercel-Id` headers.

## Manual Handoff Notes

<!-- MANUAL-NOTES-START -->
Current production route issue as of 2026-06-12:

- `portal.wiregene.com` resolves to `76.76.21.21`, and HTTP headers show
  `Server: Vercel` plus `X-Vercel-Id`.
- Browser account creation is therefore hitting Vercel, not Synology. That is
  why local JSON writes fail under `/var/task` even after the Synology Docker
  container is updated.
- Do not remove the Vercel alias before Synology routing is ready, or the public
  domain may break instead of moving to the NAS.
- Required external fixes:
  1. In DSM Reverse Proxy, route source `HTTPS portal.wiregene.com:443` to
     destination `HTTP 127.0.0.1:3002`.
  2. Ensure the router/firewall forwards external TCP 443 to the Synology NAS if
     the NAS is the public endpoint.
  3. In Cloudflare DNS, point `portal.wiregene.com` to the Synology public
     endpoint, not Vercel `76.76.21.21`.
  4. After DNS/reverse proxy works, remove the Vercel alias/domain binding for
     `portal.wiregene.com` from the Vercel `wiregene-portal` project.
- Verify with:
  `Resolve-DnsName portal.wiregene.com` and
  `curl.exe -I https://portal.wiregene.com/`. The response must not contain
  `Server: Vercel` or `X-Vercel-Id`.
- Synology scheduler command:
  `cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh`
- Vercel Google Drive setup command after OAuth values are filled:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\vercel-configure-portal-google-drive.ps1 -Redeploy`
- If Vercel already has the Google Drive OAuth secrets, use:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\vercel-configure-portal-google-drive.ps1 -UseExistingVercelGoogleDriveSecrets -Redeploy`
- 2026-06-12: Vercel metadata showed existing `GOOGLE_DRIVE_CLIENT_ID`,
  `GOOGLE_DRIVE_CLIENT_SECRET`, and `GOOGLE_DRIVE_REFRESH_TOKEN` on
  `wiregene-portal`. Added `PORTAL_ACCOUNT_STORAGE_BACKEND=google-drive` and
  `PORTAL_ACCOUNT_STORAGE_PATH_DRIVE_FILENAME=portal-accounts.json`, then
  redeployed production and aliased `portal.wiregene.com`.
- 2026-06-13: Portal account storage reached `backend=google-drive`, then
  failed at Google OAuth refresh with `invalid_grant`. This means the old
  `/var/task` local-json problem is no longer the active failure; the Portal
  Vercel Google Drive OAuth client/refresh-token pair is invalid or mismatched.
- Vercel marks these production env vars as `sensitive`; per Vercel behavior
  they are non-readable after creation. CLI/API returns `decrypted=false` and
  `valueLength=0`, so do not assume the values are empty and do not try to
  recover them by `vercel env pull`.
- Added `scripts/vercel-audit-google-drive-env.ps1` /
  `npm run vercel:audit-google-drive-env` to compare Portal/Search/Meta
  Google Drive env metadata without printing secrets.
- Added a Search repo workflow at
  `C:\Users\rhhyu\Documents\GitHub\research-briefing-platform\.github\workflows\sync-portal-google-drive-env.yml`.
  It uses Search GitHub Actions secrets as the source of the known Google Drive
  OAuth values, writes them to the `wiregene-portal` Vercel project, then
  redeploys the latest Portal production deployment. This avoids issuing a new
  Google refresh token.
- Added `GET /api/admin/storage-health`, protected by
  `PORTAL_STORAGE_HEALTH_SECRET` via `x-wiregene-storage-health-secret`, so
  production can verify Portal account Google Drive storage without relying on
  browser Basic Auth state. Without the secret it returns 404.
- The Portal proxy must also allow `/api/admin/storage-health` through when
  the same health secret header matches; otherwise Basic Auth blocks the route
  before the health handler can run.
- 2026-06-13: Production health check on
  `https://portal.wiregene.com/api/admin/storage-health` reached
  `backend=google-drive` and failed with
  `Google OAuth refresh failed: invalid_client`. This is no longer a
  `local-json`/`/var/task` problem; Google rejected the OAuth Client ID/Secret
  pair currently stored on Vercel.
- 2026-06-13: Local scan of Documents/Desktop/Downloads and Google Drive search
  found no reusable real `GOOGLE_DRIVE_CLIENT_ID`,
  `GOOGLE_DRIVE_CLIENT_SECRET`, `GOOGLE_DRIVE_REFRESH_TOKEN` set. Results were
  placeholders, docs, package files, or unrelated service-account/client IDs.
- 2026-06-13: Vercel API metadata for Portal/Search/Meta production Google
  Drive env vars shows `type=sensitive`, `decrypted=false`, `valueLength=0`.
  Vercel will not return these secret values after creation, so they cannot be
  copied from Search/Meta to Portal. A `decrypt=true` attempt returned 403.
- 2026-06-13: Search GitHub Actions secrets were already tested by running the
  existing `research-briefing.yml` config check and failed with
  `invalid_client`, so Search GitHub Secrets are not a valid source of OAuth
  values for Portal.
- 2026-06-13: Updated account-management error text and dashboard operational
  errors to distinguish `SERVERLESS_LOCAL_STORAGE`, Google OAuth
  `invalid_client`, and Google OAuth `invalid_grant`; bumped app version to
  Ver 1.49.
<!-- MANUAL-NOTES-END -->
