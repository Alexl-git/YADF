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

# ----- Overflow case: a header whose JOINED width exceeds MaxLen (180) is
# joined AND THEN greedy-wrapped (Task 2) after top-level ';'/',' separators
# so every emitted line fits the budget. (Task 1 alone left this as a single
# over-long physical line -- wrapping was explicitly out of Task 1's scope
# and is superseded here; this fixture still distinguishes JoinRoutineHeaders
# from the existing structural emitter, which is why it is kept.)
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
foreach ($ln in ($long -split "`r`n" | Where-Object { $_ -match 'ParameterNameQuiteLong' })) {
  if ($ln.Length -gt 180) { Fail "overflow: wrapped line exceeds MaxLen: <$ln>" }
}
MustMatch    $long '(?m)^function BarBarBarBarBarBarBarBarBar\b.*;\s*$' 'overflowing header: first line still starts the header and ends at a ; separator'
MustNotMatch $long '(?m)^\s*[;,]' 'overflowing header: no continuation line starts with a dangling separator (break is AFTER, not before)'
MustNotMatch $long '(?m)^function BarBarBarBarBarBarBarBarBar\(const AlphaParameterNameQuiteLong: TBytesArrayTypeName; BetaParameterNameQuiteLongToo: IThingInterfaceTypeName; GammaParameterNameQuiteLongIndeed: ISessionInterfaceTypeName; out DeltaParameterOutNameQuiteLong: TCommandRecordTypeName\): Boolean;\s*$' 'overflowing header: no longer collapsed onto one over-MaxLen physical line'

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

# ----- REGRESSION (Task 1 review M1, folded into Task 2): a comment-while-
# paren-open continuation line whose OWN bracket is net-unbalanced before the
# `//` (e.g. a multi-line set/array default split across lines) must not
# leave St.Depth stuck above 0 for the rest of the file. The bug: the old
# code re-used the block-keyword bail block (which assumes the aborting line
# is UNSCANNED), but the comment-abort fires AFTER ScanLine already advanced
# St across that line -- so it got scanned a SECOND time when the top-level
# loop reprocessed it, double-counting the '[' and leaving Depth permanently
# off by one. Symptom: every header AFTER the comment-interrupted one in the
# same file silently stops joining. Foo (below) is expected to stay split --
# it is the genuine comment-interrupted case, correctly left alone -- but
# Bar, which follows it, must still join normally; if Depth leaked, Bar would
# incorrectly stay split too.
$m1 = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function Foo(A: Integer; B: TIntSet;'
  '  C: TIntSet = [1, 2, // trailing note, bracket still open'
  '    3]): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  ''
  'function Bar(D: Integer;'
  '  E: Integer): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)
MustMatch $m1 '(?m)^  C: TIntSet = \[1, 2, // trailing note, bracket still open\s*$' 'M1: comment-interrupted header (Foo) still correctly left split'
MustMatch $m1 '(?m)^function Bar\(D: Integer; E: Integer\): Boolean;\s*$' 'M1: later header (Bar) still joins -- St.Depth did not leak from the comment-abort line'

# ----- Overflow: a header longer than MaxLen greedy-wraps AFTER ';' -----
# Default MaxLen = 180. Build a header whose one-line form exceeds it.
$long2 = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function VeryLongRoutineName(const AlphaParameter: TSomeByteArrayType; BetaParameter: IThingInterface;'
  '  GammaParameter: ISessionContext; DeltaParameter: IWhateverInterface; out EpsilonParameter: TCommandID;'
  '  out ZetaParameter: TByteArray): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)
# Every wrapped line stays within MaxLen (180); continuation lines end at a ';'
# boundary (break AFTER the separator) and are indented deeper than the header.
foreach ($ln in ($long2 -split "`r`n" | Where-Object { $_ -match 'Parameter' })) {
  if ($ln.Length -gt 180) { Fail "overflow: wrapped line exceeds MaxLen: <$ln>" }
}
# DEVIATION from the design brief: its own regex here was 'Parameter;\s*$',
# but that pattern can never match -- every top-level ';' sits right after a
# TYPE name (TSomeByteArrayType, IThingInterface, ...), never after the
# literal substring "Parameter" (that is always the PARAMETER name, one
# token left of the ':'). Assert the same intent -- the header line ends
# cleanly at a ';', not mid-token -- anchored on the routine name (line 1),
# which holds regardless of exactly which separator the greedy search picks.
MustMatch    $long2 '(?m)^function VeryLongRoutineName\b.*;\s*$' 'overflow: first line still starts the header and ends at a ; separator'
MustNotMatch $long2 '(?m)^\s*[;,]' 'overflow: no continuation line starts with a dangling separator'

# ----- Trailing-comment safety: an overflowing header whose LAST line
# carries a trailing `// note` after the closing ');' must not have the wrap
# search pick a break position inside (or past) that comment -- the wrap
# scan stops at the first `//` (seLineComment), same policy as
# JoinRoutineHeaders' own cross-line scanner.
# NOTE: params are deliberately WITHOUT a const/var modifier on continuation
# lines here -- StartsBlockKeyword (Task 1) treats a leading 'const'/'var' as
# the tell-tale of an anonymous-method's own block/section starting inside a
# still-open call paren, so a continuation line that legitimately starts a
# NEW PARAMETER with a const/var modifier (very common Delphi style) is
# mis-detected as that same tell-tale and the header is left split, unjoined.
# That is a pre-existing Task-1 defect, independent of WrapHeaderLine; out of
# Task 2 scope to fix (flagged for follow-up), so this fixture sidesteps it.
$cmtWrap = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function DoSomethingLong(AlphaParamNameIsQuiteLong: TAlphaTypeNameIsAlsoQuiteLong;'
  '  BetaParamNameIsQuiteLong: TBetaTypeNameIsAlsoQuiteLong;'
  '  GammaParamNameIsQuiteLong: TGammaTypeNameIsAlsoQuiteLong): Boolean; // keep this trailing note intact'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)
foreach ($ln in ($cmtWrap -split "`r`n" | Where-Object { $_ -match 'ParamNameIsQuiteLong' })) {
  if ($ln.Length -gt 180) { Fail "overflow+comment: wrapped line exceeds MaxLen: <$ln>" }
}
MustMatch $cmtWrap '(?m)\): Boolean; // keep this trailing note intact\s*$' 'overflow+comment: closing tokens and trailing comment survive together, unsplit'

# ----- Idempotency of the WRAP itself: format an overflowing header once (it
# gets joined+wrapped), then feed that wrapped output back through the
# formatter. Its continuation lines still sit inside the still-open '(' (the
# same reason JoinRoutineHeaders re-joins any split header), so it must
# re-join and re-wrap to the BYTE-IDENTICAL shape (hash-equal) rather than
# drift on a second pass.
$wsrc = Join-Path $env:TEMP 'jh_wrap_idem.pas'
@'
unit probe;
interface
implementation
function VeryLongRoutineName(const AlphaParameter: TSomeByteArrayType; BetaParameter: IThingInterface;
  GammaParameter: ISessionContext; DeltaParameter: IWhateverInterface; out EpsilonParameter: TCommandID;
  out ZetaParameter: TByteArray): Boolean;
begin
  Result := True;
end;
end.
'@ | Set-Content $wsrc -Encoding ascii
$wo1 = Join-Path $env:TEMP 'jh_w1.pas'; $wo2 = Join-Path $env:TEMP 'jh_w2.pas'
& $exe --ini $ini $wsrc --o $wo1 | Out-Null
& $exe --ini $ini $wo1  --o $wo2 | Out-Null
if ((Get-FileHash $wo1).Hash -ne (Get-FileHash $wo2).Hash) { Fail 'idempotent: wrapped header re-join/re-wrap' }
$wchk = & $exe --ini $ini --check $wo1 2>&1
if ("$wchk" -notmatch 'PASS') { Fail 'roundtrip/guard: wrapped header' }
Remove-Item $wsrc,$wo1,$wo2 -Force -ErrorAction SilentlyContinue

# ----- Idempotency when the wrap point lands right before a const/var
# parameter: WrapHeaderLine picks its break purely by position (rightmost
# ';'/',' <= MaxLen), so nothing stops the continuation it creates from
# starting with "const"/"var" -- exactly the leading word StartsBlockKeyword
# (Task 1, see the $cmtWrap comment above) treats as an abort tell-tale. On a
# second pass this makes JoinRoutineHeaders decline to re-join (it bails,
# emitting the two lines verbatim) instead of genuinely re-joining and
# re-wrapping -- a DIFFERENT code path than pass 1. Verified this still lands
# on the byte-identical shape (the bailed-verbatim lines already ARE
# WrapHeaderLine's own head/NewIndent+tail shape), so it is not a regression,
# but the coincidence is non-obvious enough to pin down permanently.
$cvSrc = Join-Path $env:TEMP 'jh_constvar_wrap.pas'
@'
unit probe;
interface
implementation
function ProbeConstWrap(AlphaParamNameQuiteLongXXXXXXX: TAlphaTypeNameQuiteLong; BetaParamNameQuiteLongYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY: TBetaTypeNameQuiteLong;
  const GammaParamNameQuiteLong: TGammaTypeNameQuiteLong): Boolean;
begin
  Result := True;
end;
end.
'@ | Set-Content $cvSrc -Encoding ascii
$cvo1 = Join-Path $env:TEMP 'jh_cv1.pas'; $cvo2 = Join-Path $env:TEMP 'jh_cv2.pas'
& $exe --ini $ini $cvSrc --o $cvo1 | Out-Null
& $exe --ini $ini $cvo1  --o $cvo2 | Out-Null
if ((Get-FileHash $cvo1).Hash -ne (Get-FileHash $cvo2).Hash) { Fail 'idempotent: wrap point landing before a const/var parameter' }
MustMatch (Get-Content $cvo1 -Raw) '(?m)^  const GammaParamNameQuiteLong: TGammaTypeNameQuiteLong\): Boolean;\s*$' 'wrap before const/var: continuation line still correctly formed'
$cvchk = & $exe --ini $ini --check $cvo1 2>&1
if ("$cvchk" -notmatch 'PASS') { Fail 'roundtrip/guard: wrap point landing before a const/var parameter' }
Remove-Item $cvSrc,$cvo1,$cvo2 -Force -ErrorAction SilentlyContinue

# ----- Idempotency + Guard round-trip over the mixed corpus -----
$idem = Join-Path $env:TEMP 'jh_idem.pas'
@'
unit probe;
interface
type
  TCb = procedure(Sender: TObject;
    const Msg: string) of object;
implementation
function Bar(const A: TBytes;
  B: IThing; C: ISession;
  out D: TCmd): Boolean;
begin
  Result := True;
end;
end.
'@ | Set-Content $idem -Encoding ascii
$o1 = Join-Path $env:TEMP 'jh_i1.pas'; $o2 = Join-Path $env:TEMP 'jh_i2.pas'
& $exe --ini $ini $idem --o $o1 | Out-Null
& $exe --ini $ini $o1   --o $o2 | Out-Null
if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail 'idempotent: join headers' }
$chk = & $exe --ini $ini --check $o1 2>&1
if ("$chk" -notmatch 'PASS') { Fail 'roundtrip/guard: join headers' }
Remove-Item $idem,$o1,$o2 -Force -ErrorAction SilentlyContinue

Finish 'join_headers'
