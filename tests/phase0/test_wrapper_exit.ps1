# Unit-level check: wrapper must exit 0 when installer RC is 3010 and JSON carries exit_code.
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$wrapper = Join-Path $repo 'roles\mssql_patch\files\Invoke-MssqlPatch.ps1'
$tmp = Join-Path $env:TEMP ("mssql_phase0_wrapper_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $cmdShim = Join-Path $tmp 'fake-sql-patch.cmd'
  Set-Content -LiteralPath $cmdShim -Value "@echo off`r`nexit /b 3010" -Encoding ASCII

  $argsJson = '["/quiet","/IAcceptSQLServerLicenseTerms","/Action=Patch","/AllInstances","/norestart"]'
  $runner = Join-Path $tmp 'run-wrapper.ps1'
  @"
`$ErrorActionPreference = 'Stop'
& '$($wrapper.Replace("'", "''"))' ``
  -InstallerPath '$($cmdShim.Replace("'", "''"))' ``
  -ArgumentsJson '$($argsJson.Replace("'", "''"))' ``
  -EvidenceDir '$($tmp.Replace("'", "''"))' ``
  -KbId 'KB5041321' ``
  -RunId 'phase0' ``
  -HostName 'testhost'
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $runner -Encoding UTF8

  $outFile = Join-Path $tmp 'out.txt'
  $errFile = Join-Path $tmp 'err.txt'
  $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $runner) `
    -Wait -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile

  $stdout = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
  $stderr = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
  Write-Output "WRAPPER_PROCESS_EXIT=$($p.ExitCode)"
  Write-Output "STDOUT=$stdout"
  if ($stderr) { Write-Output "STDERR=$stderr" }

  if ($p.ExitCode -ne 0) {
    throw "Expected wrapper process exit 0 for captured installer RC 3010; got $($p.ExitCode)"
  }
  $jsonLine = ($stdout -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
  if (-not $jsonLine) { throw "No JSON object found in wrapper stdout" }
  $json = $jsonLine | ConvertFrom-Json
  if ([int]$json.exit_code -ne 3010) {
    throw "Expected JSON exit_code 3010; got $($json.exit_code)"
  }
  if (-not $json.ok) {
    throw "Expected JSON ok=true for captured installer result"
  }
  Write-Output 'WRAPPER_3010_OK'
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
