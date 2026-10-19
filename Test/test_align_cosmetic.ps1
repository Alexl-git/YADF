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
Finish 'align_cosmetic'