# Keeps every version-bearing file in line with build_all.bat, the single source
# of truth for the release version (owner decision 2026-11-02, task 11):
#   * YADF.Version.inc   YADF_VERSION = '<ver>'
#   * Demo\Sample.pas    line 1 `// YADF-Sample <ver> <md5>` (md5 = SampleBodyHash:
#                        MD5 of the UTF-8 text after line 1, CRLF -> LF)
#   * YADFSample.RES     recompiled with brcc32 when it no longer embeds the
#                        current Demo\Sample.pas bytes
#
# Usage:
#   pwsh sync_version.ps1                  sync the files to build_all.bat's version
#   pwsh sync_version.ps1 -Version 1.0.21.0
#                                          bump: rewrite the build_all.bat version
#                                          lines first, then sync
# build_all.bat calls it (no arguments) before compiling, so a release build can
# never ship a sample stamp that differs from the binary's version.
# Test\test_sample_resource.ps1 fails when any of the three drift.
# Writes a file only when its content changes. Exit 0 = in sync, 1 = error.
param([string]$Version)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$bat  = Join-Path $root 'build_all.bat'
$batText = [IO.File]::ReadAllText($bat)
$parts = 'YADF_MAJOR', 'YADF_MINOR', 'YADF_RELEASE', 'YADF_BUILD'

if ($Version) {
  if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "version must be N.N.N.N, got '$Version'" }
  $nums = $Version.Split('.')
  for ($i = 0; $i -lt 4; $i++) {
    $rx = "(?m)^set $($parts[$i])=\d+\r?$"
    if ($batText -notmatch $rx) { throw "build_all.bat has no 'set $($parts[$i])=' line" }
    $batText = [regex]::Replace($batText, "(?m)^set $($parts[$i])=\d+", "set $($parts[$i])=$($nums[$i])")
  }
  if ($batText -ne [IO.File]::ReadAllText($bat)) {
    [IO.File]::WriteAllText($bat, $batText, [Text.Encoding]::ASCII)
    Write-Output "sync_version: build_all.bat -> $Version"
  }
}

$nums = foreach ($p in $parts) {
  $m = [regex]::Match($batText, "(?m)^set $p=(\d+)")
  if (-not $m.Success) { throw "build_all.bat has no 'set $p=' line" }
  $m.Groups[1].Value
}
$ver = $nums -join '.'

# 1. YADF.Version.inc
$incPath = Join-Path $root 'YADF.Version.inc'
$inc = [IO.File]::ReadAllText($incPath)
$newInc = [regex]::Replace($inc, "YADF_VERSION\s*=\s*'[\d.]+'", "YADF_VERSION = '$ver'")
if ($newInc -eq $inc -and $inc -notmatch "YADF_VERSION\s*=\s*'[\d.]+'") { throw 'YADF.Version.inc has no YADF_VERSION' }
if ($newInc -ne $inc) {
  [IO.File]::WriteAllText($incPath, $newInc, [Text.Encoding]::ASCII)
  Write-Output "sync_version: YADF.Version.inc -> $ver"
}

# 2. Demo\Sample.pas stamp (line 1); the rest of the file is kept byte for byte.
$samplePath = Join-Path $root 'Demo\Sample.pas'
$bytes = [IO.File]::ReadAllBytes($samplePath)
$nl = [Array]::IndexOf($bytes, [byte]10)
if ($nl -lt 0) { throw 'Demo\Sample.pas has a single line' }
$body = [Text.Encoding]::UTF8.GetString($bytes, $nl + 1, $bytes.Length - $nl - 1).Replace("`r`n", "`n")
$md5  = ([BitConverter]::ToString([Security.Cryptography.MD5]::HashData([Text.Encoding]::UTF8.GetBytes($body)))).Replace('-', '').ToLower()
$eol  = if ($nl -gt 0 -and $bytes[$nl - 1] -eq 13) { "`r`n" } else { "`n" }
$stamp = [Text.Encoding]::ASCII.GetBytes("// YADF-Sample $ver $md5$eol")
$newBytes = [byte[]]($stamp + $bytes[($nl + 1)..($bytes.Length - 1)])
if (-not [Linq.Enumerable]::SequenceEqual($newBytes, $bytes)) {
  [IO.File]::WriteAllBytes($samplePath, $newBytes)
  Write-Output "sync_version: Demo\Sample.pas stamp -> $ver $md5"
}

# 3. YADFSample.RES (RCDATA stores the file verbatim)
$resPath = Join-Path $root 'YADFSample.RES'
$embedded = (Test-Path $resPath) -and
  [BitConverter]::ToString([IO.File]::ReadAllBytes($resPath)).Contains([BitConverter]::ToString($newBytes))
if (-not $embedded) {
  $brcc = Join-Path ${env:ProgramFiles(x86)} 'Embarcadero\Studio\37.0\bin\brcc32.exe'
  if (-not (Test-Path $brcc)) { $brcc = 'brcc32.exe' }
  Push-Location $root
  try { & $brcc YADFSample.rc | Out-Null; $rc = $LASTEXITCODE } finally { Pop-Location }
  if ($rc -ne 0) { throw "brcc32 YADFSample.rc failed ($rc)" }
  Write-Output 'sync_version: YADFSample.RES rebuilt'
}
Write-Output "sync_version: $ver in sync"
exit 0
