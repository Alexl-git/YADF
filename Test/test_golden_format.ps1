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
#   pwsh Test\test_golden_format.ps1                    # verify: diff each file vs its golden
#   pwsh Test\test_golden_format.ps1 -Capture           # write NEW goldens; show the diff of every
#                                                       # CHANGED one and write none of them
#   pwsh Test\test_golden_format.ps1 -Capture -Accept   # after reviewing that diff: bless the changes
#
# No silent re-bless (review 2026-10-14 #9: a blind -Capture blessed corrupted
# asm goldens): an existing golden is only overwritten with -Accept, and every
# overwrite is preceded by its diff in the output.
#
# Exit 0 = all match / captured; 1 = mismatches, or changed goldens awaiting -Accept.
param([switch]$Capture, [switch]$Accept)

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
# Cases\polarity\ fixtures are spec-driven (test_option_polarity.ps1) and must
# never be blessed by a byte-golden of YADF's own output.

if (-not (Test-Path $exe)) { Write-Output "golden_format: SKIP (no exe at $exe -- build YADF.dproj Debug Win64)"; exit 2 }
if (-not (Test-Path $goldDir)) { New-Item -ItemType Directory -Path $goldDir | Out-Null }
$files = Get-ChildItem (Join-Path $PSScriptRoot 'Cases'), (Join-Path $PSScriptRoot 'Snippets') -Filter *.pas -Recurse |
         Where-Object { ($exclude -notcontains $_.Name) -and ($_.Directory.Name -ne 'polarity') }

# SameBytes comes from TestLib.ps1.
$fail = 0
$capFail = 0
$capNew = 0       # goldens written for fixtures that had none
$capPending = 0   # changed goldens shown but not written (no -Accept)
$capBlessed = 0   # changed goldens overwritten under -Accept

# Unified diff of an existing golden vs the new capture ('-' = golden, '+' = new),
# via git's no-index diff. Capped so one rewritten file cannot flood the run.
function Show-GoldenDiff([string]$goldPath, [string]$newPath, [string]$name) {
  $maxLines = 60
  $d = @(& git -c core.autocrlf=false diff --no-index --no-color --text -- $goldPath $newPath 2>&1 | ForEach-Object { "$_" })
  Write-Output "CHANGED golden: $name"
  foreach ($x in ($d | Select-Object -First $maxLines)) { Write-Output "  $x" }
  if ($d.Count -gt $maxLines) { Write-Output "  ... $($d.Count - $maxLines) more diff line(s)" }
}

if ($Accept -and -not $Capture) { Write-Output 'golden_format: -Accept only applies with -Capture'; exit 1 }
# Per-run scratch dir for the verify-mode outputs (no fixed temp names).
$goldTmp = Join-Path $env:TEMP ('gold_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $goldTmp | Out-Null
foreach ($f in $files) {
  $gold = Join-Path $goldDir ($f.Name + '.golden')
  if ($Capture) {
    # Capture into a temp dir under the fixture's own name (unit name must match),
    # and REFUSE to bless output that stopped compiling when the fixture compiles
    # standalone: goldens must not enshrine corruption.
    $cdir = Join-Path $env:TEMP ("goldcap_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $cdir | Out-Null
    try {
      if (-not (Test-UnitNameMatchesFile $f.FullName)) { $capFail++; continue }
      $ctmp = Join-Path $cdir $f.Name
      if (-not (Invoke-Yadf $f.FullName $testIni $ctmp)) { $capFail++; continue }
      $dcu = Join-Path $cdir 'dcu'; New-Item -ItemType Directory -Path $dcu | Out-Null
      if ((Test-DccCompiles $f.FullName $f.DirectoryName $dcu) -and -not (Test-DccCompiles $ctmp $f.DirectoryName $dcu)) {
        $capFail++; Write-Output "FAIL [capture refused: fixture compiles but new output does not]: $($f.Name)"; continue
      }
      if (-not (Test-Path $gold)) { Copy-Item $ctmp $gold; $capNew++; Write-Output "NEW golden: $($f.Name)"; continue }
      if (SameBytes $gold $ctmp) { continue }
      Show-GoldenDiff $gold $ctmp $f.Name
      if ($Accept) { Copy-Item $ctmp $gold -Force; $capBlessed++ }
      else { $capPending++ }
    }
    finally { [IO.Directory]::Delete($cdir, $true) }
  }
  else {
    if (-not (Test-Path $gold)) { $script:fail++; Write-Output "FAIL [missing golden]: $($f.Name) (run -Capture)"; continue }
    $tmp  = Join-Path $goldTmp ($f.Name + ".out")
    $tmp2 = Join-Path $goldTmp ($f.Name + ".out2")
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

[IO.Directory]::Delete($goldTmp, $true)

# Orphaned goldens: a golden whose fixture was renamed/deleted silently stops
# guarding anything -- flag it so the corpus stays honest.
if (-not $Capture) {
  $caseNames = $files | ForEach-Object { $_.Name + '.golden' }
  Get-ChildItem $goldDir -Filter *.golden | Where-Object { $caseNames -notcontains $_.Name } |
    ForEach-Object { $script:fail++; Write-Output "FAIL [orphaned golden]: $($_.Name) (no matching fixture)" }
}

if ($Capture) {
  if ($capFail -gt 0) { Write-Output "golden_format: capture REFUSED/failed for $capFail file(s)"; exit 1 }
  if ($capPending -gt 0) {
    Write-Output ("golden_format: {0} golden(s) CHANGED and NOT written ({1} new written) -- review the diffs above, then re-run with -Capture -Accept" -f $capPending, $capNew)
    exit 1
  }
  Write-Output ("golden_format: captured -- {0} new, {1} changed and blessed, {2} unchanged" -f $capNew, $capBlessed, ($files.Count - $capNew - $capBlessed)); exit 0
}
if ($fail -eq 0) { Write-Output ("golden_format: PASS ({0} files unchanged + idempotent)" -f $files.Count); exit 0 }
else { Write-Output "golden_format: $fail FAILURE(S)"; exit 1 }
