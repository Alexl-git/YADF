# Runs the ENTIRE YADF test suite: every Test\test_*.ps1 script, with a
# summary table and an aggregate exit code. This is the single entry point
# to run before a release or after any engine change.
#
# Usage:
#   pwsh Test\run_tests.ps1
#
# Per-script exit-code convention:  0 = pass, 2 = skip (missing prebuilt
# exe -- GuardTest/OptionsTest), anything else = fail.
# Driver exit code: 0 = no failures (skips allowed), 1 = any failure.
$ErrorActionPreference = 'Stop'

# The formatter exe every script depends on: fail fast, loudly, if it is
# missing or stale relative to the engine sources (the classic trap: tests
# silently exercising an old build).
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
if (-not (Test-Path $exe)) {
  Write-Output "run_tests: FATAL -- no exe at $exe"
  Write-Output "  build first:  msbuild /t:Build /p:Config=Debug /p:Platform=Win64 YADF.dproj"
  exit 1
}
$exeTime = (Get-Item $exe).LastWriteTime
$newer = Get-ChildItem (Join-Path $PSScriptRoot '..') -Filter 'YADF*.pas' |
         Where-Object { $_.LastWriteTime -gt $exeTime }
if ($newer) {
  Write-Output ("run_tests: WARNING -- YADF.exe ({0:yyyy-MM-dd HH:mm}) is OLDER than: {1}" -f $exeTime, (($newer | ForEach-Object Name) -join ', '))
  Write-Output "  results below may reflect a stale build."
}

$results = @()
$fail = 0
Get-ChildItem $PSScriptRoot -Filter 'test_*.ps1' | Sort-Object Name | ForEach-Object {
  $sw  = [Diagnostics.Stopwatch]::StartNew()
  $out = & pwsh -NoProfile -File $_.FullName 2>&1 | Select-Object -Last 1
  $code = $LASTEXITCODE
  $sw.Stop()
  $status = switch ($code) { 0 { 'PASS' } 2 { 'SKIP' } default { 'FAIL' } }
  if ($status -eq 'FAIL') { $fail++ }
  $results += [pscustomobject]@{
    Script = $_.BaseName -replace '^test_', ''
    Status = $status
    Secs   = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Detail = "$out"
  }
}

$results | Format-Table Script, Status, Secs, Detail -AutoSize | Out-String -Width 200 | Write-Output
$pass = ($results | Where-Object Status -eq 'PASS').Count
$skip = ($results | Where-Object Status -eq 'SKIP').Count
Write-Output ("run_tests: {0} passed, {1} failed, {2} skipped" -f $pass, $fail, $skip)
if ($fail -eq 0) { exit 0 } else { exit 1 }
