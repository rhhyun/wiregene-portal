param(
  [string]$Scope = "rhhyuns-projects",
  [string]$Project = "wiregene-portal",
  [ValidateSet("production", "preview", "development")]
  [string]$Environment = "production",
  [string]$ClientId,
  [string]$ClientSecret,
  [string]$RefreshToken,
  [string]$FolderName = "Wiregene Portal",
  [string]$PortalAccountFileName = "portal-accounts.json",
  [switch]$SkipRedeploy,
  [switch]$SkipHealthCheck
)

$ErrorActionPreference = "Stop"

function Read-RequiredSecret {
  param(
    [string]$Name,
    [string]$CurrentValue,
    [string]$Prompt
  )

  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    return $CurrentValue.Trim()
  }

  $secure = Read-Host -AsSecureString $Prompt
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }

  if ([string]::IsNullOrWhiteSpace($plain)) {
    throw "Missing required value: $Name"
  }

  return $plain.Trim()
}

function Assert-NotPlaceholder {
  param(
    [string]$Name,
    [string]$Value
  )

  if ($Value -match 'your_|example|placeholder|changeme|TODO|xxx|<|>') {
    throw "$Name looks like a placeholder, not a real Google OAuth value."
  }
}

function Assert-GoogleOauthShape {
  param(
    [string]$ClientIdValue,
    [string]$ClientSecretValue,
    [string]$RefreshTokenValue
  )

  Assert-NotPlaceholder "GOOGLE_DRIVE_CLIENT_ID" $ClientIdValue
  Assert-NotPlaceholder "GOOGLE_DRIVE_CLIENT_SECRET" $ClientSecretValue
  Assert-NotPlaceholder "GOOGLE_DRIVE_REFRESH_TOKEN" $RefreshTokenValue

  if ($ClientIdValue -notmatch '^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$') {
    throw "GOOGLE_DRIVE_CLIENT_ID does not look like a Google OAuth client id ending in .apps.googleusercontent.com."
  }

  if ($ClientSecretValue.Length -lt 20) {
    throw "GOOGLE_DRIVE_CLIENT_SECRET is too short to be a real Google OAuth client secret."
  }

  if ($RefreshTokenValue.Length -lt 80) {
    throw "GOOGLE_DRIVE_REFRESH_TOKEN is too short to be a real Google refresh token."
  }
}

function Test-GoogleOauthRefresh {
  param(
    [string]$ClientIdValue,
    [string]$ClientSecretValue,
    [string]$RefreshTokenValue
  )

  Write-Host "Validating Google OAuth refresh token before touching Vercel."

  try {
    $response = Invoke-RestMethod `
      -Method Post `
      -Uri "https://oauth2.googleapis.com/token" `
      -ContentType "application/x-www-form-urlencoded" `
      -Body @{
        client_id = $ClientIdValue
        client_secret = $ClientSecretValue
        refresh_token = $RefreshTokenValue
        grant_type = "refresh_token"
      }
  } catch [System.Net.WebException] {
    $body = ""
    if ($_.Exception.Response) {
      $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
      $body = $reader.ReadToEnd()
    }

    throw "Google OAuth validation failed. The values were not uploaded to Vercel. Response: $body"
  }

  if (-not $response.access_token) {
    throw "Google OAuth validation did not return an access token. The values were not uploaded to Vercel."
  }

  Write-Host "Google OAuth validation succeeded. Access token value was not printed."
}

function New-Base64UrlSecret {
  $bytes = New-Object byte[] 32
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }

  return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

function Set-VercelEnvValue {
  param(
    [string]$Key,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return
  }

  Write-Host "Setting Portal Vercel $Environment env: $Key"
  $Value | & npx.cmd vercel@latest env add $Key $Environment --force --yes --scope $Scope | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "vercel env add failed for $Key"
  }
}

function Invoke-PortalStorageHealth {
  param([string]$HealthSecret)

  Write-Host "Checking Portal Google Drive storage health."

  try {
    $response = Invoke-WebRequest `
      -Uri "https://portal.wiregene.com/api/admin/storage-health" `
      -Headers @{ "x-wiregene-storage-health-secret" = $HealthSecret } `
      -UseBasicParsing `
      -TimeoutSec 60
  } catch [System.Net.WebException] {
    $webResponse = $_.Exception.Response
    if ($null -eq $webResponse) {
      throw
    }

    $reader = New-Object IO.StreamReader($webResponse.GetResponseStream())
    $body = $reader.ReadToEnd()
    throw "Portal storage health check failed with HTTP $([int]$webResponse.StatusCode): $body"
  }

  $payload = $response.Content | ConvertFrom-Json
  if ($payload.ok -ne $true) {
    throw "Portal storage health check returned ok=false: $($response.Content)"
  }

  Write-Host "Portal storage health check succeeded. accountCount=$($payload.accountCount)"
}

$appDir = Split-Path -Parent $PSScriptRoot
Set-Location $appDir

$clientIdValue = Read-RequiredSecret `
  -Name "GOOGLE_DRIVE_CLIENT_ID" `
  -CurrentValue $ClientId `
  -Prompt "Paste GOOGLE_DRIVE_CLIENT_ID"
$clientSecretValue = Read-RequiredSecret `
  -Name "GOOGLE_DRIVE_CLIENT_SECRET" `
  -CurrentValue $ClientSecret `
  -Prompt "Paste GOOGLE_DRIVE_CLIENT_SECRET"
$refreshTokenValue = Read-RequiredSecret `
  -Name "GOOGLE_DRIVE_REFRESH_TOKEN" `
  -CurrentValue $RefreshToken `
  -Prompt "Paste GOOGLE_DRIVE_REFRESH_TOKEN"

Assert-GoogleOauthShape `
  -ClientIdValue $clientIdValue `
  -ClientSecretValue $clientSecretValue `
  -RefreshTokenValue $refreshTokenValue
Test-GoogleOauthRefresh `
  -ClientIdValue $clientIdValue `
  -ClientSecretValue $clientSecretValue `
  -RefreshTokenValue $refreshTokenValue

$healthSecret = ""
if (-not $SkipHealthCheck) {
  $healthSecret = New-Base64UrlSecret
}

Write-Host "Linking Vercel project $Scope/$Project."
& npx.cmd vercel@latest link --yes --project $Project --scope $Scope | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "vercel link failed"
}

$envValues = [ordered]@{
  APP_BASE_URL = "https://portal.wiregene.com"
  WIREGENE_APP_MODE = "portal"
  PORTAL_ACCOUNT_STORAGE_BACKEND = "google-drive"
  PORTAL_ACCOUNT_STORAGE_PATH = ".data/portal/portal-accounts.json"
  PORTAL_ACCOUNT_STORAGE_PATH_DRIVE_FILENAME = $PortalAccountFileName
  GOOGLE_DRIVE_CLIENT_ID = $clientIdValue
  GOOGLE_DRIVE_CLIENT_SECRET = $clientSecretValue
  GOOGLE_DRIVE_REFRESH_TOKEN = $refreshTokenValue
  GOOGLE_DRIVE_FOLDER_NAME = $FolderName
}

if ($healthSecret) {
  $envValues["PORTAL_STORAGE_HEALTH_SECRET"] = $healthSecret
}

foreach ($entry in $envValues.GetEnumerator()) {
  Set-VercelEnvValue -Key $entry.Key -Value $entry.Value
}

Write-Host "Portal Google Drive OAuth env repair completed for $Scope/$Project ($Environment)."

if ($SkipRedeploy) {
  Write-Host "Redeploy skipped. Run Vercel production deploy before expecting the new env values to apply."
  exit 0
}

Write-Host "Deploying Portal production."
& npx.cmd vercel@latest --prod --yes --scope $Scope | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "vercel production deploy failed"
}

if (-not $SkipHealthCheck) {
  Invoke-PortalStorageHealth -HealthSecret $healthSecret
}

