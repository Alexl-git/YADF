# WP14b leftover (#2.7): SmartAlignAssignments padded INSIDE the parens of
# continuation lines that START with `(` (shape-matched peers), e.g.
#   (Gamma.Delta + 2   ), // b
#   (Eta  .Th    + 4000), // c
# Rule: a line led by `(` joins a shape run only when its skeleton has a
# `:` (record/array-constant rows `(idx: 1; Field: 'x')`, see the
# record_array_const_align golden, which must keep aligning).
# Fixture compiles standalone (dcc64). Usage: pwsh Test\test_paren_continuation.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'paren_continuation' $exe
$src = Join-Path $PSScriptRoot 'Cases\paren_continuation_align.pas'
$inc = Join-Path $PSScriptRoot 'Cases'
$dcu = Join-Path $env:TEMP ("pc_dcu_" + [guid]::NewGuid().ToString('N'))
$odir = Join-Path $env:TEMP ("pc_out_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $dcu, $odir | Out-Null

if (-not (Test-DccCompiles $src $inc $dcu)) { Fail 'fixture does not compile standalone' }
$o1 = Join-Path $odir 'paren_continuation_align.pas'   # unit name must match file name
if (Invoke-Yadf $src $ini $o1) {
  $text = Get-Content $o1 -Raw
  MustMatch $text '(?m)^\s+\(Gamma\.Delta \+ 2\), // b\r?$' 'call-argument line not padded inside parens'
  MustMatch $text '(?m)^\s+\(Eta\.Th \+ 4000\), // c\r?$' 'call-argument line not padded around dot'
  MustNotMatch $text '\(\w+\s{2,}\.' 'no padding before a dot inside parens'
  # Positive control: a copy-only (no-op) formatter must fail. The multi-var decl is split and
  # its colons aligned (Eta  : TPart  ;).
  MustMatch    $text '(?m)^\s+Eta\s+: TPart\s*;' 'multi-var decl split + colon aligned (formatter ran)'
  if (SameBytes $src $o1) { Fail 'output identical to input: formatter did nothing' }
  if (-not (Test-DccCompiles $o1 $inc $dcu)) { Fail 'formatted output does not compile' }
  $o2 = New-TempOut
  if (Invoke-Yadf $o1 $ini $o2) { if (-not (SameBytes $o1 $o2)) { Fail 'second pass not byte-identical' } }
}
[IO.Directory]::Delete($dcu, $true)
[IO.Directory]::Delete($odir, $true)
Finish 'paren_continuation'