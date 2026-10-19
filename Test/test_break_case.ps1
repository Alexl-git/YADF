# Fixture-based tests for BreakCaseLabels (--break-case / --no-break-case).
# Default OFF keeps multi-label case arms on one line; ON splits them per
# label. Genuine var/field declarations still split per SplitMultiVarDecls
# regardless. Exit 0 = all pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
# Per-run scratch dir: no fixed temp names, so concurrent runs cannot collide and a stale
# file from an earlier run can never be scored.
$tmpRoot = Join-Path $env:TEMP ('yadf_test_break_case_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpRoot | Out-Null
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'break_case' $exe
$src = Join-Path $PSScriptRoot 'Cases\case_labels.pas'

function Fmt([string]$flag) {
  $tmp = Join-Path $tmpRoot ("bc_" + ($flag -replace '\W','') + ".out")
  & $exe --ini $ini $src $flag --o $tmp | Out-Null
  $out = Get-Content $tmp -Raw
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

# ----- DEFAULT (--no-break-case): arms kept on one line -----
$off = Fmt '--no-break-case'
MustMatch    $off '0, 1, 2\s*:'          'off: numeric+assign arm intact'
MustMatch    $off '3, 4\s*:'             'off: numeric+call arm intact'
MustMatch    $off '5, 6, 7\s*:\s*begin'  'off: numeric+begin arm intact'
MustNotMatch $off '(?m)^\s*1:\s'         'off: label 1 NOT on its own line'
MustNotMatch $off '(?m)^\s*6:\s'         'off: label 6 NOT on its own line'
# Genuine declaration STILL splits.
MustMatch    $off '(?m)^\s*A: Integer;'  'off: var A split'
MustMatch    $off '(?m)^\s*B: Integer;'  'off: var B split'
MustMatch    $off '(?m)^\s*C: Integer;'  'off: var C split'

# ----- --break-case: arms split per label -----
$on = Fmt '--break-case'
MustMatch    $on '(?m)^\s*0:\s'          'on: label 0 split out'
MustMatch    $on '(?m)^\s*1:\s'          'on: label 1 split out'
MustMatch    $on '(?m)^\s*2:\s'          'on: label 2 split out'
MustMatch    $on '(?m)^\s*6:\s*begin'    'on: label 6 split with begin body'
MustNotMatch $on '0, 1, 2'               'on: no multi-label arm remains'
MustMatch    $on '(?m)^\s*A: Integer;'   'on: var A still split'

# ----- string literals in arm bodies: split must still work -----
# BreakCaseLabels duplicates the arm body per label; the content guard
# tolerates exactly that duplication (2026-07-17 review: it used to veto the
# whole file, leaving --break-case silently inert on any arm with a string).
$strSrc = Join-Path $tmpRoot 'bc_str.pas'
@'
unit bcstr;
interface
procedure Go(X: Integer);
implementation
procedure Go(X: Integer);
begin
  case X of
    1, 2: Writeln('hello');
    3: Writeln('three');
  end;
end;
end.
'@ | Set-Content $strSrc -Encoding ascii
$strOut = Join-Path $tmpRoot 'bc_str_out.pas'
& $exe --ini $ini $strSrc --break-case --o $strOut | Out-Null
$so = Get-Content $strOut -Raw
MustMatch    $so "(?m)^\s*1: Writeln\('hello'\);" 'string-body: label 1 split with body'
MustMatch    $so "(?m)^\s*2: Writeln\('hello'\);" 'string-body: label 2 split with body'
MustNotMatch $so '1, 2'                           'string-body: no multi-label arm remains'
Remove-Item $strSrc, $strOut -Force -ErrorAction SilentlyContinue

# ----- anonymous types with a '(' / array[..] must NOT be split like case arms -----
# `C, D: (Red, Green)` and `A, B: array[Low(T)..High(T)] of Integer` carry '(' in
# the type part; CaseArmLikeBody used to classify them as case arms, so
# --break-case split them into incompatible distinct types (E2008/E2004).
# The real case arms in the same fixture must still split. Compile-checked.
$tySrc = Join-Path $PSScriptRoot 'Cases\break_case_types.pas'
$tyDir = Join-Path $env:TEMP ('bct_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tyDir | Out-Null
try {
  $tyOut = Join-Path $tyDir 'break_case_types.pas'
  if (Invoke-Yadf $tySrc $ini $tyOut @('--break-case')) {
    $to = Get-Content $tyOut -Raw
    MustMatch    $to '(?m)^\s*C, D: \(Red, Green\)\s*;'                              'types: enum decl kept combined'
    MustMatch    $to '(?m)^\s*A, B: array\[Low\(TRng\)\.\.High\(TRng\)\] of Integer;' 'types: array decl kept combined'
    MustMatch    $to '(?m)^\s*0:\s*Flag'                                            'types: real case arm 0 still split'
    MustMatch    $to '(?m)^\s*3:\s*Inc'                                             'types: real case arm 3 still split'
    $dcu = Join-Path $tyDir 'dcu'; New-Item -ItemType Directory -Path $dcu | Out-Null
    if (-not (Test-DccCompiles $tyOut (Split-Path $tySrc) $dcu)) { Fail 'types: formatted output does not compile' }
  }
}
finally { [IO.Directory]::Delete($tyDir, $true) }

# ----- variant-record label line `0, 1: (A: Integer);` must NOT be split -----
# Splitting it into `0: (A: Integer); 1: (A: Integer);` duplicates the field
# and does not compile (E2004). A body that opens with `(` is never split.
# The real case arms in the same fixture must still split. Compile-checked.
$vaSrc = Join-Path $PSScriptRoot 'Cases\break_case_variant.pas'
$vaDir = Join-Path $env:TEMP ('bcv_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $vaDir | Out-Null
try {
  $vaOut = Join-Path $vaDir 'break_case_variant.pas'
  if (Invoke-Yadf $vaSrc $ini $vaOut @('--break-case')) {
    $vo = Get-Content $vaOut -Raw
    MustMatch    $vo '(?m)^\s*0, 1\s*: \(A: Integer\)'  'variant: label line kept combined'
    MustMatch    $vo '(?m)^\s*0:\s*Flag'              'variant: real case arm 0 still split'
    MustMatch    $vo '(?m)^\s*3:\s*Inc'               'variant: real case arm 3 still split'
    $dcu = Join-Path $vaDir 'dcu'; New-Item -ItemType Directory -Path $dcu | Out-Null
    if (-not (Test-DccCompiles $vaOut (Split-Path $vaSrc) $dcu)) { Fail 'variant: formatted output does not compile' }
  }
}
finally { [IO.Directory]::Delete($vaDir, $true) }

# ----- idempotency + byte-faithful round-trip for both modes -----
foreach ($flag in @('--no-break-case','--break-case')) {
  $o1 = Join-Path $tmpRoot "bc1.pas"; $o2 = Join-Path $tmpRoot "bc2.pas"
  & $exe --ini $ini $src $flag --o $o1 | Out-Null
  & $exe --ini $ini $o1  $flag --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail "idempotent: $flag" }
  $chk = & $exe --ini $ini --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { Fail "roundtrip: $flag" }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}

[IO.Directory]::Delete($tmpRoot, $true)
Finish 'break_case'
