# PackShortBodies option (--pack-bodies / --no-pack-bodies). OFF (default) keeps
# a loop/if body on its own line under the header; ON pulls a SHORT simple body
# onto the header line. A nested control header (if under for) is never pulled
# up in either mode (no half-merge). Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'pack_bodies' $exe
$src = Join-Path $PSScriptRoot 'Cases\pack_bodies.pas'

function Fmt([string[]]$flags) {
  $tmp = Join-Path $env:TEMP 'pb.out'
  & $exe --ini $ini $src $flags --o $tmp | Out-Null
  $o = Get-Content $tmp -Raw; Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return $o
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

# idempotency + round-trip, both modes (CheckStable from TestLib)
CheckStable 'off' @('--no-pack-bodies')
CheckStable 'on'  @('--pack-bodies')

Finish 'pack_bodies'
