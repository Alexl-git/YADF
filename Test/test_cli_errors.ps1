# CLI error-handling tests. Unknown --flags must be rejected with a clear
# "unknown option" error and a nonzero exit code -- NOT silently treated as
# file specs (the old behavior turned a typo like --max-length into a
# confusing "no .pas files matched" / stray-file run). The positional mode
# flags (--check, --check-dir, --batch, --debug-tree) are parsed after
# ParseFlags and must keep working. Exit 0 = all pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$ini = Join-Path $PSScriptRoot '..\yadf.ini'
$fail = 0

if (-not (Test-Path $exe)) { Write-Output "cli_errors: SKIP (no exe at $exe)"; exit 2 }

# Work on a temp copy only -- never format repo fixtures in place.
$tmpDir = Join-Path $env:TEMP ("yadf_cli_errors_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$src = Join-Path $tmpDir 'input.pas'
Copy-Item (Join-Path $PSScriptRoot 'Cases\case_labels.pas') $src

function MustMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -notmatch $rx) { $script:fail++; Write-Output "FAIL [$label]: expected /$rx/ in: $out" }
}

try {
  # ----- unknown flag: clear error, nonzero exit, file untouched -----
  $before = (Get-FileHash $src).Hash
  $out = & $exe --ini $ini --no-such-flag $src 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { $fail++; Write-Output "FAIL [unknown-flag exit]: expected nonzero, got 0" }
  MustMatch $out 'unknown option --no-such-flag' 'unknown-flag message'
  if ((Get-FileHash $src).Hash -ne $before) { $fail++; Write-Output "FAIL [unknown-flag]: input file was modified" }

  # ----- typo'd value flag: same treatment, value arg not eaten as a file -----
  $out = & $exe --ini $ini --max-length 100 $src 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { $fail++; Write-Output "FAIL [typo-flag exit]: expected nonzero, got 0" }
  MustMatch $out 'unknown option --max-length' 'typo-flag message'

  # ----- mode flags still pass through ParseFlags -----
  $fmt = Join-Path $tmpDir 'formatted.pas'
  & $exe --ini $ini $src --o $fmt | Out-Null
  if ($LASTEXITCODE -ne 0) { $fail++; Write-Output "FAIL [format setup]: exit $LASTEXITCODE" }
  $chk = & $exe --ini $ini --check $fmt 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { $fail++; Write-Output "FAIL [--check exit]: expected 0, got $LASTEXITCODE" }
  MustMatch $chk 'PASS' '--check still works'
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Output "cli_errors: PASS"; exit 0 }
else { Write-Output "cli_errors: $fail FAILED"; exit 1 }
