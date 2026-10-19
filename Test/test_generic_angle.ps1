# RED target (WP17): `:` / `;` inside a generic parameter list `<A: B; C: D>` were
# taken for top-level declaration punctuation by the align / split / wrap passes,
# so `IWide<T: IInterface; U: class> = interface` was padded INSIDE the <...>
# and `procedure Q<A: class; B: record>;` got its `;` pushed out (uncompilable
# or at least ugly). TLineScanState.TrackAngle (opt-in) fixes the four sites.
#
# Fixture Test\Cases\generic_angle_align.pas compiles standalone (dcc64).
# Checks: no run of 2+ spaces INSIDE any <...>; `;` hugs `>` on the generic
# procedure line; output compiles; second pass is byte-identical.
#
# Usage: pwsh Test\test_generic_angle.ps1   (exit 0 = pass, 1 = fail, 2 = skip)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'generic_angle' $exe
$src = Join-Path $PSScriptRoot 'Cases\generic_angle_align.pas'
$inc = Join-Path $PSScriptRoot 'Cases'
$dcu = Join-Path $env:TEMP ("ga_dcu_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $dcu | Out-Null

if (-not (Test-DccCompiles $src $inc $dcu)) { Fail 'fixture does not compile standalone' }

$odir = Join-Path $env:TEMP ("ga_out_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $odir | Out-Null
$o1 = Join-Path $odir 'generic_angle_align.pas'   # unit name must match the file name for dcc64
if (Invoke-Yadf $src $ini $o1) {
  $text = Get-Content $o1 -Raw
  MustNotMatch $text '<[^>\r\n]*\s{2,}[^>\r\n]*>' 'no padding inside <...>'
  # Positive control: a copy-only (no-op) formatter must fail. The aligner pads the = column
  # OUTSIDE the <...> (TSolo<T: class> = ... gets 2+ spaces before =).
  MustMatch    $text '(?m)^\s+TSolo<T: class>\s{2,}= class end;' 'type heads aligned outside <...> (formatter ran)'
  if (SameBytes $src $o1) { Fail 'output identical to input: formatter did nothing' }
  MustContain  $text 'procedure Q<A: class; B: record>;' 'generic procedure keeps ; hugging >'
  MustContain  $text 'IWide<T: IInterface; U: class>' 'interface type parameters untouched'
  MustContain  $text 'TSolo<T: class>' 'single-parameter list untouched'
  if (-not (Test-DccCompiles $o1 $inc $dcu)) { Fail 'formatted output does not compile' }
  $o2 = New-TempOut
  if (Invoke-Yadf $o1 $ini $o2) { if (-not (SameBytes $o1 $o2)) { Fail 'second pass not byte-identical' } }
}
[IO.Directory]::Delete($dcu, $true)
[IO.Directory]::Delete($odir, $true)
Finish 'generic_angle'