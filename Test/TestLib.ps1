# Shared helpers for the Test\test_*.ps1 suites. Dot-source at the top of a
# script (AFTER $ErrorActionPreference = 'Stop'):
#
#   . (Join-Path $PSScriptRoot 'TestLib.ps1')
#
# Contract: the helpers count failures in $script:fail of the CALLING script
# (dot-sourcing shares the script scope), so a suite ends with:
#
#   Finish 'suite_name'          # prints PASS / N FAILED, sets exit code
#
# Assertion helpers take the OUTPUT under test explicitly (no closures), so
# every suite reads the same way: MustMatch $o 'regex' 'label'.
# Not matched by run_tests.ps1 (which globs test_*.ps1 only).

$script:fail = 0

# Canonical tool paths. Every suite tests the SAME Win64 Debug exe that
# run_tests.ps1 stale-checks, and pins the repo yadf.ini so a personal
# %APPDATA% profile can never flip results.
function Get-YadfExe { Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe' }
function Get-RepoIni { Join-Path $PSScriptRoot '..\yadf.ini' }

# Exit 2 = "skip" (tool not built) -- run_tests.ps1 reports it as SKIP.
function Assert-ToolOrSkip([string]$suite, [string]$path) {
  if (-not (Test-Path $path)) { Write-Output "${suite}: SKIP (no exe at $path)"; exit 2 }
}

function Fail([string]$msg) { $script:fail++; Write-Output "FAIL [$msg]" }

function MustMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -notmatch $rx) { $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" }
}

function MustNotMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -match $rx) { $script:fail++; Write-Output "FAIL [$label]: should NOT match /$rx/" }
}

function MustContain([string]$out, [string]$needle, [string]$label) {
  if (-not $out.Contains($needle)) { $script:fail++; Write-Output "FAIL [$label]: expected literal '$needle'" }
}

function SameBytes([string]$p1, [string]$p2) {
  $a = [IO.File]::ReadAllBytes($p1)
  $b = [IO.File]::ReadAllBytes($p2)
  if ($a.Length -ne $b.Length) { return $false }
  for ($k = 0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { return $false } }
  return $true
}

# Idempotency + byte-faithful round-trip for one flag set. CONTRACT: reads
# $exe, $ini and $src from the calling script's scope (dot-source sharing) --
# set all three before calling.
function CheckStable([string]$label, [string[]]$flags) {
  $g  = [guid]::NewGuid().ToString('N')
  $o1 = Join-Path $env:TEMP "cs1_$g.pas"; $o2 = Join-Path $env:TEMP "cs2_$g.pas"
  & $exe --ini $ini $src $flags --o $o1 | Out-Null
  & $exe --ini $ini $o1  $flags --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail "idempotent: $label" }
  $chk = & $exe --ini $ini --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { Fail "roundtrip: $label" }
  Remove-Item $o1, $o2 -Force -ErrorAction SilentlyContinue
}

function Finish([string]$suite) {
  if ($script:fail -eq 0) { Write-Output "${suite}: PASS"; exit 0 }
  else { Write-Output "${suite}: $($script:fail) FAILED"; exit 1 }
}
