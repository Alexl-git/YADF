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

# ----- GUARD (const/var bail-set fix): an anonymous method passed as a call
# argument, spanning multiple physical lines and carrying its own real
# `begin..end` BODY, must still be left ALONE -- not joined into the routine
# header it is passed to. This is the scenario StartsBlockKeyword's begin/asm
# bail exists to protect (see JoinRoutineHeaders' DocInsight): the call's own
# '(' stays open while the anon method's inline `procedure(` matches
# IsHeaderStart (Case B), so the accumulation loop starts scanning -- but it
# must still abort the moment `begin` appears, discarding whatever it
# accumulated and re-emitting the ORIGINAL lines verbatim (Aborted always
# emits Lines[i..j-1], never the built-up Joined string -- see the
# block-keyword bail comment in JoinRoutineHeaders). The anon method's OWN
# header here is ALSO split across two lines with the second starting
# "const" -- exactly the leading word just removed from the bail set -- to
# prove that removal does not let this construct bleed into a mis-join
# before `begin` is reached: the const-led continuation is scanned (no
# longer an immediate bail) but the whole span still correctly bails, intact
# and unmodified, the moment `begin` follows.
# NOTE (deviation, same reason as the $call fixture above): a SHORT anon
# header (e.g. `SomeCall(procedure(X: Integer; const Y: string)`) is
# collapsed onto one physical line by the pre-existing Stage-2 structural
# emitter (InlineRenderRange) -- same as it did for a short flat call --
# BEFORE JoinRoutineHeaders ever runs, so it never reaches this pass as a
# genuinely split span at all. Verified empirically against the real binary.
# Long-enough names push the anon header itself over MaxLen so Stage 2
# leaves it genuinely split across 2 physical lines for JoinRoutineHeaders
# to (correctly) leave alone.
$acSrc = Join-Path $env:TEMP 'jh_anon_src.pas'
@'
unit probe;
interface
implementation
procedure Demo;
begin
  DoStuffWithAVeryVeryVeryVeryVeryVeryLongNameThatWontFitOnOneLineAtAllNoMatterWhat(procedure(AlphaParameterNameIsQuiteLongIndeedYes: Integer;
    const BetaParameterNameIsQuiteLongTooYesIndeed: string)
  begin
    DoSomething(AlphaParameterNameIsQuiteLongIndeedYes, BetaParameterNameIsQuiteLongTooYesIndeed);
  end);
end;
end.
'@ | Set-Content $acSrc -Encoding ascii
$acO1 = Join-Path $env:TEMP 'jh_anon1.pas'; $acO2 = Join-Path $env:TEMP 'jh_anon2.pas'
& $exe --ini $ini $acSrc --o $acO1 | Out-Null
$ac = Get-Content $acO1 -Raw
MustMatch $ac '(?m)^\s*DoStuffWithAVeryVeryVeryVeryVeryVeryLongNameThatWontFitOnOneLineAtAllNoMatterWhat\(procedure\(AlphaParameterNameIsQuiteLongIndeedYes: Integer;\s*$' 'anon-method guard: call + inline header opener left on its own line'
MustMatch $ac '(?m)^\s*const BetaParameterNameIsQuiteLongTooYesIndeed: string\)\s*$'                                                                                      'anon-method guard: const-led continuation of the ANON method itself left on its own line, not folded into line 1'
MustMatch $ac '(?m)^\s*begin\s*$'                                                                                                                                         'anon-method guard: begin still starts its own line (never joined into the header)'
MustMatch $ac '(?m)^\s*DoSomething\(AlphaParameterNameIsQuiteLongIndeedYes, BetaParameterNameIsQuiteLongTooYesIndeed\);\s*$'                                              'anon-method guard: body statement untouched'
MustMatch $ac '(?m)^\s*end\);\s*$'                                                                                                                                        'anon-method guard: closing end); untouched'
& $exe --ini $ini $acO1 --o $acO2 | Out-Null
if ((Get-FileHash $acO1).Hash -ne (Get-FileHash $acO2).Hash) { Fail 'idempotent: anon-method guard' }
$acchk = & $exe --ini $ini --check $acO1 2>&1
if ("$acchk" -notmatch 'PASS') { Fail 'roundtrip/guard: anon-method guard' }
Remove-Item $acSrc,$acO1,$acO2 -Force -ErrorAction SilentlyContinue

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

# ----- REGRESSION (const/var bail-set fix): a header split across 3 lines,
# where continuation line 2 starts with "const" and line 3 starts with "var"
# -- ordinary Delphi parameter modifiers (e.g. `const D: TSomeType`), NOT the
# tell-tale of an anonymous method's own block/section opening inside a
# still-open call paren (that tell-tale is `begin`/`asm` alone -- see the
# $anonCall guard fixture above) -- must still JOIN, and since the joined
# result overflows MaxLen, WRAP, rather than bail and stay split.
# RED (confirmed against the pre-fix exe): StartsBlockKeyword wrongly
# included const/var in its bail set, so line 2 ("const Gamma...") tripped
# the block-keyword bail before line 3 was even scanned -- the header stayed
# split exactly as authored (3 physical lines, unjoined) and every assertion
# below failed.
# GREEN (post-fix, const/var removed from the bail set): the header joins
# through BOTH the const-led and var-led continuations, then WrapHeaderLine
# greedy-wraps the over-180 result.
# This replaces the OLDER $cvSrc fixture that lived here (Task-2 review Minor
# #1: mislabeled). That fixture's own comment described "pass 1 joins, only
# pass 2 bails on a re-fed wrapped continuation" -- but with const still in
# the PRE-FIX bail set, pass 1 ALSO bailed (identically to pass 2), so it
# never actually exercised a join at all, only the same verbatim bail shape
# twice in a row (still idempotent, but not for the reason the comment
# claimed). This fixture folds in the same idempotency + Guard round-trip
# coverage the old one provided, now over a genuine join+wrap.
$cvSrc = Join-Path $env:TEMP 'jh_constvar_wrap.pas'
@'
unit probe;
interface
implementation
function ProbeConstVarJoin(AlphaParamNameQuiteLongXXXXXXXXXXXXXXXXXXXX: TAlphaTypeNameQuiteLong; BetaParamNameQuiteLongYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY: TBetaTypeNameQuiteLong;
  const GammaParamNameQuiteLong: TGammaTypeNameQuiteLong;
  var DeltaParamNameQuiteLong: TDeltaTypeNameQuiteLong): Boolean;
begin
  Result := True;
end;
end.
'@ | Set-Content $cvSrc -Encoding ascii
$cvo1 = Join-Path $env:TEMP 'jh_cv1.pas'; $cvo2 = Join-Path $env:TEMP 'jh_cv2.pas'
& $exe --ini $ini $cvSrc --o $cvo1 | Out-Null
$cv = Get-Content $cvo1 -Raw
foreach ($ln in ($cv -split "`r`n" | Where-Object { $_ -match 'ParamNameQuiteLong' })) {
  if ($ln.Length -gt 180) { Fail "const/var join: wrapped line exceeds MaxLen: <$ln>" }
}
MustMatch    $cv '(?m)^function ProbeConstVarJoin\b.*;\s*$' 'const/var join: first line still starts the header and ends at a ; separator'
MustNotMatch $cv '(?m)^\s*[;,]' 'const/var join: no continuation line starts with a dangling separator'
MustMatch    $cv 'BetaParamNameQuiteLong.*const GammaParamNameQuiteLong' 'const/var join: Beta (originally line 1) and the const-led parameter (originally line 2) now share one output line -- proves an actual cross-line join, not a bail'
MustNotMatch $cv '(?m)^\s*const GammaParamNameQuiteLong: TGammaTypeNameQuiteLong;\s*$' 'const/var join: the original const-only continuation line no longer stands alone -- header is no longer one-param-per-line-as-source'
& $exe --ini $ini $cvo1 --o $cvo2 | Out-Null
if ((Get-FileHash $cvo1).Hash -ne (Get-FileHash $cvo2).Hash) { Fail 'idempotent: const/var join + wrap' }
$cvchk = & $exe --ini $ini --check $cvo1 2>&1
if ("$cvchk" -notmatch 'PASS') { Fail 'roundtrip/guard: const/var join + wrap' }
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

# ----- Casing fidelity: JoinRoutineHeaders/WrapHeaderLine never re-case a
# token -- both copy text verbatim (Trim + single-space join for the join;
# straight substring slicing for the wrap). The ONLY pass that changes
# keyword casing is the separate LowercaseKeywords option; this fixture
# proves the join+wrap sit downstream of it without adding any casing
# of their own.
#
# CRITICAL: the header below must OVERFLOW MaxLen (180), same reasoning as
# the $call/$ac fixtures above -- a short, comment-free header is already
# collapsed onto one line by the pre-existing Stage-2 structural emitter
# (InlineRenderRange, which inlines ANY comment-free parens group that fits
# under MaxLen) before JoinRoutineHeaders ever runs. A short casing fixture
# would prove Stage-2's casing fidelity, not this pass's. The parameter
# names below push the joined header to 222 chars, so WrapHeaderLine's
# greedy wrap fires too -- confirmed empirically to break the header into
# two lines at a DIFFERENT position than the source's own 2-line split
# (source breaks after "TBytesArrayTypeName;"; formatted output breaks
# after "IThingInterfaceTypeName;" instead) -- proof the pass actually
# re-joined then re-wrapped, not merely left the source's own line break
# alone.
#
# NOTE: TestLib's MustMatch/MustNotMatch use PowerShell's `-match`/
# `-notmatch` operators, which are CASE-INSENSITIVE by default (a regex
# 'FUNCTION' matches the text "function" too) -- so they cannot, by
# themselves, prove casing fidelity: a hypothetical bug that lowercased
# every keyword would still satisfy `MustMatch $c 'FUNCTION ...'`. The
# assertions that actually prove the casing claims below use `-cmatch` /
# `-cnotmatch` (case-SENSITIVE) directly and call Fail on mismatch, the
# same direct-Fail idiom the MaxLen-overflow loops above already use.
$caseSrcLines = @(
  'unit probe;'
  'interface'
  'implementation'
  'FUNCTION BarBarBarBarBarBarBarBarBar(CONST AlphaParameterNameQuiteLong: TBytesArrayTypeName;'
  '  VAR BetaParameterNameQuiteLongToo: IThingInterfaceTypeName; OUT GammaParameterOutNameQuiteLong: TCommandRecordTypeName): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)

# Default ini (LowercaseKeywords=true): the join+wrap still fires (same
# 222-char overflow; case does not change string length, so the break lands
# at the identical position), and the SEPARATE LowercaseKeywords pass
# lowercases the reserved words as usual -- a sanity check that this
# feature does not disturb the default pipeline.
$caseDef = Fmt $caseSrcLines
foreach ($ln in ($caseDef -split "`r`n" | Where-Object { $_ -match 'ParameterNameQuiteLong|ParameterOutNameQuiteLong' })) {
  if ($ln.Length -gt 180) { Fail "case(default): wrapped line exceeds MaxLen: <$ln>" }
}
if ($caseDef -cnotmatch '(?m)^function BarBarBarBarBarBarBarBarBar\(const AlphaParameterNameQuiteLong: TBytesArrayTypeName; var BetaParameterNameQuiteLongToo: IThingInterfaceTypeName;\s*$') {
  Fail 'case(default): lowercased function/const/var not found verbatim on header line 1 (default LowercaseKeywords regressed)'
}
# NOTE: "OUT" is deliberately NOT asserted to lowercase here. Verified
# independently (a short, non-overflowing "FUNCTION Bar(CONST A: TBytes; VAR
# B: Integer; OUT D: TCmd): Boolean;" probe that never reaches
# JoinRoutineHeaders at all, since it fits inline under Stage-2) that
# LowercaseKeywords leaves a source-uppercase OUT as OUT even with the
# option ON -- a pre-existing token-classification characteristic of that
# SEPARATE pass (out/const/var are all "reserved words" in the language, but
# apparently not all tagged the same lexer token kind), unrelated to this
# join/wrap feature and out of this task's scope. This assertion only needs
# the wrap SHAPE to survive under default casing; MustMatch is
# case-insensitive so it does not itself assert either casing.
MustMatch $caseDef '(?m)^\s*OUT GammaParameterOutNameQuiteLong: TCommandRecordTypeName\): Boolean;\s*$' 'case(default): wrapped continuation line shape unaffected by default casing'

# --no-lowercase-keywords: turn the ONLY casing-changing pass off. The join
# copies tokens verbatim and the wrap only inserts line breaks/indent, so the
# source's uppercase FUNCTION/CONST/VAR/OUT must survive exactly as typed,
# split across the SAME two physical lines as above (identical break
# position -- casing does not change string length).
$srcC = Join-Path $env:TEMP 'jh_case.pas'
$outC = Join-Path $env:TEMP 'jh_case_out.pas'
$caseSrcLines -join "`r`n" | Set-Content $srcC -Encoding ascii
& $exe --ini $ini $srcC --no-lowercase-keywords --o $outC | Out-Null
$c = Get-Content $outC -Raw
foreach ($ln in ($c -split "`r`n" | Where-Object { $_ -match 'ParameterNameQuiteLong|ParameterOutNameQuiteLong' })) {
  if ($ln.Length -gt 180) { Fail "case(--no-lowercase-keywords): wrapped line exceeds MaxLen: <$ln>" }
}
if ($c -cnotmatch '(?m)^FUNCTION BarBarBarBarBarBarBarBarBar\(CONST AlphaParameterNameQuiteLong: TBytesArrayTypeName; VAR BetaParameterNameQuiteLongToo: IThingInterfaceTypeName;\s*$') {
  Fail 'case: FUNCTION/CONST/VAR casing not preserved verbatim on header line 1 after join+wrap'
}
if ($c -cnotmatch '(?m)^\s*OUT GammaParameterOutNameQuiteLong: TCommandRecordTypeName\): Boolean;\s*$') {
  Fail 'case: OUT casing not preserved verbatim on the wrapped continuation line'
}
Remove-Item $srcC,$outC -Force -ErrorAction SilentlyContinue

# ----- Compile gate: the joined/wrapped output is valid Delphi (dcc64) -----
# Mirrors the pattern in Test\test_break_control.ps1's Task 4 compile gate.
# Fixture covers the three shapes this pass acts on: a proc-type declaration
# (TCb), a class method header (TFoo.Go), and a routine header long enough
# to overflow (194 chars > MaxLen 180) and greedy-wrap (VeryLongRoutineName).
$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
if (Test-Path $dcc) {
  $ns   = 'System;System.Win;Winapi;Vcl;Data;Soap;Xml'
  $cdir = Join-Path $env:TEMP ('jh_c_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $cdir | Out-Null
  $csrc = Join-Path $cdir 'jh_compile.pas'   # file name must equal unit name
  @'
unit jh_compile;
interface
type
  TCb = procedure(Sender: TObject;
    const Msg: string) of object;
  TFoo = class
    procedure Go(const A: Integer;
      B: Integer); virtual;
  end;
implementation
procedure TFoo.Go(const A: Integer;
  B: Integer);
begin
end;
function VeryLongRoutineName(const AlphaParameter: Integer; BetaParameter: Integer;
  GammaParameter: Integer; DeltaParameter: Integer; EpsilonParameter: Integer;
  ZetaParameter: Integer): Boolean;
begin
  Result := True;
end;
end.
'@ | Set-Content $csrc -Encoding ascii
  # format IN PLACE, then compile the joined/wrapped result.
  & $exe $csrc --ini $ini --o $csrc | Out-Null
  & $dcc -Q "-NS$ns" "-N0$cdir" "-E$cdir" $csrc *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'compile: joined/wrapped output must compile with dcc64' }
  Remove-Item $cdir -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Output 'join_headers: (dcc64 not found -- skipping compile check)'
}

# ----- REGRESSION (defensive lock-in, reviewer-recommended): a routine header
# whose parameter list is interrupted by a genuinely MULTI-LINE token (a { }
# or (* *) block comment spanning >1 physical line, or a multi-line string
# default) must not corrupt the file or trigger a whole-file Guard decline.
#
# This safety is REAL, but it does NOT live inside JoinRoutineHeaders: YADF's
# pre-existing multi-line-token shield (ShieldMultilineTokens /
# UnshieldMultilineTokens, YADF.Layout.pas) replaces every multi-line string
# and block-comment TOKEN with an opaque ONE-LINE sentinel before Stage 2
# (structural emission) ever runs, and restores the original text verbatim
# only at Stage 5 -- AFTER JoinRoutineHeaders (Stage 3) and BEFORE Stage 6
# Guard. So by the time JoinRoutineHeaders' line-based scanner sees the file,
# a multi-line comment/string has already been collapsed to one line; the
# pass never actually observes a raw multi-line span for these tokens. The
# Task-1 regression fixed above ($cmt, $m1) was exactly this shape of bug for
# `//` line comments (NOT shielded -- a `//` comment is already one token on
# one line, so JoinRoutineHeaders' OWN cross-line scanner has to get it right
# directly). This fixture locks in the OTHER half: block comments and
# multi-line strings, which route through the shield instead. If a future
# change reordered the pipeline (e.g. ran JoinRoutineHeaders before the
# shield) or narrowed which token kinds get shielded, this is the fixture
# that would catch it -- via the same "whole-file decline" symptom (X:= 1;
# stays X := 1;) the Task-1 bug produced.
#
# Empirically verified asymmetry (not itself asserted as a requirement, just
# documented so a future reader is not surprised): the { } / (* *) sentinels
# are still COMMENT-shaped tokens post-shield (MlComSentinel produces a
# one-line `{...}` brace comment), so WalkGroup/JoinRoutineHeaders' existing
# "do not join across a comment" caution still applies -- the header is left
# split exactly as authored. The multi-line STRING sentinel (MlStrSentinel)
# is a plain one-line string CONSTANT, not comment-shaped, so it does not
# block the join -- JoinRoutineHeaders pulls the trailing parameter onto the
# same line as the closing sentinel. Both are safe; they just differ in
# shape, because the "comment blocks joining" rule keys off token kind, not
# token content.

# --- (a) { ... } block comment spanning the parameter list ---
$mlbSrc = Join-Path $env:TEMP 'jh_mlbrace_src.pas'
@'
unit probe;
interface
implementation
function Foo(A: Integer; { this comment
  runs across two lines } B: string): Boolean;
begin
  X := 1;
end;
end.
'@ | Set-Content $mlbSrc -Encoding ascii
$mlbO1 = Join-Path $env:TEMP 'jh_mlbrace_o1.pas'; $mlbO2 = Join-Path $env:TEMP 'jh_mlbrace_o2.pas'
& $exe --ini $ini $mlbSrc --o $mlbO1 | Out-Null
$mlb = Get-Content $mlbO1 -Raw
MustMatch   $mlb '(?m)^\s*X:= 1;\s*$' 'brace-comment header: file still formatted (not Guard-declined)'
MustContain $mlb "function Foo(A: Integer; { this comment`r`n  runs across two lines } B: string): Boolean;" 'brace-comment header: multi-line comment + surrounding header tokens survive verbatim'
& $exe --ini $ini $mlbO1 --o $mlbO2 | Out-Null
if ((Get-FileHash $mlbO1).Hash -ne (Get-FileHash $mlbO2).Hash) { Fail 'idempotent: brace-comment header' }
$mlbchk = & $exe --ini $ini --check $mlbO1 2>&1
if ("$mlbchk" -notmatch 'PASS') { Fail 'roundtrip/guard: brace-comment header' }
Remove-Item $mlbSrc,$mlbO1,$mlbO2 -Force -ErrorAction SilentlyContinue

# --- (b) (* ... *) block comment spanning the parameter list ---
$mlaSrc = Join-Path $env:TEMP 'jh_mlansi_src.pas'
@'
unit probe;
interface
implementation
function Foo(A: Integer; (* this comment
  runs across two lines *) B: string): Boolean;
begin
  X := 1;
end;
end.
'@ | Set-Content $mlaSrc -Encoding ascii
$mlaO1 = Join-Path $env:TEMP 'jh_mlansi_o1.pas'; $mlaO2 = Join-Path $env:TEMP 'jh_mlansi_o2.pas'
& $exe --ini $ini $mlaSrc --o $mlaO1 | Out-Null
$mla = Get-Content $mlaO1 -Raw
MustMatch   $mla '(?m)^\s*X:= 1;\s*$' 'ansi-comment header: file still formatted (not Guard-declined)'
MustContain $mla "function Foo(A: Integer; (* this comment`r`n  runs across two lines *) B: string): Boolean;" 'ansi-comment header: multi-line comment + surrounding header tokens survive verbatim'
& $exe --ini $ini $mlaO1 --o $mlaO2 | Out-Null
if ((Get-FileHash $mlaO1).Hash -ne (Get-FileHash $mlaO2).Hash) { Fail 'idempotent: ansi-comment header' }
$mlachk = & $exe --ini $ini --check $mlaO1 2>&1
if ("$mlachk" -notmatch 'PASS') { Fail 'roundtrip/guard: ansi-comment header' }
Remove-Item $mlaSrc,$mlaO1,$mlaO2 -Force -ErrorAction SilentlyContinue

# --- (c) multi-line ('''...''') string literal as a parameter default ---
$mlsSrc = Join-Path $env:TEMP 'jh_mlstr_src.pas'
@'
unit probe;
interface
implementation
function Foo(A: Integer; B: string = '''
multi
line default''';
  C: Boolean): Boolean;
begin
  X := 1;
end;
end.
'@ | Set-Content $mlsSrc -Encoding ascii
$mlsO1 = Join-Path $env:TEMP 'jh_mlstr_o1.pas'; $mlsO2 = Join-Path $env:TEMP 'jh_mlstr_o2.pas'
& $exe --ini $ini $mlsSrc --o $mlsO1 | Out-Null
$mls = Get-Content $mlsO1 -Raw
MustMatch   $mls '(?m)^\s*X:= 1;\s*$' 'multi-line-string-default header: file still formatted (not Guard-declined)'
MustContain $mls "function Foo(A: Integer; B: string = '''`r`nmulti`r`nline default'''; C: Boolean): Boolean;" 'multi-line-string-default header: string interior + surrounding header tokens survive verbatim (JoinRoutineHeaders pulls the trailing param onto the sentinel line; unshield then restores the real multi-line value)'
& $exe --ini $ini $mlsO1 --o $mlsO2 | Out-Null
if ((Get-FileHash $mlsO1).Hash -ne (Get-FileHash $mlsO2).Hash) { Fail 'idempotent: multi-line-string-default header' }
$mlschk = & $exe --ini $ini --check $mlsO1 2>&1
if ("$mlschk" -notmatch 'PASS') { Fail 'roundtrip/guard: multi-line-string-default header' }
Remove-Item $mlsSrc,$mlsO1,$mlsO2 -Force -ErrorAction SilentlyContinue

# ----- REGRESSION (idempotency): a header whose CODE fits MaxLen but whose
# TRAILING `//` note pushes the PHYSICAL line past it must be left alone.
# yadf.ini documents the policy this locks in: "Lines containing string
# literals or // line-comments may extend past this without being broken
# (those exceptions are by design)". WrapHeaderLine measured the full
# physical line instead, so the rightmost separator that still "fitted" was
# the header's OWN terminating ';' -- and breaking after it pushed the note
# onto a continuation line at (indent + AOpts.Indent), i.e. column 2.
#
# That break is NOT reproducible on a second pass: the header alone now fits,
# so JoinRoutineHeaders emits it as-is (single-physical-line branch) and never
# calls WrapHeaderLine at all, leaving the note as an ordinary comment-only
# line -- which ReindentByDepth then re-indents to the routine's structural
# depth, column 0. So pass 1 wrote column 2 and pass 2 wrote column 0:
# format(format(x)) <> format(x) on YADF's OWN YADF.Layout.pas, the tool
# violating its core guarantee on the file it is written in.
#
# Requires a `, ` at paren depth 1 (two grouped parameters): that comma is the
# greedy breaker's only candidate on a header line, so it splits the parameter
# list first, which is what makes JoinRoutineHeaders re-join the header and
# reach WrapHeaderLine at all. --no-break-expr selects that greedy breaker.
# RED (pre-fix): note moves to its own line at column 2, then to column 0.
$tnSrc = Join-Path $env:TEMP 'jh_trailnote.pas'
@'
unit probe;
interface
implementation
function ProbeTrailingNote(const S: string; AlphaFlagName, BetaFlagName: Boolean): string;  // dl:ok note aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
var
  L: Integer;
begin
  Result := '';
end;
end.
'@ | Set-Content $tnSrc -Encoding ascii
$tno1 = Join-Path $env:TEMP 'jh_tn1.pas'; $tno2 = Join-Path $env:TEMP 'jh_tn2.pas'
& $exe --ini $ini $tnSrc --no-break-expr --o $tno1 | Out-Null
& $exe --ini $ini $tno1  --no-break-expr --o $tno2 | Out-Null
$tn = Get-Content $tno1 -Raw
# The header's code fits (90 chars); only the note takes it past 180.
MustMatch    $tn '(?m)^function ProbeTrailingNote\(const S: string; AlphaFlagName, BetaFlagName: Boolean\): string; // dl:ok note a+\s*$' 'trailing-note header: code + note stay together on ONE line (note may exceed MaxLen by design)'
MustNotMatch $tn '(?m)^\s*// dl:ok note'                                                                                                'trailing-note header: note is never pushed onto a continuation line of its own'
if ((Get-FileHash $tno1).Hash -ne (Get-FileHash $tno2).Hash) { Fail 'idempotent: trailing-note header (note drifts column 2 -> column 0 on pass 2)' }
$tnchk = & $exe --ini $ini --check $tno1 2>&1
if ("$tnchk" -notmatch 'PASS') { Fail 'roundtrip/guard: trailing-note header' }
Remove-Item $tnSrc,$tno1,$tno2 -Force -ErrorAction SilentlyContinue

# ----- CORRECTION: a trailing directive the source split onto its OWN line
# (e.g. `overload;` / `stdcall;` on the physical line right after the header's
# terminating `;`) is pulled back onto the header line, MaxLen permitting --
# rather than left dangling on its own line. -----
$dirOwn = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function Foo(A: Integer): Integer;'
  '  overload;'
  'begin'
  '  Result := A;'
  'end;'
  'procedure Bar(A: Integer);'
  '  stdcall;'
  'begin'
  'end;'
  'end.'
)
MustMatch    $dirOwn '(?m)^function Foo\(A: Integer\): Integer; overload;\s*$'    'trailing directive on its own line joined onto the header (overload)'
MustMatch    $dirOwn '(?m)^procedure Bar\(A: Integer\); stdcall;\s*$'            'trailing directive on its own line joined onto the header (stdcall)'
MustNotMatch $dirOwn '(?m)^\s*overload;\s*$'                                     'no leftover directive-only line (overload)'
MustNotMatch $dirOwn '(?m)^\s*stdcall;\s*$'                                      'no leftover directive-only line (stdcall)'

# Multiple directive clauses each on their own line all ride up together.
$dirMulti = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'procedure Baz(A: Integer);'
  '  virtual;'
  '  abstract;'
  'end.'
)
MustMatch $dirMulti '(?m)^procedure Baz\(A: Integer\); virtual; abstract;\s*$' 'multiple directive-only lines all joined onto the header'

# Idempotency: re-running the already-joined output is a no-op.
$dirSrc = Join-Path $env:TEMP 'jh_dir.pas'
$dirO1  = Join-Path $env:TEMP 'jh_dir1.pas'
$dirO2  = Join-Path $env:TEMP 'jh_dir2.pas'
@'
unit probe;
interface
implementation
function Foo(A: Integer): Integer;
  overload;
begin
  Result := A;
end;
end.
'@ | Set-Content $dirSrc -Encoding ascii
& $exe --ini $ini $dirSrc --o $dirO1 | Out-Null
& $exe --ini $ini $dirO1  --o $dirO2 | Out-Null
if ((Get-FileHash $dirO1).Hash -ne (Get-FileHash $dirO2).Hash) { Fail 'idempotent: directive-on-own-line join is stable on a second pass' }
Remove-Item $dirSrc,$dirO1,$dirO2 -Force -ErrorAction SilentlyContinue

Finish 'join_headers'
