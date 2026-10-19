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
# $env:YADF_TEST_EXE overrides the exe (used to prove the harness goes RED
# against a stub that merely copies its input).
function Get-YadfExe { if ($env:YADF_TEST_EXE) { $env:YADF_TEST_EXE } else { Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe' } }
function Get-RepoIni { Join-Path $PSScriptRoot '..\yadf.ini' }

# Exit 2 = "skip" (tool not built) -- run_tests.ps1 reports it as SKIP.
function Assert-ToolOrSkip([string]$suite, [string]$path) {
  if (-not (Test-Path $path)) { Write-Output "${suite}: SKIP (no exe at $path)"; exit 2 }
}

function Fail([string]$msg) { $script:fail++; Write-Host "FAIL [$msg]" }

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

# Formats $src into $out with the given ini (and optional extra flags) and
# FAILS the suite -- returning $false -- when YADF exits nonzero, reports a
# guard decline, or writes nothing. $out is deleted first, so a crashed or
# declining run can never be scored against a previous run's output (review
# 2026-10-14: fixed-name temp outputs let a crashing exe pass two suites).
# CONTRACT: reads $exe from the calling script's scope.
function Invoke-Yadf([string]$src, [string]$iniPath, [string]$out, [string[]]$flags = @()) {
  if (Test-Path $out) { Remove-Item $out -Force }
  $msg = & $exe --ini $iniPath $src @flags --o $out 2>&1 | Out-String
  $leaf = Split-Path $src -Leaf
  if ($LASTEXITCODE -ne 0)           { Fail "YADF exit $LASTEXITCODE on ${leaf}: $($msg.Trim())"; return $false }
  if ($msg -match '(?m)^declined ') { Fail "guard declined ${leaf}: $($msg.Trim())"; return $false }
  if (-not (Test-Path $out))         { Fail "no output written for $leaf"; return $false }
  return $true
}

# A fresh, unique temp path (never reused across runs or cases).
function New-TempOut([string]$ext = '.pas') { Join-Path $env:TEMP ("yt_" + [guid]::NewGuid().ToString('N') + $ext) }

# dcc64 + standalone-compile helper shared by the compile gate and the golden
# -Capture guard. $dcuDir must exist; $incDir is the fixture dir ({$I} files).
function Get-Dcc64 { 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe' }
function Test-DccCompiles([string]$pasFile, [string]$incDir, [string]$dcuDir) {
  $ns = 'System;System.Win;Winapi;Vcl;Data;Soap;Xml'
  & (Get-Dcc64) -Q "-NS$ns" "-N0$dcuDir" "-E$dcuDir" "-I$incDir" $pasFile *> $null
  return ($LASTEXITCODE -eq 0)
}

# A fixture whose `unit X;` header differs from its file name cannot compile
# standalone (dcc64 E1038), so the compile gates would silently skip it and
# the golden -Capture would bless its output uncompiled. Returns $false and
# FAILS the suite for such a fixture (review 2026-10-18).
function Test-UnitNameMatchesFile([string]$pasFile) {
  $head = (Get-Content -LiteralPath $pasFile -TotalCount 40 -Encoding Latin1) -join "`n"
  $m = [regex]::Match($head, '(?im)^\s*unit\s+([A-Za-z_][\w.]*)\s*;')
  if (-not $m.Success) { return $true }   # program / library / fragment: not subject
  $base = [IO.Path]::GetFileNameWithoutExtension($pasFile)
  if ($m.Groups[1].Value -ine $base) {
    Fail "unit name '$($m.Groups[1].Value)' != file name '$base': $(Split-Path $pasFile -Leaf)"
    return $false
  }
  return $true
}
function Finish([string]$suite) {
  if ($script:fail -eq 0) { Write-Output "${suite}: PASS"; exit 0 }
  else { Write-Output "${suite}: $($script:fail) FAILED"; exit 1 }
}
