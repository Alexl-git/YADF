# PackShortBodies option (--pack-bodies / --no-pack-bodies). OFF (default) keeps
# a loop/if body on its own line under the header; ON pulls a SHORT simple body
# onto the header line. A nested control header (if under for) is never pulled
# up in either mode (no half-merge). Exit 0 = pass.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$src = Join-Path $PSScriptRoot 'Cases\pack_bodies.pas'
$fail = 0

function Fmt([string[]]$flags) {
  $tmp = Join-Path $env:TEMP 'pb.out'
  & $exe $src $flags --o $tmp | Out-Null
  $o = Get-Content $tmp -Raw; Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return $o
}
function MustMatch([string]$o, [string]$rx, [string]$label) {
  if ($o -notmatch $rx) { $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" }
}
function MustNotMatch([string]$o, [string]$rx, [string]$label) {
  if ($o -match $rx) { $script:fail++; Write-Output "FAIL [$label]: should not match /$rx/" }
}

# ----- DEFAULT (off): structural -----
$off = Fmt @('--no-pack-bodies')
MustMatch    $off '(?m)^    Inc\(N\);'      'off: for body on own line'
MustMatch    $off '(?m)^    DoIt;'          'off: if body on own line'
MustMatch    $off '(?m)^    Step;'          'off: while body on own line'
MustNotMatch $off 'do Inc\(N\)'             'off: nothing packed onto do'
MustNotMatch $off 'then DoIt'              'off: nothing packed onto then'
# case arms expanded by default (each body on its own line)
MustMatch    $off '(?m)^    0:\r?\n\s+DoZero;'  'off: case arm 0 expanded'
MustNotMatch $off '0: DoZero'                   'off: case arm not packed onto label'
MustNotMatch $off 'else DoDefault'              'off: case-else body on own line'

# ----- --pack-bodies: short simple bodies packed; nested if NOT half-merged -----
$on = Fmt @('--pack-bodies')
MustMatch    $on 'for I:= 0 to N do Inc\(N\);'   'on: for+simple packed'
MustMatch    $on 'if X then DoIt;'               'on: if+simple packed'
MustMatch    $on 'while Y do Step;'              'on: while+simple packed'
MustMatch    $on 'if Odd\(I\) then DoOdd\(I\);'  'on: inner if+simple packed'
MustMatch    $on '(?m)^  for I:= 0 to N do\r?$'  'on: outer for stays (if is a control header)'
MustNotMatch $on 'do if Odd'                     'on: no half-merge of for+if'
# case arms pack onto the label when on
MustMatch    $on '0: DoZero\s*;'                 'on: case arm 0 packed'
MustMatch    $on '1: if Flag then DoOne;'        'on: case arm if fully packed (no half-merge)'
MustMatch    $on 'else DoDefault;'               'on: case-else body packed'

# idempotency + round-trip, both modes
function CheckStable([string]$label, [string[]]$flags) {
  $o1 = Join-Path $env:TEMP 'pb1.pas'; $o2 = Join-Path $env:TEMP 'pb2.pas'
  & $exe $src $flags --o $o1 | Out-Null
  & $exe $o1  $flags --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { $script:fail++; Write-Output "FAIL [idempotent]: $label" }
  $chk = & $exe --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { $script:fail++; Write-Output "FAIL [roundtrip]: $label" }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}
CheckStable 'off' @('--no-pack-bodies')
CheckStable 'on'  @('--pack-bodies')

if ($fail -eq 0) { Write-Output 'pack_bodies: PASS'; exit 0 }
else { Write-Output "pack_bodies: $fail FAILED"; exit 1 }
