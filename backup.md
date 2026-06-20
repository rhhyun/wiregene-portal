# Wiregene Work Backup

Generated: 2026-06-20 12:22:05 +0900

This file is a safe handoff note for continuing the project on another PC.
Do not store passwords, tokens, API keys, cookies, or private environment
values in this file.

## Current Repository

- Repository: wiregene-portal
- Remote: https://github.com/rhhyun/wiregene-portal.git
- Branch: main
- Latest known commit: d77bc7f Remove cross-site sidebar links
- App version: Ver 1.57

## Git Status At Generation

Env-like paths and backup.md are intentionally omitted from this section.

```text
(clean after omitting env-like paths and backup.md)
```

## Active Work Summary

- `portal.wiregene.com` is the Wiregene account and site launcher service.
- ID/PW add, delete, and change operations are managed from
  `portal.wiregene.com`; `APP_BASIC_AUTH_*` values are reserved for
  break-glass/bootstrap access.
- Portal account ID storage is intended to run on Synology with
  `PORTAL_ACCOUNT_STORAGE_BACKEND=local-json`.
- If `portal.wiregene.com` is served by Vercel, account storage must use
  `PORTAL_ACCOUNT_STORAGE_BACKEND=google-drive` with a valid Google OAuth
  Client ID/Secret/Refresh Token set on the Vercel project.
- The Synology update script checks local container readiness, rendered version,
  and whether the public portal host is still returning Vercel headers. The
  public route check warns by default and only fails when
  `PUBLIC_PORTAL_ROUTE_POLICY=synology`.
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

One-time or on-demand automatic identity setup:

```sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
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
- `scripts/synology-auto-wiregene-identity.sh`: automatic identity/admin/shared
  auth secret setup for Portal and known subsite env files.
- `scripts/synology-start-portal.sh`: Synology container build/restart helper.
- `synology/docker/portal/.env.example`: runtime environment template.
- `src/lib/version.ts`: visible application version.

## Verification Checklist

- `npm.cmd run lint -- --max-warnings=0`
- `npx.cmd tsc --noEmit --pretty false --incremental false`
- `npm.cmd run build`
- On Synology, syntax-check shell scripts with `sh -n scripts/<name>.sh`.
- If public Portal is intended to run from Synology, confirm
  `portal.wiregene.com` does not return `Server: Vercel` or `X-Vercel-Id`
  headers. If public Portal is intentionally Vercel, keep
  `PUBLIC_PORTAL_ROUTE_POLICY=warn` and verify Google Drive OAuth storage.

## Manual Handoff Notes

<!-- MANUAL-NOTES-START -->
Current production route issue as of 2026-06-12:

- `portal.wiregene.com` resolves to `76.76.21.21`, and HTTP headers show
  `Server: Vercel` plus `X-Vercel-Id`.
- Browser account creation is therefore hitting Vercel, not Synology. If Vercel
  is the intended public host, Portal account storage must be Google Drive with
  valid OAuth values on the Vercel project. If Synology is the intended public
  host, move DNS/reverse proxy to Synology before expecting browser writes to use
  Synology local JSON.
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
- Synology public route policy:
  `PUBLIC_PORTAL_ROUTE_POLICY=warn` lets Synology updates finish when the
  public host is intentionally still Vercel; `PUBLIC_PORTAL_ROUTE_POLICY=synology`
  makes the scheduler fail if Vercel headers remain.
- Vercel Portal Google Drive OAuth repair command after exact Google Cloud
  OAuth values are known:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\repair-portal-google-drive-oauth.ps1`
- Portal refresh token generation command after a new Google OAuth Client ID
  and Client Secret are created:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\get-portal-google-drive-refresh-token.ps1`
- The token generation wrapper requests only
  `https://www.googleapis.com/auth/drive.file` for Portal account storage,
  prompts for the Client ID/Secret without writing them to disk, prints the
  Google approval URL, and then prints the verified refresh token in the local
  terminal after approval.
- The repair script prompts for `GOOGLE_DRIVE_CLIENT_ID`,
  `GOOGLE_DRIVE_CLIENT_SECRET`, and `GOOGLE_DRIVE_REFRESH_TOKEN`, validates
  them against Google's token endpoint before changing Vercel, writes only the
  Portal project's Vercel env vars, redeploys production, and calls the storage
  health endpoint. It does not print secret values.
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
- 2026-06-13: Added `scripts/repair-portal-google-drive-oauth.ps1` and
  `npm run vercel:repair-portal-google-drive`. Use this instead of copying
  Search/Meta secrets. It validates the OAuth 3-value set first, then updates
  only Portal Vercel env vars, redeploys, and health-checks
  `portal-accounts.json`.
- 2026-06-13: Added `scripts/get-portal-google-drive-refresh-token.ps1` and
  `npm run google-drive:oauth:portal` so a Portal refresh token can be issued
  with Drive-only scope from the new Client ID/Secret before running the repair
  script.
- 2026-06-13: Updated the Synology public route check. It no longer says browser
  writes will always fail with `/var/task`; it now explains Vercel public
  routing vs Synology public routing and only fails on Vercel headers when
  `PUBLIC_PORTAL_ROUTE_POLICY=synology`.
- 2026-06-13: Added `omni.wiregene.com` to Portal launcher and account
  management. Portal login accounts now stay separate from `siteCredentials`,
  which store site-specific ID/PW hashes for create, delete, and password
  change flows without mixing different subsite passwords.
- 2026-06-14: Added `protocol.wiregene.com` as `protocol` to the Portal
  launcher, Portal account/site credential management list, default user site
  selection, and environment-admin site authorization list. Existing admin
  accounts normalize to all current Portal site IDs, so admin users include the
  new Protocol site automatically after deployment.
- 2026-06-19: The failed NAS message
  `/bin/sh: /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh: No such file or directory`
  meant the automation script had been written locally but had not yet been
  committed and pushed to GitHub, so Synology `git pull` could not download it.
- 2026-06-19: Added `scripts/synology-auto-wiregene-identity.sh`. It clones or
  updates `/volume1/docker/wiregene-portal`, creates `/volume1/docker/portal/.env`
  if missing, preserves existing `wiregene` credentials, adds `rhhyun` to
  `APP_BASIC_AUTH_USERS`, adds `rhhyun` to `WIREGENE_ADMIN_EMAILS`, syncs
  `PORTAL_AUTH_CHECK_SECRET`, `WIREGENE_AUTH_CHECK_SECRET`, and
  `PORTAL_AUTH_CHECK_URL` to known subsite `.env` files, adds `rhhyun` to
  `ARIM_PROFESSOR_ACCOUNTS` when an ARIM env file is found, and restarts Portal
  plus known compose runtimes when `AUTO_START=true`.
- 2026-06-19: If no existing `rhhyun` or `wiregene` password can be reused, the
  identity script generates an initial password and stores it only at
  `/volume1/docker/portal/rhhyun-initial-password.txt`; secrets and passwords
  are not printed to logs.
- 2026-06-19: DSM Task Scheduler update command remains:
  `cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-update-portal.sh`
- 2026-06-19: DSM one-time/on-demand identity command is:
  `cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh`
- 2026-06-19: Version-up status: yes. The visible Portal app version was bumped
  from `Ver 1.53` to `Ver 1.54` for the automatic identity setup change.
- 2026-06-19: Synology Docker fallback was hardened. `scripts/synology-start-portal.sh`
  now retries config/build/up from `/volume1/docker/portal` without
  `--env-file` when older `docker-compose` rejects that flag, and
  `scripts/synology-web-start.sh` now forwards `APP_BASIC_AUTH_USERS`,
  `APP_ADMIN_USER`, `PORTAL_AUTH_CHECK_SECRET`, `WIREGENE_AUTH_CHECK_SECRET`,
  and `PORTAL_AUTH_CHECK_URL` into Docker containers.
- 2026-06-19: NAS log showing only
  `Wiregene identity auto-configuration started` and
  `Updating portal source checkout at /volume1/docker/wiregene-portal` exposed
  a shell `set -e` bug in `scripts/synology-auto-wiregene-identity.sh`.
  `patch_compose_file` returned a non-zero status when a compose file was
  already compatible or missing, so the script exited before configuring env
  files. Fixed by returning `0` for those normal no-op cases, and also for
  the normal `AUTO_START=false` no-op restart path.
- 2026-06-19: Version-up status: yes. The visible Portal app version was bumped
  from `Ver 1.54` to `Ver 1.55` for the identity-script no-op return fix.
- 2026-06-20: Fixed Portal remote auth checks so `APP_BASIC_AUTH_USER` and
  `APP_BASIC_AUTH_USERS` environment credentials are accepted by
  `/api/auth/check` for authorized sites such as `protocol`. Before this fix,
  the admin panel displayed ENV accounts as having site access, but subsites
  using Portal auth-check could still reject the same ID.
- 2026-06-20: Version-up status: yes. The visible Portal app version was bumped
  from `Ver 1.56` to `Ver 1.57` for the ENV-account auth-check fix.
<!-- MANUAL-NOTES-END -->
