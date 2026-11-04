# Tab-indented input must reach a fixed point like space-indented input does
# (TODO 2026-11-03 LOW): variant-record arm field lists were re-joined on the
# second format because the structural walker decided "fits MaxLen" against the
# SOURCE column (3 tabs x TabWidth 8 = 24) instead of the settled one (12).
# Each fixture is converted to tab indentation (every 2 leading spaces -> 1 tab),
# formatted, and the output formatted again: the two must be byte-identical.
# Usage: pwsh Test\test_tab_idempotence.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'tab_idempotence' $exe
$fixtures = @('Cases\variant_record.pas', 'Snippets\VariantRecordFieldAttributes.pas')
$sets = @(
  @{ Name = 'greedy60-i4';  Flags = @('--no-break-expr', '--max-len', '60', '--indent', '4') },
  @{ Name = 'expr60-i4';    Flags = @('--max-len', '60', '--indent', '4') },
  @{ Name = 'greedy80';     Flags = @('--no-break-expr', '--max-len', '80') },
  @{ Name = 'expr80';       Flags = @('--max-len', '80') }
)
foreach ($fx in $fixtures) {
  $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $fx))
  $tabbed = (($text -split "`r`n") | ForEach-Object {
      if ($_ -match '^( +)(.*)$') { ("`t" * [Math]::Floor($Matches[1].Length / 2)) + (' ' * ($Matches[1].Length % 2)) + $Matches[2] } else { $_ }
    }) -join "`r`n"
  $in = New-TempOut
  [IO.File]::WriteAllText($in, $tabbed)
  foreach ($set in $sets) {
    $flags = @($set.Flags) + @('--tab-width', '8')
    $p1 = New-TempOut; $p2 = New-TempOut
    if (-not (Invoke-Yadf $in $ini $p1 $flags)) { continue }
    if (-not (Invoke-Yadf $p1 $ini $p2 $flags)) { continue }
    if (-not (SameBytes $p1 $p2)) { Fail "[$fx $($set.Name)] tab-indented input: second format changed the output" }
  }
}
Finish 'tab_idempotence'