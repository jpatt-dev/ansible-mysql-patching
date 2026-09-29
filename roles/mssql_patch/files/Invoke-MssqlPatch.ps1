<#
.SYNOPSIS
  Execute a staged SQL Server patch installer and return compact JSON for Ansible.
.DESCRIPTION
  Requires /norestart. Writes stdout/stderr to evidence files; JSON returns paths only.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InstallerPath,

  [Parameter(Mandatory = $true)]
  [string]$ArgumentsJson,

  [Parameter(Mandatory = $true)]
  [string]$EvidenceDir,

  [Parameter(Mandatory = $false)]
  [string]$KbId = "",

  [Parameter(Mandatory = $false)]
  [string]$RunId = "",

  [Parameter(Mandatory = $false)]
  [string]$HostName = ""
)

$ErrorActionPreference = 'Stop'
$started = (Get-Date).ToUniversalTime().ToString('o')
$safeKb = if ($KbId) { $KbId } else { 'nokb' }
$safeRun = if ($RunId) { $RunId } else { (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss') }
$safeHost = if ($HostName) { $HostName } else { $env:COMPUTERNAME }
$tag = "$safeHost-$safeKb-$safeRun"

$result = [ordered]@{
  ok               = $false
  exit_code        = 1
  started_at       = $started
  ended_at         = $null
  duration_seconds = 0
  installer_path   = $InstallerPath
  kb_id            = $KbId
  run_id           = $safeRun
  arguments        = @()
  stdout_path      = $null
  stderr_path      = $null
  setup_log_paths  = @()
  evidence_paths   = @()
  error            = $null
}

try {
  if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "Installer not found: $InstallerPath"
  }
  if (-not (Test-Path -LiteralPath $EvidenceDir)) {
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
  }

  $arguments = @()
  if ($ArgumentsJson -and $ArgumentsJson.Trim().Length -gt 0) {
    $arguments = $ArgumentsJson | ConvertFrom-Json
    if ($arguments -isnot [System.Array]) {
      $arguments = @($arguments)
    }
  }
  $result.arguments = @($arguments)

  $joined = ($arguments -join ' ').ToLowerInvariant()
  if ($joined -notmatch '/norestart' -and $joined -notmatch '/forcerestart=0') {
    throw "Refusing to execute installer without /norestart."
  }

  $stdoutPath = Join-Path $EvidenceDir "installer-stdout-$tag.txt"
  $stderrPath = Join-Path $EvidenceDir "installer-stderr-$tag.txt"
  $result.stdout_path = $stdoutPath
  $result.stderr_path = $stderrPath

  $proc = Start-Process -FilePath $InstallerPath -ArgumentList @($arguments) -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

  $result.exit_code = [int]$proc.ExitCode
  $result.ok = $true
  $result.evidence_paths = @($stdoutPath, $stderrPath)

  $bootstrapRoot = 'C:\Program Files\Microsoft SQL Server'
  if (Test-Path $bootstrapRoot) {
    $summaries = Get-ChildItem -Path $bootstrapRoot -Recurse -Filter 'Summary*.txt' -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddHours(-6) } |
      Sort-Object LastWriteTimeUtc -Descending |
      Select-Object -First 5
    $summaryIndex = 0
    foreach ($s in $summaries) {
      $summaryIndex++
      $parentSafe = ($s.Directory.Name -replace '[^A-Za-z0-9._-]', '_')
      $destName = "setup-$tag-$summaryIndex-$parentSafe-$($s.Name)"
      $dest = Join-Path $EvidenceDir $destName
      Copy-Item -LiteralPath $s.FullName -Destination $dest -Force -ErrorAction SilentlyContinue
      $result.setup_log_paths += $s.FullName
      $result.evidence_paths += $dest
    }
  }
}
catch {
  $result.error = $_.Exception.Message
  $result.exit_code = 1
  $result.ok = $false
}
finally {
  $ended = (Get-Date).ToUniversalTime()
  $result.ended_at = $ended.ToString('o')
  try {
    $startDt = [datetime]::Parse($started).ToUniversalTime()
    $result.duration_seconds = [math]::Round(($ended - $startDt).TotalSeconds, 1)
  } catch {
    $result.duration_seconds = 0
  }
  $result | ConvertTo-Json -Compress -Depth 6
  if (-not $result.ok) { exit 1 }
  exit ([int]$result.exit_code)
}
