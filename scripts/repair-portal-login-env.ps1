param(
  [string]$Scope = "rhhyuns-projects",
  [string]$Project = "wiregene-portal",
  [ValidateSet("production", "preview", "development")]
  [string]$Environment = "production",
  [string[]]$Usernames = @("rhhyun", "wiregene"),
  [string]$Password,
  [switch]$GeneratePassword,
  [switch]$Redeploy,
  [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"

function Read-RequiredSecret {
  param(
    [string]$Name,
    [string]$Prompt
  )

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

function New-Base64UrlSecret {
  param([int]$Bytes = 24)

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
    return
  }

  Write-Host "Setting Portal Vercel $Environment env: $Key"
  $Value | & npx.cmd vercel@latest env add $Key $Environment --force --yes --scope $Scope | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "vercel env add failed for $Key"
  }
}

function Write-GeneratedCredentialFile {
  param(
    [string]$AppDir,
    [string[]]$LoginUsers,
    [string]$LoginPassword
  )

  $logDir = Join-Path $AppDir ".codex-logs"
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $path = Join-Path $logDir "portal-emergency-login-$timestamp.txt"
  $content = @(
    "Portal emergency Basic Auth credentials",
    "GeneratedAt=$(Get-Date -Format o)",
    "URL=https://portal.wiregene.com",
    "Users=$($LoginUsers -join ',')",
    "Password=$LoginPassword",
    "",
    "After login, rotate this password from Vercel env or rerun this script."
  )

  Set-Content -LiteralPath $path -Value $content -Encoding UTF8
  return $path
}

function Test-PortalLogin {
  param(
    [string]$Username,
    [string]$LoginPassword
  )

  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${Username}:${LoginPassword}"))
  $headers = @{ Authorization = "Basic $encoded" }

  for ($attempt = 1; $attempt -le 12; $attempt++) {
    try {
      $response = Invoke-WebRequest `
        -Uri "https://portal.wiregene.com/" `
        -Headers $headers `
        -UseBasicParsing `
        -TimeoutSec 30

      if ([int]$response.StatusCode -eq 200) {
        Write-Host "Portal Basic Auth verification succeeded for $Username."
        return
      }

      Write-Host "Portal Basic Auth verification returned HTTP $([int]$response.StatusCode). Retry $attempt/12."
    } catch [System.Net.WebException] {
      $webResponse = $_.Exception.Response
      if ($webResponse) {
        Write-Host "Portal Basic Auth verification returned HTTP $([int]$webResponse.StatusCode). Retry $attempt/12."
      } else {
        Write-Host "Portal Basic Auth verification failed: $($_.Exception.Message). Retry $attempt/12."
      }
    }

    Start-Sleep -Seconds 10
  }

  throw "Portal Basic Auth verification did not succeed after redeploy."
}

$appDir = Split-Path -Parent $PSScriptRoot
Set-Location $appDir

$loginUsers = $Usernames |
  ForEach-Object { $_.Trim() } |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
  Select-Object -Unique

if ($loginUsers.Count -eq 0) {
  throw "At least one login username is required."
}

foreach ($username in $loginUsers) {
  if ($username -match "[:,\s]") {
    throw "Username '$username' cannot contain colon, comma, or whitespace."
  }
}

$passwordValue = $Password
if ([string]::IsNullOrWhiteSpace($passwordValue)) {
  if ($GeneratePassword) {
    $passwordValue = New-Base64UrlSecret
  } else {
    $passwordValue = Read-RequiredSecret `
      -Name "PORTAL_LOGIN_PASSWORD" `
      -Prompt "Paste the emergency Portal login password to set for $($loginUsers -join ', ')"
  }
}

if ($passwordValue.Length -lt 16) {
  throw "Emergency Portal login password must be at least 16 characters."
}

$authUsers = ($loginUsers | ForEach-Object { "${_}:$passwordValue" }) -join ","
$adminUsers = $loginUsers -join ","
$credentialFile = ""

if ($GeneratePassword) {
  $credentialFile = Write-GeneratedCredentialFile `
    -AppDir $appDir `
    -LoginUsers $loginUsers `
    -LoginPassword $passwordValue
}

Write-Host "Linking Vercel project $Scope/$Project."
& npx.cmd vercel@latest link --yes --project $Project --scope $Scope | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "vercel link failed"
}

$envValues = [ordered]@{
  APP_BASE_URL = "https://portal.wiregene.com"
  WIREGENE_APP_MODE = "portal"
  APP_BASIC_AUTH_USERS = $authUsers
  WIREGENE_ADMIN_EMAILS = $adminUsers
  APP_ADMIN_USERS = $adminUsers
}

foreach ($entry in $envValues.GetEnumerator()) {
  Set-VercelEnvValue -Key $entry.Key -Value $entry.Value
}

Write-Host "Portal emergency login env repair completed for $Scope/$Project ($Environment)."
if ($credentialFile) {
  Write-Host "Generated emergency login credential file: $credentialFile"
}

if (-not $Redeploy) {
  Write-Host "Redeploy was not requested. Run again with -Redeploy before expecting production login to change."
  exit 0
}

Write-Host "Deploying Portal production so the new Basic Auth env is active."
& npx.cmd vercel@latest --prod --yes --scope $Scope | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "vercel production deploy failed"
}

if (-not $SkipVerify) {
  Test-PortalLogin -Username $loginUsers[0] -LoginPassword $passwordValue
}
