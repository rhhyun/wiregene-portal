param(
  [string]$SourceEnvPath = "C:\Users\rhhyu\Documents\GitHub\research-briefing-platform\.env.local",
  [string]$PortalEnvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) ".env.local"),
  [string]$Scope = "rhhyuns-projects",
  [string]$Project = "wiregene-portal",
  [ValidateSet("production", "preview", "development")]
  [string]$Environment = "production",
  [switch]$Redeploy
)

$ErrorActionPreference = "Stop"

function Read-DotEnvFile {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path -LiteralPath $Path)) {
    return $values
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (-not $trimmed -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
      continue
    }

    $parts = $trimmed -split "=", 2
    $key = $parts[0].Trim()
    $value = $parts[1]
    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    $values[$key] = $value
  }

  return $values
}

function Get-RequiredValue {
  param(
    [hashtable]$Values,
    [string]$Key
  )

  $value = $Values[$Key]
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Missing required Google Drive value: $Key in $SourceEnvPath"
  }

  return $value
}

function Add-VercelEnv {
  param(
    [string]$Key,
    [string]$Value
  )

  if ($null -eq $Value) {
    return
  }

  Write-Host "Setting Vercel $Environment env: $Key"
  & npx.cmd vercel@latest env add $Key $Environment --force --yes --value $Value --scope $Scope | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "vercel env add failed for $Key"
  }
}

$appDir = Split-Path -Parent $PSScriptRoot
Set-Location $appDir

Write-Host "Linking Vercel project $Scope/$Project"
& npx.cmd vercel@latest link --yes --project $Project --scope $Scope | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "vercel link failed"
}

$sourceEnv = Read-DotEnvFile $SourceEnvPath
$portalEnv = Read-DotEnvFile $PortalEnvPath

$clientId = Get-RequiredValue $sourceEnv "GOOGLE_DRIVE_CLIENT_ID"
$clientSecret = Get-RequiredValue $sourceEnv "GOOGLE_DRIVE_CLIENT_SECRET"
$refreshToken = Get-RequiredValue $sourceEnv "GOOGLE_DRIVE_REFRESH_TOKEN"

$envValues = [ordered]@{
  APP_BASE_URL = "https://portal.wiregene.com"
  WIREGENE_APP_MODE = "portal"
  PORTAL_ACCOUNT_STORAGE_BACKEND = "google-drive"
  PORTAL_ACCOUNT_STORAGE_PATH = ".data/portal/portal-accounts.json"
  PORTAL_ACCOUNT_STORAGE_PATH_DRIVE_FILENAME = "portal-accounts.json"
  GOOGLE_DRIVE_CLIENT_ID = $clientId
  GOOGLE_DRIVE_CLIENT_SECRET = $clientSecret
  GOOGLE_DRIVE_REFRESH_TOKEN = $refreshToken
  GOOGLE_DRIVE_FOLDER_ID = $sourceEnv["GOOGLE_DRIVE_FOLDER_ID"]
  GOOGLE_DRIVE_FOLDER_URL = $sourceEnv["GOOGLE_DRIVE_FOLDER_URL"]
  GOOGLE_DRIVE_FOLDER_NAME = if ($sourceEnv["GOOGLE_DRIVE_FOLDER_NAME"]) { $sourceEnv["GOOGLE_DRIVE_FOLDER_NAME"] } else { "Research Briefing Platform" }
}

foreach ($key in @(
  "APP_BASIC_AUTH_USER",
  "APP_BASIC_AUTH_PASSWORD",
  "APP_BASIC_AUTH_USERS",
  "WIREGENE_ADMIN_EMAILS",
  "PORTAL_AUTH_CHECK_SECRET",
  "PORTAL_AUTH_CHECK_URL"
)) {
  if (-not [string]::IsNullOrWhiteSpace($portalEnv[$key])) {
    $envValues[$key] = $portalEnv[$key]
  }
}

foreach ($entry in $envValues.GetEnumerator()) {
  if (-not [string]::IsNullOrWhiteSpace($entry.Value)) {
    Add-VercelEnv $entry.Key $entry.Value
  }
}

Write-Host "Vercel env setup completed for $Scope/$Project ($Environment)."

if ($Redeploy) {
  Write-Host "Deploying $Scope/$Project to production."
  & npx.cmd vercel@latest --prod --yes --scope $Scope | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "vercel production deploy failed"
  }
}
else {
  Write-Host "Redeploy was not requested. Run again with -Redeploy to apply the new env values to production."
}
