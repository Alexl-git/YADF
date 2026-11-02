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

# Task 8c: line 1 is the stamp `// YADF-Sample <version> <md5>` LoadSample uses to
# upgrade %APPDATA%\YADF\Sample.pas (YADF.Options.DecideSampleSeed). The md5 is
# SampleBodyHash: MD5 of the UTF-8 text after line 1, CRLF -> LF. <version> is
# YADF_VERSION (YADF.Version.inc), which equals the build_all.bat version (task 11,
# owner 2026-11-02). After editing the demo or bumping: pwsh sync_version.ps1
$text  = [Text.Encoding]::UTF8.GetString($src)
$nlAt  = $text.IndexOf("`n")
$body  = $text.Substring($nlAt + 1).Replace("`r`n", "`n")
$md5   = ([BitConverter]::ToString([Security.Cryptography.MD5]::HashData([Text.Encoding]::UTF8.GetBytes($body)))).Replace('-', '').ToLower()
$inc   = [IO.File]::ReadAllText((Join-Path $root 'YADF.Version.inc'))
$yver  = [version]([regex]::Match($inc, "YADF_VERSION\s*=\s*'([\d.]+)'").Groups[1].Value)
$m     = [regex]::Match($text.Substring(0, $nlAt).TrimEnd(), '^// YADF-Sample (\d+(?:\.\d+)*) ([0-9a-f]{32})$')
if (-not $m.Success) {
  Write-Output "sample_resource: FAIL -- line 1 of Demo\Sample.pas is no stamp; want: // YADF-Sample $yver $md5"
  exit 1
}
if ($m.Groups[2].Value -ne $md5) {
  Write-Output "sample_resource: FAIL -- the stamp hash is stale (Demo\Sample.pas changed); want: // YADF-Sample $yver $md5"
  exit 1
}
$bat   = [IO.File]::ReadAllText((Join-Path $root 'build_all.bat'))
$bver  = (('YADF_MAJOR', 'YADF_MINOR', 'YADF_RELEASE', 'YADF_BUILD') | ForEach-Object { [regex]::Match($bat, "(?m)^set $_=(\d+)").Groups[1].Value }) -join '.'
if ($bver -ne "$yver") {
  Write-Output "sample_resource: FAIL -- build_all.bat version $bver differs from YADF_VERSION $yver; run: pwsh sync_version.ps1"
  exit 1
}
if ([version]$m.Groups[1].Value -ne $yver) {
  Write-Output "sample_resource: FAIL -- stamp version $($m.Groups[1].Value) differs from YADF_VERSION $yver; run: pwsh sync_version.ps1"
  exit 1
}
if ($hex.Contains([BitConverter]::ToString($src))) {
  Write-Output 'sample_resource: PASS (YADFSample.RES embeds the current Demo\Sample.pas)'
  exit 0
}
Write-Output 'sample_resource: FAIL -- YADFSample.RES is stale; run: pwsh sync_version.ps1'
exit 1