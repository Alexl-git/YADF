# Bug 2: a then/do/else/case-arm body that is a nested `if` (and its begin/end)
# must indent one level under its controller, composing across nesting -- while
# a same-line `else if` ladder stays flat. Asserted with --no-reflow so the
# nesting is visible (reflow merges some controllers onto one line). Exit 0=pass.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$ini = Join-Path $PSScriptRoot '..\yadf.ini'  # pin config: personal %APPDATA% profile must not affect tests
$src = Join-Path $PSScriptRoot 'Cases\nested_indent.pas'
$fail = 0

$tmp = Join-Path $env:TEMP 'ni.out'
& $exe --ini $ini $src --no-reflow --o $tmp | Out-Null
$o = Get-Content $tmp -Raw
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

function MustMatch([string]$rx, [string]$label) {
  if ($o -notmatch $rx) { $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" }
}
function MustNotMatch([string]$rx, [string]$label) {
  if ($o -match $rx) { $script:fail++; Write-Output "FAIL [$label]: should not match /$rx/" }
}

# A: then -> nested if -> begin/end  (inner if/begin/end at 4, body at 6)
MustMatch '(?m)^    if Y then'        'A: inner if under outer if'
MustMatch '(?m)^    begin'            'A: begin aligns with inner if'
MustMatch '(?m)^      DoA;'           'A: block body one deeper'
MustMatch '(?m)^    end;'             'A: end aligns with begin'
# B: then -> comment -> nested if -> stmt
MustMatch '(?m)^    // note explaining' 'B: comment at body level'
MustMatch '(?m)^      DoNested;'      'B: nested-if body composes to 6'
# C: do -> nested if -> stmt  (for=2, if=4, stmt=6)
MustMatch '(?m)^    if Odd\(I\) then' 'C: loop body if at 4'
MustMatch '(?m)^      DoOdd\(I\);'    'C: innermost body at 6'
# E: same-line else-if ladder stays FLAT
MustMatch    '(?m)^  else if N = 2 then' 'E: ladder else-if at 2'
MustNotMatch '(?m)^    else if'          'E: ladder does NOT creep to 4'
MustMatch    '(?m)^    DoOther;'         'E: ladder body at 4'

# idempotency + round-trip helper
function CheckStable([string]$label, [string[]]$flags) {
  $o1 = Join-Path $env:TEMP 'ni1.pas'; $o2 = Join-Path $env:TEMP 'ni2.pas'
  & $exe --ini $ini $src $flags --o $o1 | Out-Null
  & $exe --ini $ini $o1  $flags --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { $script:fail++; Write-Output "FAIL [idempotent]: $label" }
  $chk = & $exe --ini $ini --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { $script:fail++; Write-Output "FAIL [roundtrip]: $label" }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}
CheckStable 'default'   @()
CheckStable 'no-reflow' @('--no-reflow')

if ($fail -eq 0) { Write-Output 'nested_indent: PASS'; exit 0 }
else { Write-Output "nested_indent: $fail FAILED"; exit 1 }
