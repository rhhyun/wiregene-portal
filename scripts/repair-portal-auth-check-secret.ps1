param(
  [string]$Scope = "rhhyuns-projects",
  [string]$Project = "wiregene-portal",
  [ValidateSet("production", "preview", "development")]
  [string]$Environment = "production",
  [string]$Secret,
  [switch]$Redeploy,
  [string]$HomepageAppDir = "/volume1/docker/wiregene-homepage",
  [string]$HomepageDeployKey = "/var/services/homes/rhhyun/.ssh/wiregene_homepage_github"
)

$ErrorActionPreference = "Stop"

function New-Base64UrlSecret {
  param([int]$Bytes = 32)

  $bytesValue = New-Object byte[] $Bytes
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytesValue)
  } finally {
    $rng.Dispose()
  }

  return [Convert]::ToBase64String($bytesValue).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Set-VercelEnvValue {
  param(
    [string]$Key,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Cannot set empty Vercel env value for $Key"
  }

  Write-Host "Setting Portal Vercel $Environment env: $Key"
  $Value | & npx.cmd vercel@latest env add $Key $Environment --force --yes --scope $Scope | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "vercel env add failed for $Key"
  }
}

function Write-DotEnvValue {
  param(
    [string]$Path,
    [string]$Key,
    [string]$Value
  )

  $lines = @()
  if (Test-Path -LiteralPath $Path) {
    $lines = @(Get-Content -LiteralPath $Path)
  }

  $found = $false
  $next = foreach ($line in $lines) {
    if ($line -match "^\s*(export\s+)?$([regex]::Escape($Key))=") {
      $found = $true
      "$Key=$Value"
    } else {
      $line
    }
  }

  if (-not $found) {
    $next += "$Key=$Value"
  }

  Set-Content -LiteralPath $Path -Value $next -Encoding UTF8
}

$appDir = Split-Path -Parent $PSScriptRoot
Set-Location $appDir

if ([string]::IsNullOrWhiteSpace($Secret)) {
  $Secret = New-Base64UrlSecret
}

if ($Secret.Length -lt 32) {
  throw "PORTAL_AUTH_CHECK_SECRET must be at least 32 characters."
}

Write-Host "Linking Vercel project $Scope/$Project."
& npx.cmd vercel@latest link --yes --project $Project --scope $Scope | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "vercel link failed"
}

Set-VercelEnvValue -Key "PORTAL_AUTH_CHECK_SECRET" -Value $Secret
Set-VercelEnvValue -Key "WIREGENE_AUTH_CHECK_SECRET" -Value $Secret
Set-VercelEnvValue -Key "PORTAL_AUTH_CHECK_URL" -Value "https://portal.wiregene.com/api/auth/check"

$localEnvPath = Join-Path $appDir ".env.local"
Write-DotEnvValue -Path $localEnvPath -Key "PORTAL_AUTH_CHECK_SECRET" -Value $Secret
Write-DotEnvValue -Path $localEnvPath -Key "WIREGENE_AUTH_CHECK_SECRET" -Value $Secret
Write-DotEnvValue -Path $localEnvPath -Key "PORTAL_AUTH_CHECK_URL" -Value "https://portal.wiregene.com/api/auth/check"

$logDir = Join-Path $appDir ".codex-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$commandPath = Join-Path $logDir "synology-homepage-auth-check-secret-$timestamp.sh"

$synologyCommand = @"
set -eu
APP_DIR=$HomepageAppDir
DEPLOY_KEY=$HomepageDeployKey
PORTAL_AUTH_CHECK_SECRET='$Secret'

cd "`$APP_DIR" || exit 1
git config --global --add safe.directory "`$APP_DIR"
chmod 600 "`$DEPLOY_KEY" 2>/dev/null || true
git remote set-url origin git@github.com:rhhyun/wiregene-homepage.git 2>/dev/null || true

export GIT_SSH_COMMAND="ssh -i `$DEPLOY_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
git pull --ff-only origin main

PORTAL_AUTH_CHECK_SECRET="`$PORTAL_AUTH_CHECK_SECRET" WIREGENE_AUTH_CHECK_SECRET="`$PORTAL_AUTH_CHECK_SECRET" PORTAL_AUTH_CHECK_URL="https://portal.wiregene.com/api/auth/check" DEPLOY_KEY="`$DEPLOY_KEY" /bin/sh scripts/synology-start-homepage.sh
/bin/sh scripts/synology-diagnose-homepage.sh
/bin/sh scripts/synology-check-homepage.sh
"@

Set-Content -LiteralPath $commandPath -Value $synologyCommand -Encoding UTF8

Write-Host "Portal auth-check secret was configured locally and in Vercel."
Write-Host "Synology homepage command was written to: $commandPath"
Write-Host "Do not commit .env.local or .codex-logs files."

if ($Redeploy) {
  Write-Host "Deploying Portal production so the new auth-check secret is active."
  & npx.cmd vercel@latest --prod --yes --scope $Scope | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "vercel production deploy failed"
  }
}
else {
  Write-Host "Redeploy was not requested. Run again with -Redeploy before expecting production auth-check to change."
}
