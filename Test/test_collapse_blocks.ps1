# CollapseShortBlocks option (--collapse-blocks / --no-collapse-blocks). OFF
# (default) keeps begin..end blocks expanded; ON folds a SHORT control-statement
# begin..end body (if/for/while/with/else) of simple statements onto one line.
# Leaf-only: a nested/multi-line body or a comment keeps the block expanded.
# Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'collapse_blocks' $exe
$src = Join-Path $PSScriptRoot 'Cases\collapse_blocks.pas'

function Fmt([string[]]$flags) {
  $tmp = Join-Path $env:TEMP 'cb.out'
  & $exe --ini $ini $src $flags --o $tmp | Out-Null
  $o = Get-Content $tmp -Raw; Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return $o
}

# ----- DEFAULT (off): blocks stay expanded -----
$off = Fmt @('--no-collapse-blocks')
MustNotMatch $off 'then begin'              'off: if not collapsed'
MustNotMatch $off 'do begin Inc'            'off: for not collapsed'
MustMatch    $off '(?m)^  begin\r?$'        'off: begin on its own line'

# ----- --collapse-blocks: short control bodies fold onto one line -----
$on = Fmt @('--collapse-blocks')
MustMatch    $on 'if X > 0 then begin A:= 1; B:= 2; end;'   'on: if collapsed'
MustMatch    $on 'for A:= 0 to 9 do begin Inc\(B\); Inc\(X\); end;' 'on: for collapsed'
MustMatch    $on 'while X > 0 do begin Dec\(X\); end;'      'on: while collapsed'
MustMatch    $on 'if X = 5 then begin A:= 1; end'           'on: if/else then-branch collapsed'
MustMatch    $on 'else begin B:= 2; end;'                   'on: if/else else-branch collapsed'
# leaf-only: the OUTER while of a nested pair stays expanded, the inner if folds
MustMatch    $on 'if A > 0 then begin Dec\(X\); end;'       'on: inner leaf collapsed'
MustMatch    $on '(?m)^  while X > 0 do\r?$'                'on: outer (nested) while stays expanded'
# a comment in the body blocks the collapse
MustMatch    $on '(?m)^    A:= 1; // keep me'               'on: commented body stays expanded'
MustNotMatch $on 'then begin A:= 1; // keep me'             'on: comment block not collapsed'
# string interior spaces survive the squeeze
MustMatch    $on "begin S:= 'a   b'; end;"                  'on: string interior preserved'

# idempotency + round-trip, both modes (CheckStable from TestLib)
CheckStable 'off' @('--no-collapse-blocks')
CheckStable 'on'  @('--collapse-blocks')

Finish 'collapse_blocks'
