# Bug 2: a then/do/else/case-arm body that is a nested `if` (and its begin/end)
# must indent one level under its controller, composing across nesting -- while
# a same-line `else if` ladder stays flat. Asserted with --no-reflow so the
# nesting is visible (reflow merges some controllers onto one line). Exit 0=pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'nested_indent' $exe
$src = Join-Path $PSScriptRoot 'Cases\nested_indent.pas'

$tmp = Join-Path $env:TEMP 'ni.out'
& $exe --ini $ini $src --no-reflow --o $tmp | Out-Null
$o = Get-Content $tmp -Raw
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

# A: then -> nested if -> begin/end  (inner if/begin/end at 4, body at 6)
MustMatch $o '(?m)^    if Y then'        'A: inner if under outer if'
MustMatch $o '(?m)^    begin'            'A: begin aligns with inner if'
MustMatch $o '(?m)^      DoA;'           'A: block body one deeper'
MustMatch $o '(?m)^    end;'             'A: end aligns with begin'
# B: then -> comment -> nested if -> stmt
MustMatch $o '(?m)^    // note explaining' 'B: comment at body level'
MustMatch $o '(?m)^      DoNested;'      'B: nested-if body composes to 6'
# C: do -> nested if -> stmt  (for=2, if=4, stmt=6)
MustMatch $o '(?m)^    if Odd\(I\) then' 'C: loop body if at 4'
MustMatch $o '(?m)^      DoOdd\(I\);'    'C: innermost body at 6'
# E: same-line else-if ladder stays FLAT
MustMatch    $o '(?m)^  else if N = 2 then' 'E: ladder else-if at 2'
MustNotMatch $o '(?m)^    else if'          'E: ladder does NOT creep to 4'
MustMatch    $o '(?m)^    DoOther;'         'E: ladder body at 4'

# idempotency + round-trip (CheckStable from TestLib)
CheckStable 'default'   @()
CheckStable 'no-reflow' @('--no-reflow')

Finish 'nested_indent'
