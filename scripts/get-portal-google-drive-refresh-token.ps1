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

$appDir = Split-Path -Parent $PSScriptRoot
Set-Location $appDir

$previousClientId = $env:GOOGLE_DRIVE_CLIENT_ID
$previousClientSecret = $env:GOOGLE_DRIVE_CLIENT_SECRET
$previousScopes = $env:GOOGLE_DRIVE_OAUTH_SCOPES

try {
  $env:GOOGLE_DRIVE_CLIENT_ID = Read-RequiredSecret `
    -Name "GOOGLE_DRIVE_CLIENT_ID" `
    -Prompt "Paste Portal GOOGLE_DRIVE_CLIENT_ID"
  $env:GOOGLE_DRIVE_CLIENT_SECRET = Read-RequiredSecret `
    -Name "GOOGLE_DRIVE_CLIENT_SECRET" `
    -Prompt "Paste Portal GOOGLE_DRIVE_CLIENT_SECRET"
  $env:GOOGLE_DRIVE_OAUTH_SCOPES = "https://www.googleapis.com/auth/drive.file"

  Write-Host "Starting Portal Google Drive refresh token flow. Secret values will not be printed by this wrapper."
  Write-Host "The OAuth script will print a browser URL. Open it, approve access, then copy the generated GOOGLE_DRIVE_REFRESH_TOKEN from this terminal."
  npm.cmd run google-drive:oauth
  if ($LASTEXITCODE -ne 0) {
    throw "google-drive:oauth failed"
  }
} finally {
  $env:GOOGLE_DRIVE_CLIENT_ID = $previousClientId
  $env:GOOGLE_DRIVE_CLIENT_SECRET = $previousClientSecret
  $env:GOOGLE_DRIVE_OAUTH_SCOPES = $previousScopes
}
