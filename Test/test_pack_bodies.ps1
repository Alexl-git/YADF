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

# ----- WP13: an arm label whose line ends in a `//` note ending in ':' is not a bare label -----
# `2: // note:` ends with a colon, but the colon is comment text; joining the next
# line onto it would swallow the body into the comment.
$wpSrc = @(
  'unit pb13;'
  'interface'
  'implementation'
  'procedure P(X: Integer);'
  'begin'
  '  case X of'
  '    1:'
  '      DoOne;'
  '    2: // note:'
  '      DoTwo;'
  '  end;'
  'end;'
  'end.'
) -join "`r`n"
$wpIn  = New-TempOut
$wpOut = New-TempOut
Set-Content -Path $wpIn -Value $wpSrc -Encoding ascii
if (Invoke-Yadf $wpIn $ini $wpOut @('--pack-bodies', '--no-reflow')) {
  $wpText = Get-Content $wpOut -Raw
  MustMatch    $wpText '1: DoOne;'            'wp13: a real bare label still joins'
  MustNotMatch $wpText '// note:[ \t]+DoTwo'     'wp13: body never pulled into the // comment'
  MustMatch    $wpText '(?m)^\s+DoTwo;'       'wp13: body stays on its own line'
}
Remove-Item $wpIn, $wpOut -Force -ErrorAction SilentlyContinue

Finish 'pack_bodies'
