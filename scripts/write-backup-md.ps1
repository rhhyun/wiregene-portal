param(
  [string]$AppDir = (Split-Path -Parent $PSScriptRoot),
  [string]$BackupPath
)

$ErrorActionPreference = "Stop"

if (-not $BackupPath) {
  $BackupPath = Join-Path $AppDir "backup.md"
}

function Invoke-GitText {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GitArgs
  )

  try {
    $output = & git -C $AppDir @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
      return ""
    }

    return ($output -join "`n").Trim()
  } catch {
    return ""
  }
}

function Read-CurrentVersion {
  $versionFile = Join-Path $AppDir "src/lib/version.ts"
  if (-not (Test-Path -LiteralPath $versionFile)) {
    return "unknown"
  }

  $text = Get-Content -LiteralPath $versionFile -Raw
  $match = [regex]::Match($text, 'export\s+const\s+BRIEFING_VERSION\s*=\s*"([^"]+)"')
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return "unknown"
}

function Get-FilteredStatus {
  $status = Invoke-GitText status --short
  if (-not $status) {
    return "(clean or unavailable)"
  }

  $lines = $status -split "`n" | Where-Object {
    $line = $_.TrimEnd()
    $line -and ($line -notmatch '\.env') -and ($line -notmatch 'backup\.md$')
  }

  if (-not $lines -or $lines.Count -eq 0) {
    return "(clean after omitting env-like paths and backup.md)"
  }

  return ($lines -join "`n")
}

function Get-ManualNotes {
  if (-not (Test-Path -LiteralPath $BackupPath)) {
    return "Add handoff notes here when a task has context that is not captured by git status."
  }

  $text = Get-Content -LiteralPath $BackupPath -Raw
  $match = [regex]::Match(
    $text,
    '(?s)<!-- MANUAL-NOTES-START -->\s*(.*?)\s*<!-- MANUAL-NOTES-END -->'
  )

  if ($match.Success -and $match.Groups[1].Value.Trim()) {
    return $match.Groups[1].Value.Trim()
  }

  return "Add handoff notes here when a task has context that is not captured by git status."
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"
$version = Read-CurrentVersion
$branch = Invoke-GitText rev-parse --abbrev-ref HEAD
$commit = Invoke-GitText log -1 --oneline
$remote = Invoke-GitText remote get-url origin
$status = Get-FilteredStatus
$manualNotes = Get-ManualNotes

if (-not $branch) { $branch = "unknown" }
if (-not $commit) { $commit = "unknown" }
if (-not $remote) { $remote = "unknown" }

$template = @'
# Wiregene Work Backup

Generated: __GENERATED_AT__

This file is a safe handoff note for continuing the project on another PC.
Do not store passwords, tokens, API keys, cookies, or private environment
values in this file.

## Current Repository

- Repository: wiregene-portal
- Remote: __REMOTE__
- Branch: __BRANCH__
- Latest known commit: __COMMIT__
- App version: Ver __VERSION__

## Git Status At Generation

Env-like paths and backup.md are intentionally omitted from this section.

```text
__STATUS__
```

## Active Work Summary

- `portal.wiregene.com` is the Wiregene account and site launcher service.
- ID/PW add, delete, and change operations are managed from
  `portal.wiregene.com`; `APP_BASIC_AUTH_*` values are reserved for
  break-glass/bootstrap access.
- Portal account ID storage is intended to run on Synology with
  `PORTAL_ACCOUNT_STORAGE_BACKEND=local-json`.
- Google Drive is a backup mirror only, enabled with
  `PORTAL_ACCOUNT_GOOGLE_DRIVE_BACKUP=true`. Vercel is emergency/temporary
  access and must not be the long-term ID/PW source of truth.
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
  headers. Keep Vercel only as emergency/temporary access; production ID/PW
  storage belongs on Synology local JSON with Google Drive backup mirroring.

## Manual Handoff Notes

<!-- MANUAL-NOTES-START -->
__MANUAL_NOTES__
<!-- MANUAL-NOTES-END -->
'@

$content = $template.
  Replace("__GENERATED_AT__", $generatedAt).
  Replace("__REMOTE__", $remote).
  Replace("__BRANCH__", $branch).
  Replace("__COMMIT__", $commit).
  Replace("__VERSION__", $version).
  Replace("__STATUS__", $status).
  Replace("__MANUAL_NOTES__", $manualNotes)

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($BackupPath, $content, $utf8NoBom)
Write-Host "Wrote $BackupPath"
