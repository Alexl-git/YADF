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

# ----- REGRESSION: header interrupted by a `//` comment while a paren is
# still open must NOT be silently mis-joined. The bug: the cross-line scanner
# stopped on the comment without objection, so the accumulation loop folded
# the following continuation line(s) into the comment text -- the Stage-6
# Guard then detects the altered `// count` token and DECLINES THE WHOLE FILE
# (reverts to the unformatted input verbatim), a regression for any file with
# an interior parameter comment (common Delphi style) that formatted fine
# before this pass existed. The symptom is a whole-file decline, not visibly
# mangled output (Guard reverts the mangle), so detect it via a body
# statement YADF always reflows (`X := 1;` -> `X:= 1;`): declined = stays
# `X := 1;` (RED); formatted = becomes `X:= 1;` (GREEN). `X := 1;` is kept as
# the ONLY assignment in the body so AlignMatchingShapes has no sibling
# assignment to pad it against (which would produce `X     := 1;` instead).
$cmt = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function Foo(A: Integer; // count'
  '  B: string): Boolean;'
  'begin'
  '  X := 1;'
  'end;'
  'end.'
)
MustMatch    $cmt '(?m)^\s*X:= 1;\s*$'                           'comment-interrupted header: file still formatted (not Guard-declined)'
MustMatch    $cmt '(?m)^function Foo\(A: Integer; // count\s*$' 'comment-interrupted header: comment line survives on the header start line'
MustMatch    $cmt '(?m)^\s*B: string\): Boolean;\s*$'            'comment-interrupted header: rest of header still on its own line'
MustNotMatch $cmt '// count.*B: string'                          'comment-interrupted header: comment text not immediately followed by rest of header on the same line'

Finish 'join_headers'
