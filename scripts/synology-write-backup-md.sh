#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=${APP_DIR:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
BACKUP_PATH=${BACKUP_PATH:-"$APP_DIR/backup.md"}
TMP_PATH="$BACKUP_PATH.tmp.$$"

git_text() {
  if command -v git >/dev/null 2>&1; then
    git -C "$APP_DIR" "$@" 2>/dev/null || true
  fi
}

read_version() {
  version_file="$APP_DIR/src/lib/version.ts"
  if [ -f "$version_file" ]; then
    sed -n 's/^export const BRIEFING_VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$version_file" | sed -n '1p'
  fi
}

read_manual_notes() {
  if [ -f "$BACKUP_PATH" ]; then
    awk '
      /<!-- MANUAL-NOTES-START -->/ {flag=1; next}
      /<!-- MANUAL-NOTES-END -->/ {flag=0}
      flag {print}
    ' "$BACKUP_PATH"
  fi
}

generated_at=$(date '+%Y-%m-%d %H:%M:%S %z')
version=$(read_version)
branch=$(git_text rev-parse --abbrev-ref HEAD | sed -n '1p')
commit=$(git_text log -1 --oneline | sed -n '1p')
remote=$(git_text remote get-url origin | sed -n '1p')
status=$(git_text status --short | grep -v '[.]env' | grep -v 'backup[.]md$' || true)
manual_notes=$(read_manual_notes)

[ -n "$version" ] || version="unknown"
[ -n "$branch" ] || branch="unknown"
[ -n "$commit" ] || commit="unknown"
[ -n "$remote" ] || remote="unknown"
[ -n "$status" ] || status="(clean after omitting env-like paths and backup.md)"
[ -n "$manual_notes" ] || manual_notes="Add handoff notes here when a task has context that is not captured by git status."

cat > "$TMP_PATH" <<EOF
# Wiregene Work Backup

Generated: $generated_at

This file is a safe handoff note for continuing the project on another PC.
Do not store passwords, tokens, API keys, cookies, or private environment
values in this file.

## Current Repository

- Repository: wiregene-portal
- Remote: $remote
- Branch: $branch
- Latest known commit: $commit
- App version: Ver $version

## Git Status At Generation

Env-like paths and backup.md are intentionally omitted from this section.

\`\`\`text
$status
\`\`\`

## Active Work Summary

- \`portal.wiregene.com\` is the Wiregene account and site launcher service.
- ID/PW add, delete, and change operations are managed from
  \`portal.wiregene.com\`; \`APP_BASIC_AUTH_*\` values are reserved for
  break-glass/bootstrap access.
- Portal account ID storage is intended to run on Synology with
  \`PORTAL_ACCOUNT_STORAGE_BACKEND=local-json\`.
- Google Drive is a backup mirror only, enabled with
  \`PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP=true\`. Vercel is emergency/temporary
  access and must not be the long-term ID/PW source of truth.
- The Synology update script checks local container readiness, rendered version,
  and whether the public portal host is still returning Vercel headers. The
  public route check warns by default and only fails when
  \`PUBLIC_PORTAL_ROUTE_POLICY=synology\`.
- Synology source checkout: \`/volume1/docker/wiregene-portal\`.
- Synology runtime folder: \`/volume1/docker/portal\`.
- This backup file can be regenerated at the end of each work session.

## Continue On Another PC

\`\`\`powershell
cd C:\\Users\\rhhyu\\Documents\\Portal.wiregene.com
git pull --ff-only origin main
npm.cmd install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\write-backup-md.ps1
\`\`\`

Then inspect \`backup.md\`, run the needed verification commands, and continue
from the latest commit.

## Synology Commands

\`\`\`sh
APP_DIR=/volume1/docker/wiregene-portal
REPO_URL=https://github.com/rhhyun/wiregene-portal.git
if [ ! -d "\$APP_DIR/.git" ]; then
  if [ -e "\$APP_DIR" ]; then
    echo "ERROR: \$APP_DIR exists but is not a Git checkout."
    echo "Move it aside or set APP_DIR to the real checkout path."
    exit 1
  fi
  git clone "\$REPO_URL" "\$APP_DIR"
fi
git -C "\$APP_DIR" pull --ff-only origin main
/bin/sh "\$APP_DIR/scripts/synology-write-backup-md.sh"
/bin/sh "\$APP_DIR/scripts/synology-update-portal.sh"
\`\`\`

One-time or on-demand automatic identity setup:

\`\`\`sh
cd /volume1/docker/wiregene-portal && git pull --ff-only origin main && /bin/sh /volume1/docker/wiregene-portal/scripts/synology-auto-wiregene-identity.sh
\`\`\`

The Synology backup writer updates this file locally. To make the updated
handoff visible on other PCs, commit and push \`backup.md\` from a trusted
development machine after reviewing it.

## Important Files

- \`backup.md\`: latest handoff snapshot.
- \`scripts/write-backup-md.ps1\`: Windows backup writer.
- \`scripts/synology-write-backup-md.sh\`: Synology backup writer.
- \`docs/synology-meta-portal-split.md\`: transition NAS layout and scheduler notes.
- \`scripts/synology-update-portal.sh\`: full Synology update, build, restart,
  local health check, version check, and public route check.
- \`scripts/synology-auto-wiregene-identity.sh\`: automatic identity/admin/shared
  auth secret setup for Portal and known subsite env files, with \`wiregene\`
  scoped to \`search\` unless explicitly changed.
- \`scripts/synology-start-portal.sh\`: Synology container build/restart helper.
- \`synology/docker/portal/.env.example\`: runtime environment template.
- \`src/lib/version.ts\`: visible application version.

## Verification Checklist

- \`npm.cmd run lint -- --max-warnings=0\`
- \`npx.cmd tsc --noEmit --pretty false --incremental false\`
- \`npm.cmd run build\`
- On Synology, syntax-check shell scripts with \`sh -n scripts/<name>.sh\`.
- If public Portal is intended to run from Synology, confirm
  \`portal.wiregene.com\` does not return \`Server: Vercel\` or \`X-Vercel-Id\`
  headers. Keep Vercel only as emergency/temporary access; production ID/PW
  storage belongs on Synology local JSON with Google Drive backup mirroring.

## Manual Handoff Notes

<!-- MANUAL-NOTES-START -->
$manual_notes
<!-- MANUAL-NOTES-END -->
EOF

mv "$TMP_PATH" "$BACKUP_PATH"
echo "Wrote $BACKUP_PATH"
