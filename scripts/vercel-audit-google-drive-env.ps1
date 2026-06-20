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

function Get-OutputText {
  param([object[]]$Output)

  return (@($Output | ForEach-Object { $_.ToString() }) -join "`n").Trim()
}

function Get-JsonObjectText {
  param([string]$Text)

  $start = $Text.IndexOf("{")
  $end = $Text.LastIndexOf("}")
  if ($start -lt 0 -or $end -le $start) {
    return ""
  }

  return $Text.Substring($start, $end - $start + 1)
}

function New-ApiErrorRow {
  param(
    [hashtable]$Project,
    [int]$ExitCode,
    [string]$Message
  )

  if ($Message.Length -gt 240) {
    $Message = $Message.Substring(0, 240) + "..."
  }

  return [pscustomobject]@{
    Project = $Project.Name
    Key = "(project env API)"
    Status = "api-error"
    Present = "unknown"
    Type = ""
    Decrypted = ""
    ValueLength = ""
    CreatedLocal = ""
    Note = "exit=$ExitCode; $Message"
  }
}

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

  $outputText = Get-OutputText $output
  $raw = Get-JsonObjectText $outputText

  if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
    New-ApiErrorRow -Project $project -ExitCode $exitCode -Message $outputText
    continue
  }

  try {
    $parsed = $raw | ConvertFrom-Json
  } catch {
    New-ApiErrorRow -Project $project -ExitCode $exitCode -Message "Could not parse Vercel API JSON: $($_.Exception.Message)"
    continue
  }

  if ($null -eq $parsed.envs) {
    New-ApiErrorRow -Project $project -ExitCode $exitCode -Message "Vercel API response did not contain an envs array: $raw"
    continue
  }

  $envs = $parsed.envs
  foreach ($key in $keys) {
    $envVar = @($envs | Where-Object { $_.key -eq $key }) | Select-Object -First 1
    if ($null -eq $envVar) {
      [pscustomobject]@{
        Project = $project.Name
        Key = $key
        Status = "missing"
        Present = $false
        Type = ""
        Decrypted = ""
        ValueLength = ""
        CreatedLocal = ""
        Note = ""
      }
      continue
    }

    [pscustomobject]@{
      Project = $project.Name
      Key = $key
      Status = "present"
      Present = $true
      Type = $envVar.type
      Decrypted = $envVar.decrypted
      ValueLength = ([string]$envVar.value).Length
      CreatedLocal = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$envVar.createdAt).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz")
      Note = ""
    }
  }
}

$rows | Format-Table -AutoSize
