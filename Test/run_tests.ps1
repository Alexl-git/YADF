# Runs the ENTIRE YADF test suite: every Test\test_*.ps1 script, with a
# summary table and an aggregate exit code. This is the single entry point
# to run before a release or after any engine change.
#
# Usage:
#   pwsh Test\run_tests.ps1
#
# Per-script exit-code convention:  0 = pass, 2 = skip (missing prebuilt
# exe -- GuardTest/OptionsTest), anything else = fail. Note that a SKIP from
# those two is NOT tolerated: this driver pre-checks both console runners and
# counts a missing/stale one as a failure (see below).
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

# The two prebuilt CONSOLE runners get the same treatment -- harder, in fact.
# Their suites exit 2 = SKIP when the exe is missing, and a skipped guard test
# is indistinguishable from a passing one in the summary table. That is how
# GuardTest.exe sat at 2026-07-17 through nine commits to YADF.Guard.pas, and
# how OptionsTest's EXPECTED_OPTION_COUNT invariant drifted by four options
# unnoticed for a month. Missing OR stale is a FAILURE here, not a warning.
$srcFiles = Get-ChildItem (Join-Path $PSScriptRoot '..') -Filter 'YADF*.pas'
$runnerFail = 0
foreach ($r in @(
    @{ Name = 'GuardTest';   Dpr = 'GuardTest.dpr'   },
    @{ Name = 'OptionsTest'; Dpr = 'OptionsTest.dpr' })) {
  $rexe  = Join-Path $PSScriptRoot ('Win32\Debug\EXE\' + $r.Name + '.exe')
  $rdpr  = Join-Path $PSScriptRoot $r.Dpr
  $build = "  build first:  msbuild /t:Build /p:Config=Debug /p:Platform=Win32 Test\{0}.dproj" -f $r.Name
  if (-not (Test-Path $rexe)) {
    Write-Output "run_tests: FATAL -- $($r.Name).exe is MISSING at $rexe"
    Write-Output "  its suite would report SKIP, which the summary counts as non-failure."
    Write-Output $build
    $runnerFail++
    continue
  }
  $rTime = (Get-Item $rexe).LastWriteTime
  $older = @($srcFiles | Where-Object { $_.LastWriteTime -gt $rTime } | ForEach-Object Name)
  if ((Test-Path $rdpr) -and ((Get-Item $rdpr).LastWriteTime -gt $rTime)) { $older += $r.Dpr }
  if ($older) {
    Write-Output ("run_tests: FATAL -- {0}.exe ({1:yyyy-MM-dd HH:mm}) is OLDER than: {2}" -f $r.Name, $rTime, ($older -join ', '))
    Write-Output "  it would test a build that no longer exists -- rebuild it."
    Write-Output $build
    $runnerFail++
  }
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
if ($runnerFail) {
  Write-Output ("run_tests: FATAL -- {0} console runner(s) missing or stale (see the top of this run); counted as failures." -f $runnerFail)
  $fail += $runnerFail
}
Write-Output ("run_tests: {0} passed, {1} failed, {2} skipped" -f $pass, $fail, $skip)
if ($fail -eq 0) { exit 0 } else { exit 1 }
