# Golden-format regression harness.
#
# WHY: --check / --check-dir only verify byte-faithful ROUND-TRIP (every source byte
# re-emitted once); they CANNOT catch formatting-shape changes. When we edit the
# indentation/alignment engine (ReindentByDepth, the Align* passes), we need to see
# exactly which corpus files' *formatted output* changed, so an intended fix doesn't
# silently regress unrelated files.
#
# These goldens are a CHANGE DETECTOR, not an assertion that current output is perfect.
# An intended formatting improvement shows as a diff here -- review it, and if correct,
# re-capture with -Capture.
#
# YADF writes each golden itself (via --o) and we compare BYTE-for-byte, so non-ASCII
# files (e.g. umlauts.pas) and encodings are handled exactly as YADF emits them.
#
# Usage:
#   pwsh Test\test_golden_format.ps1            # verify: diff each file vs its golden
#   pwsh Test\test_golden_format.ps1 -Capture   # (re)generate goldens from current exe
#
# Exit 0 = all match / captured; 1 = mismatches.
param([switch]$Capture)

$ErrorActionPreference = 'Stop'
$exe     = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$goldDir = Join-Path $PSScriptRoot 'Golden'
# WIP fixtures (known-bad output we're about to fix) can be excluded so they don't
# lock in a bug. anon_proc_split.pas exercises the anonymous-procedural-type no-split
# guard but ALSO trips a separate, pre-existing procedural-indent quirk (begin/end
# over-indent); it is asserted via regex in test_format_regressions.ps1 instead of a
# byte-golden so we don't lock in that unrelated indent bug.
$exclude = @('anon_proc_split.pas')

if (-not (Test-Path $goldDir)) { New-Item -ItemType Directory -Path $goldDir | Out-Null }
$files = Get-ChildItem (Join-Path $PSScriptRoot 'Cases'), (Join-Path $PSScriptRoot 'Snippets') -Filter *.pas -Recurse |
         Where-Object { $exclude -notcontains $_.Name }

$fail = 0
foreach ($f in $files) {
  $gold = Join-Path $goldDir ($f.Name + '.golden')
  if ($Capture) {
    & $exe $f.FullName --o $gold | Out-Null
  }
  else {
    if (-not (Test-Path $gold)) { $script:fail++; Write-Output "FAIL [missing golden]: $($f.Name) (run -Capture)"; continue }
    $tmp = Join-Path $env:TEMP ("gold_" + $f.Name + ".out")
    & $exe $f.FullName --o $tmp | Out-Null
    $a = [IO.File]::ReadAllBytes($gold)
    $b = [IO.File]::ReadAllBytes($tmp)
    $same = ($a.Length -eq $b.Length)
    if ($same) { for ($k=0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { $same = $false; break } } }
    if (-not $same) { $script:fail++; Write-Output "FAIL [changed]: $($f.Name)" }
  }
}

if ($Capture) { Write-Output ("golden_format: captured {0} files" -f $files.Count); exit 0 }
if ($fail -eq 0) { Write-Output ("golden_format: PASS ({0} files unchanged)" -f $files.Count); exit 0 }
else { Write-Output "golden_format: $fail FILE(S) CHANGED"; exit 1 }
