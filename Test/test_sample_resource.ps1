# Guards the embedded preview sample against drift.
#
# YADF.OptionsFrame links YADFSample.RES (compiled from YADFSample.rc) and seeds
# %APPDATA%\YADF\Sample.pas from it on first use -- no Sample.pas ships beside
# YADFOT.bpl / YADFSetup.exe any more. The .RES is committed and NOT rebuilt by
# msbuild, so editing Demo\Sample.pas without re-running `brcc32 YADFSample.rc`
# would silently ship the OLD demo. RCDATA stores the file bytes verbatim, so the
# check is: the current Demo\Sample.pas must appear byte-for-byte inside the .RES.
#
# Usage: pwsh Test\test_sample_resource.ps1   (exit 0 = pass, 1 = fail)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$src  = [IO.File]::ReadAllBytes((Join-Path $root 'Demo\Sample.pas'))
$res  = [IO.File]::ReadAllBytes((Join-Path $root 'YADFSample.RES'))
$hex  = [BitConverter]::ToString($res)
if ($hex.Contains([BitConverter]::ToString($src))) {
  Write-Output 'sample_resource: PASS (YADFSample.RES embeds the current Demo\Sample.pas)'
  exit 0
}
Write-Output 'sample_resource: FAIL -- YADFSample.RES is stale; run: brcc32 YADFSample.rc'
exit 1