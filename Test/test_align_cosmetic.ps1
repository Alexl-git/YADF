# Review 2026-10-19: SmartAlignAssignments must not pair a `:=` line with a peer
# at a DIFFERENT indent (remainder after --break-if / --break-loop), and must not
# pad inside an attribute bracket (`[weak  ] FX, FY`, `[MyAttr] A , B :`).
# Usage: pwsh Test\test_align_cosmetic.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'align_cosmetic' $exe
$src = Join-Path $PSScriptRoot 'Cases\align_indent_attr.pas'

$out = New-TempOut
if (Invoke-Yadf $src $ini $out @('--break-if', '--break-loop')) {
  $txt = [IO.File]::ReadAllText($out)
  MustMatch $txt '(?m)^ {2}Y:= 2;'   'Y:= 2; keeps single-space := (not aligned to the deeper X:= 1;)'
  MustMatch $txt '(?m)^ {2}Y:= 4;'   'Y:= 4; keeps single-space := (not aligned to the deeper X:= 3;)'
  MustMatch $txt '\[weak\] FX, FY\s*:' 'attribute bracket [weak] not padded'
  MustMatch $txt '\[MyAttr\] A, B\s*:' 'attribute list [MyAttr] A, B not padded'
  MustNotMatch $txt '\[\w+ +\]'        'no padding inside any attribute bracket'
  $out2 = New-TempOut
  if (Invoke-Yadf $out $ini $out2 @('--break-if', '--break-loop')) {
    if (-not (SameBytes $out $out2)) { Fail 'align_cosmetic: second pass changed the output (not idempotent)' }
  }
}
# Cosmetic (2026-11-03): AlignMatchingShapes never pads a closing `)` / `]`.
$src3 = Join-Path $PSScriptRoot 'Cases\align_close_paren.pas'
$out3 = New-TempOut
if (Invoke-Yadf $src3 $ini $out3 @()) {
  $txt = [IO.File]::ReadAllText($out3)
  MustNotMatch $txt '(?m)^(?!\s*//)[^/]*\S +[)\]]' 'no space before a closing ) or ] on a code line'
  MustMatch $txt "(?m)^  Writeln\('one'\);" "Writeln('one'); tight"
  MustMatch $txt '(?m)^  Foo\(1  , 2\);' 'Foo(1  , 2); keeps comma alignment, tight closer'
  # Never a space between a callee and its `(` (P(); beside Writeln('x'); was `P      ();`).
  MustNotMatch $txt '(?m)^(?!\s*//)[^/]*\w +\(' 'no space between an identifier and its ('
  MustMatch $txt '(?m)^  P\(\);' 'P(); tight'
  MustMatch $txt '(?m)^  Foo\(1, 2\);\r?\n  Gamma\(3, 4\);' 'different callees: no padding at the ( nor in the arguments'
  $out4 = New-TempOut
  if (Invoke-Yadf $out3 $ini $out4 @()) {
    if (-not (SameBytes $out3 $out4)) { Fail 'align_cosmetic: close-paren case not idempotent' }
  }
}
# Owner rule 2026-11-04: same-shape := lines with an indexed target. Default
# (AlignShapeMinAnchors=3): the := after the interior ] lines up, the ] does not.
# AlignShapeMinAnchors<=2 with AlignMatchingShapes on: the target's ] lines up too.
$src5 = Join-Path $PSScriptRoot 'Cases\align_index_target.pas'
# Repo INI with each key's value replaced IN PLACE (a second [Format] section is not merged).
function New-AnchorIni([hashtable]$kv) {
  $p = New-TempOut '.ini'
  $t = [IO.File]::ReadAllText($ini)
  foreach ($k in $kv.Keys) {
    if ($t -notmatch "(?m)^$k=") { throw "New-AnchorIni: $k not in the repo INI" }
    $t = $t -replace "(?m)^$k=[^\r\n]*", "$k=$($kv[$k])"
  }
  [IO.File]::WriteAllText($p, $t)
  $p
}
$out5 = New-TempOut
if (Invoke-Yadf $src5 $ini $out5 @()) {
  $txt = [IO.File]::ReadAllText($out5)
  MustMatch $txt '(?m)^  A\[1\]  := 1;\r?\n  A\[22\] := 2;\r?\n  A\[333\]:= 3;' 'min 3: := lines up after the interior ], brackets tight'
  MustMatch $txt '(?m)^  A\[1\]  := A\[1\]   \+ 1;' 'min 3: RHS ] tight, + aligned'
}
$ini2 = New-AnchorIni @{ AlignShapeMinAnchors = '2' }
$out6 = New-TempOut
if (Invoke-Yadf $src5 $ini2 $out6 @()) {
  $txt = [IO.File]::ReadAllText($out6)
  MustMatch $txt '(?m)^  A\[1  \]:= 1;\r?\n  A\[22 \]:= 2;\r?\n  A\[333\]:= 3;' 'min 2: target ] and := both line up'
  MustMatch $txt '(?m)^  A\[1  \]:= A\[1\]   \+ 1;' 'min 2: a ] after := stays tight'
  MustMatch $txt '(?m)^  Writeln\(A\[1\]\);' 'min 2: Writeln(A[1]); untouched'
  $out7 = New-TempOut
  if (Invoke-Yadf $out6 $ini2 $out7 @()) {
    if (-not (SameBytes $out6 $out7)) { Fail 'align_cosmetic: index-target min 2 not idempotent' }
  }
}
$ini3 = New-AnchorIni @{ AlignShapeMinAnchors = '2'; AlignMatchingShapes = 'false' }
$out8 = New-TempOut
if (Invoke-Yadf $src5 $ini3 $out8 @()) {
  MustMatch ([IO.File]::ReadAllText($out8)) '(?m)^  A\[1\]  := 1;\r?\n  A\[22\] := 2;' 'shapes off: := only, brackets tight'
}
Finish 'align_cosmetic'