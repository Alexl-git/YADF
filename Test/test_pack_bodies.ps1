# PackShortBodies option (SPEC-2026-11-03): a preset (--pack-bodies =
# BreakIfBody/BreakLoopBody/BreakWithBody off + CaseArmOnLabelLine on, resolved
# per layer, see the layers section below). The Break*Body defaults (on) keep
# a loop/if body on its own line under the header; the preset pulls a SHORT simple
# body onto the header line. A nested control header (if under for) is never pulled
# up in either mode (no half-merge). Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'pack_bodies' $exe
# Pin config (a personal %APPDATA% profile must not affect tests): the repo INI
# WITHOUT the three Break*Body keys, so the runs below show the compiled-in
# defaults (the CLI preset would beat those keys anyway, SPEC-2026-11-03).
$ini = New-TempOut '.ini'
[IO.File]::WriteAllLines($ini, @([IO.File]::ReadAllLines((Get-RepoIni)) | Where-Object { $_ -notmatch '^\s*Break(If|Loop|With)Body\s*=' }))
$src = Join-Path $PSScriptRoot 'Cases\pack_bodies.pas'

function Fmt([string[]]$flags) {
  $tmp = Join-Path $env:TEMP 'pb.out'
  & $exe --ini $ini $src $flags --o $tmp | Out-Null
  $o = Get-Content $tmp -Raw; Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return $o
}

# ----- DEFAULT (off): structural -----
# Q1/Q2 (SPEC-2026-11-01): Pack OFF only means "don't pack"; case arms follow
# CaseArmOnLabelLine (default on), so pin it off to see the arms expanded.
$off = Fmt @('--no-pack-bodies', '--no-case-arm-on-label')
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
CheckStable 'off' @('--no-pack-bodies', '--no-case-arm-on-label')
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

# ----- SPEC-2026-11-03 section 2: the layered pack rule, worked examples 1-9 -----
# Layers: defaults < INI (PackShortBodies preset, then the INI's own explicit
# rule keys) < CLI (--pack-bodies preset over the result, then the CLI's own
# explicit rule switches). --no-pack-bodies cancels the preset in both layers.
# Order of keys / switches inside one layer never matters.
$lySrc = New-TempOut
[IO.File]::WriteAllText($lySrc, (@(
  'unit pack_layers;'
  'interface'
  'implementation'
  'procedure P(K: Integer);'
  'begin'
  '  if Ok then'
  '    Run;'
  '  for I:= 0 to 9 do'
  '    Inc(N);'
  '  with R do'
  '    Clear;'
  '  case K of'
  '    0:'
  '      DoZero;'
  '  end;'
  'end;'
  'end.'
) -join "`r`n") + "`r`n")
function LyIni([string]$body) { $p = New-TempOut '.ini'; [IO.File]::WriteAllText($p, "[Format]`r`n$body"); return $p }
$lyBare    = LyIni ''
$lyIf      = LyIni "BreakIfBody=true`r`n"
$lyAll     = LyIni "BreakIfBody=true`r`nBreakLoopBody=true`r`nBreakWithBody=true`r`nCaseArmOnLabelLine=true`r`nPackShortBodies=false`r`n"
$lyPackIf  = LyIni "PackShortBodies=true`r`nBreakIfBody=true`r`n"
$lyPack    = LyIni "PackShortBodies=true`r`n"
$lyPackArm = LyIni "CaseArmOnLabelLine=false`r`nPackShortBodies=true`r`n"
# One run; '' = no --ini argument (used with --no-ini).
function Ly([string]$iniPath, [string[]]$flags) {
  $o = New-TempOut
  if ($iniPath) { & $exe --ini $iniPath $lySrc @flags --o $o 2>&1 | Out-Null } else { & $exe $lySrc @flags --o $o 2>&1 | Out-Null }
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $o)) { Fail "layers: YADF exit $LASTEXITCODE for $($flags -join ' ')"; return '' }
  $t = [IO.File]::ReadAllText($o); Remove-Item $o -Force -ErrorAction SilentlyContinue; return $t
}
# $want: four letters if/loop/with/arm -- J = joined onto the header, B = on its own line;
# arm: J = on the label line, B = under the label.
function LyExpect([string]$label, [string]$out, [string]$want) {
  $rx = @(
    @('if Ok then Run;',              '(?m)^\s*if Ok then\r?\n\s+Run;'),
    @('for I:= 0 to 9 do Inc\(N\);', '(?m)^\s*for I:= 0 to 9 do\r?\n\s+Inc\(N\);'),
    @('with R do Clear;',             '(?m)^\s*with R do\r?\n\s+Clear;'),
    @('0: DoZero;',                   '(?m)^\s*0:\r?\n\s+DoZero;'))
  $names = @('if', 'loop', 'with', 'arm')
  for ($k = 0; $k -lt 4; $k++) {
    $col = if ($want[$k] -eq 'J') { 0 } else { 1 }
    MustMatch $out $rx[$k][$col] "layers ${label}: $($names[$k]) $(if ($col -eq 0) { 'joined' } else { 'broken' })"
  }
}
LyExpect '#1 none + --pack-bodies'                       (Ly $lyBare @('--pack-bodies'))                               'JJJJ'
LyExpect '#2 INI BreakIfBody=true + --pack-bodies'       (Ly $lyIf @('--pack-bodies'))                                 'JJJJ'
LyExpect '#3 --break-loop --pack-bodies'                 (Ly $lyBare @('--break-loop', '--pack-bodies'))               'JBJJ'
LyExpect '#3 --pack-bodies --break-loop'                 (Ly $lyBare @('--pack-bodies', '--break-loop'))               'JBJJ'
LyExpect '#4 YADF-written INI + --pack-bodies'           (Ly $lyAll @('--pack-bodies'))                                'JJJJ'
LyExpect '#5 --no-case-arm-on-label --pack-bodies'       (Ly $lyBare @('--no-case-arm-on-label', '--pack-bodies'))     'JJJB'
LyExpect '#5 --pack-bodies --no-case-arm-on-label'       (Ly $lyBare @('--pack-bodies', '--no-case-arm-on-label'))     'JJJB'
LyExpect '#6 INI Pack + --pack-bodies --no-pack-bodies'  (Ly $lyPack @('--pack-bodies', '--no-pack-bodies'))           'BBBJ'
LyExpect '#6 INI Pack + --no-pack-bodies --pack-bodies'  (Ly $lyPack @('--no-pack-bodies', '--pack-bodies'))           'BBBJ'
LyExpect '#6 INI arm=false + both'                       (Ly $lyPackArm @('--no-pack-bodies', '--pack-bodies'))        'BBBB'
LyExpect '#7 INI Pack + BreakIfBody=true'                (Ly $lyPackIf @())                                            'BJJJ'
LyExpect '#7b INI Pack + CaseArmOnLabelLine=false'       (Ly $lyPackArm @())                                           'JJJB'
LyExpect '#8 INI Pack + --no-pack-bodies'                (Ly $lyPack @('--no-pack-bodies'))                            'BBBJ'
# L2 (review 2026-11-03): an EMPTY or unparsable rule key is not an explicit choice,
# so the Pack preset still applies to that rule (if joined, not pinned to the default).
$lyEmpty = LyIni "PackShortBodies=true`r`nBreakIfBody=`r`nBreakLoopBody=maybe`r`n"
LyExpect '#L2 INI Pack + empty/garbage rule keys'        (Ly $lyEmpty @())                                             'JJJJ'
LyExpect '#9 --no-ini --pack-bodies'                     (Ly '' @('--no-ini', '--pack-bodies'))                        'JJJJ'
# --no-ini = compiled-in defaults + CLI switches: the same bytes as an empty INI.
if ((Ly '' @('--no-ini')) -ne (Ly $lyBare @())) { Fail 'layers #9: --no-ini output differs from an empty INI (defaults)' }
$lyErr = & $exe --ini $lyBare --no-ini $lySrc 2>&1 | Out-String
if ($LASTEXITCODE -ne 2) { Fail "--ini + --no-ini: exit $LASTEXITCODE, want 2 (usage error)" }
MustMatch $lyErr '--ini and --no-ini cannot be combined' '--ini + --no-ini: message'
$lyHelp = & $exe --no-ini --help 2>&1 | Out-String
MustMatch $lyHelp '(?m)^\s+--no-ini\s' '--help lists --no-ini'
MustMatch $lyHelp ([regex]::Escape('Precedence: CLI flags > INI values > compiled-in defaults (--no-ini: CLI flags > defaults).')) '--help precedence line'
Remove-Item $lySrc, $lyBare, $lyIf, $lyAll, $lyPackIf, $lyPack, $lyPackArm -Force -ErrorAction SilentlyContinue

Finish 'pack_bodies'
