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
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe     = Get-YadfExe
$goldDir = Join-Path $PSScriptRoot 'Golden'
# Pin the config explicitly. Without --ini, YADF now resolves the per-user F
# profile (%APPDATA%\YADF\profiles.ini -> yadf.ini), which varies per machine
# and would make these goldens non-reproducible. The goldens were captured
# against the repo's own yadf.ini, so pass it via --ini to test the FORMATTING
# ENGINE independent of the developer's personal F profile.
$testIni = Join-Path $PSScriptRoot '..\yadf.ini'
# WIP fixtures (known-bad output we're about to fix) can be excluded so they don't
# lock in a bug. (Empty now -- the procedural-indent quirk that kept
# anon_proc_split.pas out is fixed, so it is a normal byte-golden again.)
$exclude = @()

if (-not (Test-Path $exe)) { Write-Output "golden_format: SKIP (no exe at $exe -- build YADF.dproj Debug Win64)"; exit 2 }
if (-not (Test-Path $goldDir)) { New-Item -ItemType Directory -Path $goldDir | Out-Null }
$files = Get-ChildItem (Join-Path $PSScriptRoot 'Cases'), (Join-Path $PSScriptRoot 'Snippets') -Filter *.pas -Recurse |
         Where-Object { $exclude -notcontains $_.Name }

# SameBytes comes from TestLib.ps1.
$fail = 0
$capFail = 0
foreach ($f in $files) {
  $gold = Join-Path $goldDir ($f.Name + '.golden')
  if ($Capture) {
    # Capture into a temp dir under the fixture's own name (unit name must match),
    # and REFUSE to bless output that stopped compiling when the fixture compiles
    # standalone: goldens must not enshrine corruption.
    $cdir = Join-Path $env:TEMP ("goldcap_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $cdir | Out-Null
    try {
      $ctmp = Join-Path $cdir $f.Name
      if (-not (Invoke-Yadf $f.FullName $testIni $ctmp)) { $capFail++; continue }
      $dcu = Join-Path $cdir 'dcu'; New-Item -ItemType Directory -Path $dcu | Out-Null
      if ((Test-DccCompiles $f.FullName $f.DirectoryName $dcu) -and -not (Test-DccCompiles $ctmp $f.DirectoryName $dcu)) {
        $capFail++; Write-Output "FAIL [capture refused: fixture compiles but new output does not]: $($f.Name)"; continue
      }
      Copy-Item $ctmp $gold -Force
    }
    finally { [IO.Directory]::Delete($cdir, $true) }
  }
  else {
    if (-not (Test-Path $gold)) { $script:fail++; Write-Output "FAIL [missing golden]: $($f.Name) (run -Capture)"; continue }
    $tmp  = Join-Path $env:TEMP ("gold_" + $f.Name + ".out")
    $tmp2 = Join-Path $env:TEMP ("gold_" + $f.Name + ".out2")
    if (-not (Invoke-Yadf $f.FullName $testIni $tmp)) { continue }
    if (-not (SameBytes $gold $tmp)) { $script:fail++; Write-Output "FAIL [changed]: $($f.Name)" }
    # Corpus-wide idempotency: formatting the formatted output must be a
    # fixed point. format(format(x)) != format(x) means some pass keeps
    # rewriting its own output -- a non-idempotency bug even when the first
    # output matches the golden.
    if (-not (Invoke-Yadf $tmp $testIni $tmp2)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; continue }
    if (-not (SameBytes $tmp $tmp2)) { $script:fail++; Write-Output "FAIL [not idempotent]: $($f.Name)" }
    Remove-Item $tmp, $tmp2 -Force -ErrorAction SilentlyContinue
  }
}

# Orphaned goldens: a golden whose fixture was renamed/deleted silently stops
# guarding anything -- flag it so the corpus stays honest.
if (-not $Capture) {
  $caseNames = $files | ForEach-Object { $_.Name + '.golden' }
  Get-ChildItem $goldDir -Filter *.golden | Where-Object { $caseNames -notcontains $_.Name } |
    ForEach-Object { $script:fail++; Write-Output "FAIL [orphaned golden]: $($_.Name) (no matching fixture)" }
}

if ($Capture) {
  if ($capFail -gt 0) { Write-Output "golden_format: capture REFUSED/failed for $capFail file(s)"; exit 1 }
  Write-Output ("golden_format: captured {0} files" -f $files.Count); exit 0
}
if ($fail -eq 0) { Write-Output ("golden_format: PASS ({0} files unchanged + idempotent)" -f $files.Count); exit 0 }
else { Write-Output "golden_format: $fail FAILURE(S)"; exit 1 }
