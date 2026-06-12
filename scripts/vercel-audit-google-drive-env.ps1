param(
  [string]$Scope = "rhhyuns-projects"
)

$ErrorActionPreference = "Stop"

$projects = @(
  @{
    Name = "Portal"
    Id = "prj_WlEhHme2pSN7n3UGjQN1VEB7SFcE"
  },
  @{
    Name = "Search"
    Id = "prj_kSrYcLZ6MsoNe8cATzclLyl6jqPa"
  },
  @{
    Name = "Meta"
    Id = "prj_mecTl3vq12v4PejhAsTxF5EMiiWB"
  }
)

$keys = @(
  "GOOGLE_DRIVE_CLIENT_ID",
  "GOOGLE_DRIVE_CLIENT_SECRET",
  "GOOGLE_DRIVE_REFRESH_TOKEN",
  "GOOGLE_DRIVE_FOLDER_NAME",
  "GOOGLE_DRIVE_DATABASE_FILENAME",
  "GOOGLE_DRIVE_DATABASE_FILE_ID",
  "PORTAL_ACCOUNT_STORAGE_BACKEND",
  "PORTAL_ACCOUNT_STORAGE_PATH_DRIVE_FILENAME"
)

Write-Host "Auditing Vercel Google Drive env metadata for scope '$Scope'."
Write-Host "Sensitive values are intentionally not printed. valueLength=0 with decrypted=false means Vercel hid the value; it does not prove the env value is empty."

$rows = foreach ($project in $projects) {
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & npx.cmd vercel@latest api "/v10/projects/$($project.Id)/env" --scope $Scope --raw 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  $raw = @($output | ForEach-Object { $_.ToString() }) |
    Where-Object { $_.Trim().StartsWith("{") -and $_ -match '"envs"' } |
    Select-Object -First 1

  if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
    foreach ($key in $keys) {
      [pscustomobject]@{
        Project = $project.Name
        Key = $key
        Present = $false
        Type = ""
        Decrypted = ""
        ValueLength = ""
        CreatedLocal = ""
      }
    }
    continue
  }

  $envs = ($raw | ConvertFrom-Json).envs
  foreach ($key in $keys) {
    $envVar = @($envs | Where-Object { $_.key -eq $key }) | Select-Object -First 1
    if ($null -eq $envVar) {
      [pscustomobject]@{
        Project = $project.Name
        Key = $key
        Present = $false
        Type = ""
        Decrypted = ""
        ValueLength = ""
        CreatedLocal = ""
      }
      continue
    }

    [pscustomobject]@{
      Project = $project.Name
      Key = $key
      Present = $true
      Type = $envVar.type
      Decrypted = $envVar.decrypted
      ValueLength = ([string]$envVar.value).Length
      CreatedLocal = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$envVar.createdAt).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz")
    }
  }
}

$rows | Format-Table -AutoSize
