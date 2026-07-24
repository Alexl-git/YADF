# Fixture tests for JoinRoutineHeaders: a routine header the source split across
# lines is collapsed onto ONE line (always-on, no flag). Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'join_headers' $exe

# Format a whole unit given as an array of source lines; return formatted text.
function Fmt([string[]]$srcLines) {
  $u = $srcLines -join "`r`n"
  $src = Join-Path $env:TEMP 'jh_in.pas'
  $out = Join-Path $env:TEMP 'jh_out.pas'
  Set-Content -Path $src -Value $u -Encoding ascii
  & $exe --ini $ini $src --o $out | Out-Null
  $t = Get-Content $out -Raw
  Remove-Item $src,$out -Force -ErrorAction SilentlyContinue
  return $t
}

# ----- Motivating case: a 3-line header (fits <= MaxLen) collapses to 1 line -----
$hdr = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function Bar(const A: TBytes;'
  '  B: IThing; C: ISession;'
  '  out D: TCmd): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)
MustMatch    $hdr '(?m)^function Bar\(const A: TBytes; B: IThing; C: ISession; out D: TCmd\): Boolean;\s*$' 'header joined to one line'
MustNotMatch $hdr '(?m)^\s+B: IThing; C: ISession;\s*$' 'no leftover middle continuation line'

# ----- Overflow case: a header whose JOINED width exceeds MaxLen (180) still
# collapses to ONE physical line (Task 1 scope: wrapping is Task 2). This is
# the fixture that actually distinguishes JoinRoutineHeaders from the existing
# structural emitter: a header this long does NOT already fit inline, so
# Stage 2 leaves it split across lines on its own; only JoinRoutineHeaders
# joins it (single long line, over MaxLen, by design).
$long = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function BarBarBarBarBarBarBarBarBar(const AlphaParameterNameQuiteLong: TBytesArrayTypeName;'
  '  BetaParameterNameQuiteLongToo: IThingInterfaceTypeName; GammaParameterNameQuiteLongIndeed: ISessionInterfaceTypeName;'
  '  out DeltaParameterOutNameQuiteLong: TCommandRecordTypeName): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)
MustMatch    $long '(?m)^function BarBarBarBarBarBarBarBarBar\(const AlphaParameterNameQuiteLong: TBytesArrayTypeName; BetaParameterNameQuiteLongToo: IThingInterfaceTypeName; GammaParameterNameQuiteLongIndeed: ISessionInterfaceTypeName; out DeltaParameterOutNameQuiteLong: TCommandRecordTypeName\): Boolean;\s*$' 'overflowing header still joined to one line'
MustNotMatch $long '(?m)^\s+BetaParameterNameQuiteLongToo:' 'no leftover continuation line for overflowing header'

# ----- Interface forward decl + trailing directives: joins params, stops at first ';' -----
$fwd = Fmt @(
  'unit probe;'
  'interface'
  'type'
  '  TFoo = class'
  '    procedure Go(const A: Integer;'
  '      B: Integer); virtual;'
  '  end;'
  'implementation'
  'end.'
)
MustMatch $fwd '(?m)^\s*procedure Go\(const A: Integer; B: Integer\); virtual;\s*$' 'forward decl joined, directive rides along'

# ----- Constructor (Case A leading keyword, not procedure/function) -----
$ctor = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'constructor TFoo.Create(const A: string;'
  '  B: Integer);'
  'begin'
  'end;'
  'end.'
)
MustMatch $ctor '(?m)^constructor TFoo\.Create\(const A: string; B: Integer\);\s*$' 'constructor header joined'

# ----- Procedure-type declaration (Case B inline procedure() ) -----
$ptype = Fmt @(
  'unit probe;'
  'interface'
  'type'
  '  TCb = procedure(Sender: TObject;'
  '    const Msg: string) of object;'
  'implementation'
  'end.'
)
MustMatch $ptype '(?m)^\s*TCb = procedure\(Sender: TObject; const Msg: string\) of object;\s*$' 'proc-type decl joined'

# ----- NEGATIVE: a multi-line CALL must survive unchanged -----
# NOTE (deviation from the brief): the brief's original fixture used 3 short
# args (DoStuff(Alpha, / Beta, / Gamma);). Verified against baseline (pre-
# JoinRoutineHeaders) that this call is ALREADY collapsed onto one line by
# the pre-existing Stage-2 structural emitter (WalkGroup's InlineRenderRange
# collapses ANY comment-free parens group -- call or header alike -- that
# fits inline under MaxLen=180) before JoinRoutineHeaders ever runs, so the
# original assertions failed unconditionally regardless of this feature and
# could never distinguish "JoinRoutineHeaders wrongly joined a call" from
# "Stage 2 already joined it for unrelated reasons". Long-enough arg names
# push the call over MaxLen so Stage 2's RenderParensBroken leaves it
# genuinely split across 2 physical lines -- a real span for
# JoinRoutineHeaders to (correctly) leave alone, since `DoStuffWith...(`
# never matches IsHeaderStart (no leading routine keyword).
$call = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'procedure Demo;'
  'begin'
  '  DoStuffWithAVeryVeryVeryVeryVeryVeryLongNameThatWontFitOnOneLineAtAllNoMatterWhat(AlphaParameterNameIsQuiteLongIndeedYes,'
  '    BetaParameterNameIsQuiteLongTooYesIndeed,'
  '    GammaParameterNameAlsoQuiteLongIndeedYesVeryLong);'
  'end;'
  'end.'
)
MustMatch $call '(?m)^\s+DoStuffWithAVeryVeryVeryVeryVeryVeryLongNameThatWontFitOnOneLineAtAllNoMatterWhat\(\s*$' 'call header opener left split (line 1)'
MustMatch $call '(?m)^\s+AlphaParameterNameIsQuiteLongIndeedYes, BetaParameterNameIsQuiteLongTooYesIndeed, GammaParameterNameAlsoQuiteLongIndeedYesVeryLong\);\s*$' 'call args left split (line 2)'

Finish 'join_headers'
