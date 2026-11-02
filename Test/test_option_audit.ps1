# Option-coverage audit: every [Format] key of the repo yadf.ini must be
# exercised by at least one behavioural suite (a Test\test_*.ps1 script names
# the key or one of its CLI flags). REVIEW-2026-10-14 #9 found 22 of 45
# options with no non-default test; option_coverage_a/b closed them. This
# audit keeps a NEW option from shipping untested: add a flipped-from-default
# case (option_coverage_*, option_polarity or a feature suite) or the run is red.
#
# A name match is a floor, not proof of a non-default run -- review the suite
# you point it at. Keys tested only through a CLI flag whose spelling differs
# from the key are listed in $flagOnly.
#
# Usage: pwsh Test\test_option_audit.ps1 [-IniPath <ini>]   (-IniPath proves the audit goes red)
# Exit 0 = every key covered, 1 = uncovered key(s).
param([string]$IniPath)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
if (-not $IniPath) { $IniPath = Get-RepoIni }

# Key -> CLI flag that a suite uses instead of the key name.
$flagOnly = @{ LabelLongBlocks = '--no-label-blocks' }

$keys = @(Select-String -LiteralPath $IniPath -Pattern '^\s*([A-Za-z]\w*)\s*=' | ForEach-Object { $_.Matches[0].Groups[1].Value })
$minKeys = 48   # 2026-11-02; fewer means the INI parse broke, not that options vanished
if ($keys.Count -lt $minKeys) { Fail "only $($keys.Count) keys read from $IniPath (< $minKeys)" }

$suites = @(Get-ChildItem $PSScriptRoot -Filter 'test_*.ps1' | Where-Object { $_.Name -ne 'test_option_audit.ps1' })
$text = ($suites | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
$uncovered = @()
foreach ($k in $keys) {
  $hit = $text -match ('\b' + [regex]::Escape($k) + '\b')
  if (-not $hit -and $flagOnly.ContainsKey($k)) { $hit = $text.Contains($flagOnly[$k]) }
  if (-not $hit) { $uncovered += $k; Fail "option $k has no behavioural test (no test_*.ps1 names it or its flag)" }
}
Write-Output ("option_audit: {0} keys, {1} uncovered" -f $keys.Count, $uncovered.Count)
Finish 'option_audit'
