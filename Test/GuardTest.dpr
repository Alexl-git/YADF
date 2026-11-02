program GuardTest;

{ Console tests for YADF.Guard -- the post-format content-preservation
  safety net. Style mirrors OptionsTest.dpr: plain Check() procedures,
  ExitCode = failure count. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  YADF.Tokens in '..\YADF.Tokens.pas',
  YADF.Options in '..\YADF.Options.pas',
  YADF.Groups in '..\YADF.Groups.pas',
  YADF.Debug in '..\YADF.Debug.pas',
  YADF.LineScan in '..\YADF.LineScan.pas',
  YADF.Layout in '..\YADF.Layout.pas',
  YADF.Guard in '..\YADF.Guard.pas';

var
  GFailures: Integer = 0;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then
    Writeln('ok   - ', AName)
  else
  begin
    Writeln('FAIL - ', AName);
    Inc(GFailures);
  end;
end;

const
  CRLF = #13#10;

// --- cases where the formatter behaved: guard must pass -------------------

procedure TestAcceptsLegitimateFormatting;
const
  Original =
    'unit U;'   + CRLF +
    'interface' + CRLF +
    'const'     + CRLF +
    '  S = ''hello'';  // greeting' + CRLF +
    '{$IFDEF  foo }'    + CRLF +
    '  N = 1;'  + CRLF +
    '{$ENDIF}'  + CRLF +
    'implementation' + CRLF +
    'end.' + CRLF;
begin
  Check('identical text passes',
    FormatPreservesContent(Original, Original));
  Check('whitespace-only reformat passes',
    FormatPreservesContent(Original,
      StringReplace(Original, '  S', '      S', [])));
  Check('code keyword case change passes (code tokens not compared)',
    FormatPreservesContent(Original,
      StringReplace(Original, 'const', 'CONST', [])));
  Check('directive case + inner whitespace normalization passes',
    FormatPreservesContent(Original,
      StringReplace(Original, '{$IFDEF  foo }', '{$IFDEF FOO}', [])));
  Check('trailing spaces trimmed inside a // comment pass',
    FormatPreservesContent('X; // note   ' + CRLF, 'X; // note' + CRLF));
  Check('formatter-added trailing comment passes (subsequence rule)',
    FormatPreservesContent(
      'begin' + CRLF + 'X;' + CRLF + 'end;' + CRLF,
      'begin' + CRLF + 'X;' + CRLF + 'end; // end of X' + CRLF));
  Check('LF input vs CRLF output inside block comment passes',
    FormatPreservesContent('{ two' + #10 + '  lines }' + #10,
      '{ two' + CRLF + '  lines }' + CRLF));
  Check('char-literal hex case change passes',
    FormatPreservesContent('C := #$ab;', 'C := #$AB;'));
end;

// --- corruption cases: guard must refuse ----------------------------------

procedure TestRejectsDroppedInclude;
begin
  Check('dropped {$I file} rejected',
    not FormatPreservesContent(
      'unit U;' + CRLF + '{$I opts.inc}' + CRLF + 'end.',
      'unit U;' + CRLF + 'end.'));
end;

procedure TestRejectsCommentDamage;
begin
  Check('dropped comment rejected',
    not FormatPreservesContent(
      'X := 1; // keep me' + CRLF + 'Y := 2;',
      'X := 1;' + CRLF + 'Y := 2;'));
  Check('code swallowed into comment rejected (merge-over-comment bug)',
    not FormatPreservesContent(
      'A, // first' + CRLF + 'B' + CRLF,
      'A, // first B' + CRLF));
  Check('block comment interior collapse rejected',
    not FormatPreservesContent(
      '{ spaced    out    interior }',
      '{ spaced out interior }'));
end;

procedure TestRejectsStringDamage;
begin
  Check('altered string literal rejected',
    not FormatPreservesContent('S := ''a  b'';', 'S := ''a b'';'));
  Check('dropped string literal rejected',
    not FormatPreservesContent('S := ''a'' + ''b'';', 'S := ''a'';'));
  Check('multiline string interior change rejected',
    not FormatPreservesContent(
      'S := ''''''' + CRLF + '  keep   this' + CRLF + ''''''';',
      'S := ''''''' + CRLF + '  keep this' + CRLF + ''''''';'));
end;

// Review 2026-10-14: damage the three original content streams cannot see.
procedure TestRejectsReviewFindings;
const
  AsmSrc = 'procedure P;' + CRLF + 'asm' + CRLF + '  mov eax, 1' + CRLF + '  add eax, 2' + CRLF + 'end;';
begin
  Check('asm instruction lines joined rejected',
    not FormatPreservesContent(AsmSrc,
      'procedure P;' + CRLF + 'asm' + CRLF + '  mov eax, 1 add eax, 2' + CRLF + 'end;'));
  Check('asm mnemonic re-cased rejected',
    not FormatPreservesContent(AsmSrc,
      'procedure P;' + CRLF + 'asm' + CRLF + '  mov eax, 1' + CRLF + '  Add eax, 2' + CRLF + 'end;'));
  Check('asm body re-indented passes',
    FormatPreservesContent(AsmSrc,
      'procedure P;' + CRLF + 'asm' + CRLF + '    mov  eax, 1' + CRLF + #9'add eax, 2' + CRLF + 'end;'));
  Check('include-shield marker leaked into output rejected',
    not FormatPreservesContent('S := ''{$I a.inc}'';', 'S := ''{$IZQYADF a.inc}'';'));
  Check('layout sentinel leaked into output rejected',
    not FormatPreservesContent('X := 1;', 'X := 1; //__YADF_ASM_0__'));
  Check('marker already in the input is not a leak',
    FormatPreservesContent('S := ''ZQYADF'';', 'S  :=  ''ZQYADF'';'));
  Check('asm lines after an @@End label are still compared',
    not FormatPreservesContent(
      'asm' + CRLF + '  jnz @@End' + CRLF + '  mov eax, 1' + CRLF + '@@End:' + CRLF + '  ret' + CRLF + 'end;',
      'asm' + CRLF + '  jnz @@End' + CRLF + '  mov eax, 1 @@End:' + CRLF + '  ret' + CRLF + 'end;'));
  Check('one-character literal case change rejected',
    not FormatPreservesContent('C := ''A'';', 'C := ''a'';'));
end;

// The extended overload: BreakCaseLabels duplicates arm bodies (strings
// included), so with AAllowStringDuplication the original sequence need only
// survive IN ORDER; loss/alteration still fails, and AReason names the cause.
procedure TestDuplicationToleranceAndReason;
var
  Reason: string;
begin
  Check('strict mode rejects duplicated string',
    not FormatPreservesContent('1, 2: Log(''x'');', '1: Log(''x''); 2: Log(''x'');', False, False, Reason));
  Check('strict rejection carries a reason', Reason <> '');
  Check('duplication-tolerant mode accepts duplicated string',
    FormatPreservesContent('1, 2: Log(''x'');', '1: Log(''x''); 2: Log(''x'');', True, False, Reason));
  Check('acceptance carries empty reason', Reason = '');
  Check('duplication-tolerant mode still rejects a LOST string',
    not FormatPreservesContent('S := ''a'' + ''b'';', 'S := ''a'';', True, False, Reason));
  Check('lost-string reason names the stream', Pos('string', Reason) > 0);
  Check('duplication-tolerant mode still rejects an ALTERED string',
    not FormatPreservesContent('S := ''a  b'';', 'S := ''a b'';', True, False, Reason));
  Check('directives stay strict under duplication tolerance',
    not FormatPreservesContent('{$IFDEF X} A; {$ENDIF}', '{$IFDEF X} A; {$ENDIF} {$IFDEF X} B; {$ENDIF}', True, False, Reason));
  Check('dropped-comment reason names the stream',
    (not FormatPreservesContent('X; { note }', 'X;', False, False, Reason)) and (Pos('comment', Reason) > 0));
end;

// AAllowLabelRemoval: LabelLongBlocks may DELETE a stale block-end marker, so
// one exact-match marker is allowed to go missing. The point of these cases is
// that the hole is exactly that size and no bigger -- if any of them starts
// passing, the relaxation has widened into "the formatter may drop comments".
procedure TestLabelRemovalTolerance;
const
  // A `while` block. The marker this formatter would write for that `end` is
  // `// while` -- and only `// while`.
  Loop =
    'begin'          + CRLF +
    '  while A do'   + CRLF +
    '  begin'        + CRLF +
    '    B;'         + CRLF +
    '  end; %s'      + CRLF +
    'end;'           + CRLF;
  Bare =
    'begin'          + CRLF +
    '  while A do'   + CRLF +
    '  begin'        + CRLF +
    '    B;'         + CRLF +
    '  end;'         + CRLF +
    'end;'           + CRLF;
var
  Reason: string;
begin
  Check('strict mode rejects a dropped block-end marker',
    not FormatPreservesContent(Format(Loop, ['// while']), Bare, False, False, Reason));
  Check('label-removal mode accepts the marker it would itself have written',
    FormatPreservesContent(Format(Loop, ['// while']), Bare, False, True, Reason));
  Check('label-removal acceptance carries empty reason', Reason = '');

  // THE NARROWNESS PROOF: an ordinary comment is still rejected, with reason.
  Check('label-removal mode still rejects a dropped ORDINARY comment',
    not FormatPreservesContent(
      'X := 1; // keep me' + CRLF + 'Y := 2;',
      'X := 1;' + CRLF + 'Y := 2;', False, True, Reason));
  Check('ordinary dropped comment still names the comment stream', Pos('comment', Reason) > 0);
  Check('ordinary dropped comment reason previews the comment', Pos('keep me', Reason) > 0);

  // Rule 3: the keyword must be the one computed for THIS block. `procedure`
  // is in the sixteen-keyword set, but this `end` closes a `while`.
  Check('a keyword-set marker naming a DIFFERENT construct is still protected',
    not FormatPreservesContent(Format(Loop, ['// procedure']), Bare, False, True, Reason));
  Check('trailing prose after the keyword is still protected',
    not FormatPreservesContent(Format(Loop, ['// while -- see ticket 42']), Bare, False, True, Reason));
  Check('a marker without the space after // is still protected',
    not FormatPreservesContent(Format(Loop, ['//while']), Bare, False, True, Reason));
  Check('a brace comment naming the keyword is still protected',
    not FormatPreservesContent(Format(Loop, ['{ while }']), Bare, False, True, Reason));

  // The exception is POSITIONAL, not textual: `// while` standing on its own
  // line trails no `end`, so it is an ordinary comment and stays protected even
  // though a marker elsewhere in the same file may say exactly that.
  Check('a lone // while comment that trails no end is still protected',
    not FormatPreservesContent(
      '// while' + CRLF + Format(Loop, ['// while']),
      Bare, False, True, Reason));
  // Ordinary comments still may not be reordered under the relaxation.
  Check('label-removal mode still rejects REORDERED ordinary comments',
    not FormatPreservesContent(
      'A; // one' + CRLF + 'B; // two' + CRLF,
      'A; // two' + CRLF + 'B; // one' + CRLF, False, True, Reason));
  Check('strings stay strict under label-removal tolerance',
    not FormatPreservesContent('S := ''a'' + ''b'';', 'S := ''a'';', False, True, Reason));
  Check('directives stay strict under label-removal tolerance',
    not FormatPreservesContent('{$I opts.inc}' + CRLF + 'end.', 'end.', False, True, Reason));
end;

// --- YADF.LineScan: the shared line scanner --------------------------------

// Walks ALine with the shared scanner, returning only the CODE characters
// (string literals and comment interiors skipped). Stops at a // comment.
// AState carries block-comment state across calls (i.e. across lines).
function CodeChars(var AState: TLineScanState; const ALine: string): string;
var
  i: Integer;
begin
  Result:= '';
  AState.BeginLine;
  i:= 1;
  while True do
    case AState.SkipNonCode(ALine, i) of
      seEndOfLine  : Exit;
      seLineComment: Exit;
      seCode:
        begin
          Result:= Result + ALine[i];
          AState.StepCode(ALine, i);
        end;
    end;
end;

procedure TestLineScanCore;
var
  St: TLineScanState;
begin
  St.Reset;
  Check('string with doubled-quote escape fully skipped',
    CodeChars(St, 'a ''it''''s'' b') = 'a  b');
  St.Reset;
  Check('brace comment skipped', CodeChars(St, 'x { c } y') = 'x  y');
  St.Reset;
  Check('paren-star comment skipped', CodeChars(St, 'x (* c *) y') = 'x  y');
  St.Reset;
  Check('line comment stops the scan', CodeChars(St, 'a; // b c') = 'a; ');
  // Block comments carry across lines; strings do not.
  St.Reset;
  Check('open brace consumes rest of line', CodeChars(St, 'a { open') = 'a ');
  Check('...and next line up to the closer', CodeChars(St, 'in } b') = ' b');
  St.Reset;
  Check('open (* consumes rest of line', CodeChars(St, 'a (* open') = 'a ');
  Check('...and next line up to *)', CodeChars(St, 'in *) c') = ' c');
  St.Reset;
  CodeChars(St, 'S := ''unterminated');
  Check('unterminated string does not leak into next line',
    CodeChars(St, 'plain') = 'plain');
end;

procedure TestLineScanDepth;
var
  St: TLineScanState;
begin
  St.Reset;
  CodeChars(St, 'f(a[1');
  Check('depth counts ( and [', St.Depth = 2);
  CodeChars(St, '])');
  Check('depth counts ) and ]', St.Depth = 0);
  CodeChars(St, ')');
  Check('unclamped depth goes negative', St.Depth = -1);
  St.Reset;
  St.ClampDepth:= True;
  CodeChars(St, ')');
  Check('clamped depth stays at zero', St.Depth = 0);
  St.Reset;
  CodeChars(St, 'a (1)');
  Check('paren-star opener is not counted as depth', St.Depth = 0);
end;

// Code characters of ALine that sit at TLineScanState.AtTopLevel.
function TopLevelChars(var AState: TLineScanState; const ALine: string): string;
var
  i: Integer;
begin
  Result:= '';
  AState.BeginLine;
  i:= 1;
  while AState.SkipNonCode(ALine, i) = seCode do
  begin
    if AState.AtTopLevel then
      Result:= Result + ALine[i];
    AState.StepCode(ALine, i);
  end;
end;

procedure TestLineScanAngle;
var
  St: TLineScanState;
begin
  St.Reset;
  St.TrackAngle:= True;
  Check('colon/semicolon inside <...> are not top level',
    TopLevelChars(St, 'TBar<T1: TComponent; T2: class> = class(TObject);') = 'TBar< = class(;');
  Check('closer lowers AngleDepth', St.AngleDepth = 0);
  St.Reset;
  St.TrackAngle:= True;
  CodeChars(St, 'if A<B then');
  Check('less-than without closer is not an angle', St.AngleDepth = 0);
  CodeChars(St, 'if A<B and C>D then');
  Check('balanced compare span is closed again', St.AngleDepth = 0);
  St.Reset;
  St.TrackAngle:= True;
  CodeChars(St, 'x:= A<>B; y:= A<=B; z:= (A<B) and (C>D);');
  Check('<> <= and paren-broken spans are not angles', St.AngleDepth = 0);
  St.Reset;
  CodeChars(St, 'TList<Integer>');
  Check('default (TrackAngle off) never tracks', St.AngleDepth = 0);
end;

procedure TestBlockCommentLock;
var
  L   : TStringList;
  Lock: TArray<Boolean>;
begin
  L:= TStringList.Create;
  try
    L.Add('a := 1;');
    L.Add('b := { open');
    L.Add('  interior');
    L.Add('close } c;');
    L.Add('d := 2; // tail');
    Lock:= ComputeBlockCommentLock(L);
    Check('plain line not locked'          , not Lock[0]);
    Check('opening line locked'            ,     Lock[1]);
    Check('interior line locked'           ,     Lock[2]);
    Check('closing line locked'            ,     Lock[3]);
    Check('line after the comment unlocked', not Lock[4]);
  finally
    L.Free;
  end;
end;

procedure TestLineStartDepths;
var
  L: TStringList;
  D: TArray<Integer>;
begin
  L:= TStringList.Create;
  try
    L.Add('call(');
    L.Add('  x, ''('',   // paren in string+comment must not count');
    L.Add(');');
    L.Add('done;');
    D:= ComputeLineStartDepths(L);
    Check('depth 0 before the opener'    , D[0] = 0);
    Check('depth 1 inside the group'     , D[1] = 1);
    Check('depth 1 at the closing line'  , D[2] = 1);
    Check('depth 0 after the group'      , D[3] = 0);
  finally
    L.Free;
  end;
end;

// --- WP1: strict code-token stream ----------------------------------------

function CodeOk(const AOrig, AFmt: string; AMode: TGuardCodeMode): Boolean;
var
  Reason: string;
begin
  Result:= FormatPreservesContent(AOrig, AFmt, False, False, AMode, Reason);
end;

procedure TestCodeTokenStream;
const
  Base = 'begin' + CRLF + '  A:= 1;' + CRLF + '  B:= 2;' + CRLF + 'end;' + CRLF;
begin
  Check('STRICT identical passes'     , CodeOk(Base, Base, gcStrict));
  Check('STRICT whitespace/case passes', CodeOk(Base, 'BEGIN A := 1;  b:=2; END;', gcStrict));
  Check('STRICT hex literal case passes', CodeOk('X:= $ab;', 'X:= $AB;', gcStrict));
  Check('STRICT reordered statements rejected',
    not CodeOk(Base, 'begin' + CRLF + '  B:= 2;' + CRLF + '  A:= 1;' + CRLF + 'end;' + CRLF, gcStrict));
  Check('STRICT lost token rejected',
    not CodeOk(Base, 'begin' + CRLF + '  A:= 1;' + CRLF + 'end;' + CRLF, gcStrict));
  Check('STRICT duplicated statement rejected',
    not CodeOk(Base, 'begin' + CRLF + '  A:= 1;' + CRLF + '  A:= 1;' + CRLF + '  B:= 2;' + CRLF + 'end;' + CRLF, gcStrict));
  Check('STRICT changed operator rejected', not CodeOk('X:= A + B;', 'X:= A - B;', gcStrict));
  Check('STRICT comment/string/directive changes do not count here',
    CodeOk('X:= ''a''; // c', 'X:= ''a''; // c', gcStrict));
  Check('STRICT asm body is ignored by the code stream',
    CodeOk('asm' + CRLF + '  mov eax, 1' + CRLF + 'end;', 'asm' + CRLF + '  mov  eax,  1' + CRLF + 'end;', gcStrict));
  Check('gcNone does not compare code', CodeOk(Base, 'begin end;', gcNone));
end;

procedure TestCodeTokenSplitAndD10;
begin
  Check('SPLIT multi-var split ok',
    CodeOk('var A, B: Integer;', 'var A: Integer; B: Integer;', gcSplit));
  Check('SPLIT split with new identifier rejected',
    not CodeOk('var A, B: Integer;', 'var A: Integer; C: Integer;', gcSplit));
  Check('SPLIT dropped token rejected',
    not CodeOk('var A, B: Integer;', 'var A: Integer;', gcSplit));
  Check('SPLIT reordered rejected',
    not CodeOk('var A, B: Integer;', 'var B: Integer; A: Integer;', gcSplit));
  Check('SPLIT case-arm split ok',
    CodeOk('case X of 1, 2: Foo; end;', 'case X of 1: Foo; 2: Foo; end;', gcSplit));
  Check('D10 inline var hoist ok',
    CodeOk('procedure P; begin var X: Integer:= 1; Use(X); end;',
           'procedure P; var X: Integer; begin X:= 1; Use(X); end;', gcD10));
  Check('D10 untyped for-var hoist with inferred type ok',
    CodeOk('procedure P; begin for var I:= 0 to 3 do Use(I); end;',
           'procedure P; var I: Integer; begin for I:= 0 to 3 do Use(I); end;', gcD10));
  // The D10 pipeline checks in two stages (YADF.Layout.FormatSource): STRICT
  // from the post-hoist token text to the pre-split text, then gcD10 from the
  // source to the final text. The bag-of-tokens gcD10 alone cannot see a
  // reorder; the strict stage is what rejects it.
  Check('D10 bag check alone is blind to a reorder (why the strict stage exists)',
    CodeOk('procedure P; begin X:= A - B; end;', 'procedure P; begin X:= B - A; end;', gcD10));
  Check('D10 strict stage: reordered A - B rejected after the hoist',
    not CodeOk('procedure P; var X: Integer; begin X:= 1; Y:= A - B; end;',
               'procedure P;' + CRLF + 'var X: Integer;' + CRLF + 'begin' + CRLF + '  X:= 1;' + CRLF + '  Y:= B - A;' + CRLF + 'end;', gcStrict));
  Check('D10 strict stage: legit hoist (post-hoist text vs reflowed output) passes',
    CodeOk('procedure P; var X: Integer; begin X:= 1; Y:= A - B; end;',
           'procedure P;' + CRLF + 'var X: Integer;' + CRLF + 'begin' + CRLF + '  X:= 1;' + CRLF + '  Y:= A - B;' + CRLF + 'end;', gcStrict));
  Check('D10 final stage: source vs hoisted+reflowed output passes',
    CodeOk('procedure P; begin var X: Integer:= 1; Y:= A - B; end;',
           'procedure P;' + CRLF + 'var X: Integer;' + CRLF + 'begin' + CRLF + '  X:= 1;' + CRLF + '  Y:= A - B;' + CRLF + 'end;', gcD10));
  Check('D10 lost statement rejected',
    not CodeOk('procedure P; begin var X: Integer:= 1; Use(X); end;',
               'procedure P; var X: Integer; begin X:= 1; end;', gcD10));
end;

procedure TestDirectiveWhitespaceKey;
begin
  Check('WP2 {$I a b.inc} vs {$I ab.inc} rejected',
    not FormatPreservesContent('{$I a b.inc}' + CRLF, '{$I ab.inc}' + CRLF));
  Check('WP2 whitespace runs inside directive still equal',
    FormatPreservesContent('{$IFDEF   A  }' + CRLF, '{$IFDEF A}' + CRLF));
  Check('WP2 leading whitespace after {$ ok',
    FormatPreservesContent('{$ifdef A}' + CRLF, '{$IFDEF A}' + CRLF));
  Check('WP2 argument change rejected',
    not FormatPreservesContent('{$IFDEF A B}' + CRLF, '{$IFDEF AB}' + CRLF));
end;

// --- integration: FormatSource must still format normal code --------------

procedure TestFormatSourceStillFormats;
const
  Src =
    'unit U;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'procedure P;' + CRLF +
    'var a,b:Integer;' + CRLF +
    'begin' + CRLF +
    'a:=1; // note' + CRLF +
    'b:=2;' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
var
  Opts: TYadfOptions;
  Res : string;
begin
  Opts:= DefaultOptions;
  Res := FormatSource(Src, Opts);
  Check('FormatSource still changes unformatted code (guard not tripping)',
    Res <> Src);
  Check('formatted output itself passes the guard',
    FormatPreservesContent(Src, Res));
end;

// WP11: user text that looks exactly like a layout sentinel must neither be
// replaced by a shielded multi-line atom on unshield nor make the guard decline.
// FormatSource picks a shield prefix that is absent from the source.
procedure TestShieldPrefixAvoidsUserText;
const
  Src =
    'unit U;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'procedure P;' + CRLF +
    'var a,b:Integer;' + CRLF +
    'begin' + CRLF +
    '{ real line one' + CRLF +
    'real line two }' + CRLF +
    'a:=1; {__YADF_MLC_0__}' + CRLF +
    'b:=2; // __YADF_ML_0__ and //__YADF_ASM_0__' + CRLF +
    'end;' + CRLF +
    'end.' + CRLF;
var
  Opts  : TYadfOptions;
  Res   : string;
  Reason: string;
begin
  Opts:= DefaultOptions;
  Res := FormatSource(Src, Opts, Reason);
  Check('sentinel-lookalike source is formatted, not declined', (Reason = '') and (Res <> Src));
  Check('lookalike brace comment kept verbatim', Pos('{__YADF_MLC_0__}', Res) > 0);
  Check('lookalike line comment kept verbatim', Pos('// __YADF_ML_0__ and //__YADF_ASM_0__', Res) > 0);
  Check('real multi-line comment kept verbatim', Pos('{ real line one' + CRLF + 'real line two }', Res) > 0);
  Check('formatted lookalike output passes the guard', FormatPreservesContent(Src, Res));
  Check('guard still flags a leaked prefixed sentinel',
    not FormatPreservesContent('X := 1;', 'X := 1; //__YADF1_ASM_0__'));
end;

// --- task 8: strict code-token stream ---------------------------------------

const
  // The casing licence at default options (LowercaseKeywords, FirstOccCasing,
  // UpperHexNumbers all on).
  DEF_CASING: TGuardCasing = [gkKeywordsLower, gkFirstOccurrence, gkUpperHex];

function GuardOk(const AOrig, AFmt: string; AMode: TGuardCodeMode; ACasing: TGuardCasing; ALabels: Boolean = False): Boolean;
var
  Reason: string;
begin
  Result:= FormatPreservesContent(AOrig, AFmt, False, ALabels, AMode, ACasing, Reason);
end;

// Each corruption class of the 2026-10-14 review, injected straight into the
// guard as the formatter's output, in the modes FormatSource uses at defaults
// (gcSplit: SplitMultiVarDecls is on) and in gcStrict.
procedure TestReviewCorruptionClasses;
const
  Unit0 = 'unit U;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF + 'procedure P;' + CRLF + 'begin' + CRLF + '  A:= 1;' + CRLF + '  B:= 2;' + CRLF + 'end;' + CRLF + 'end.' + CRLF;
  Exp0  = 'Tol:= A - B;' + CRLF + 'Eps:= 1E-9;' + CRLF;
  Dir0  = 'var' + CRLF + '  I, J: Integer; {$IFDEF X}' + CRLF + '  K: Integer;' + CRLF + '{$ENDIF}' + CRLF;
  Ext0  = 'procedure A; begin gettickcount; end;' + CRLF + 'function GetTickCount: Cardinal; stdcall; external ''kernel32.dll'';' + CRLF;
  Enum0 = 'var red: Integer;' + CRLF + 'type TColor = (Red, Green);' + CRLF;
  NUL_CUT = 38; // the review's NUL repro kept 38 of 83 bytes
  D10S  = 'procedure P;' + CRLF + 'begin' + CRLF + '{$IFDEF X}' + CRLF + '  var Y: Integer:= 1;' + CRLF + '  Use(Y);' + CRLF + '{$ENDIF}' + CRLF + 'end;' + CRLF;
var
  M: TGuardCodeMode;
begin
  for M in [gcStrict, gcSplit] do
  begin
    Check(Format('#5 truncated output (NUL) rejected [%d]', [Ord(M)]),
      not GuardOk(Unit0, Copy(Unit0, 1, NUL_CUT), M, DEF_CASING));
    Check(Format('#6 signed exponent split by alignment rejected [%d]', [Ord(M)]),
      not GuardOk(Exp0, 'Tol:= A - B;' + CRLF + 'Eps:= 1E   -9;' + CRLF, M, DEF_CASING));
    Check(Format('#8 external import name re-cased rejected [%d]', [Ord(M)]),
      not GuardOk(Ext0, 'procedure A; begin gettickcount; end;' + CRLF + 'function gettickcount: Cardinal; stdcall; external ''kernel32.dll'';' + CRLF, M, DEF_CASING));
    Check(Format('#9 enum member re-cased rejected [%d]', [Ord(M)]),
      not GuardOk(Enum0, 'var red: Integer;' + CRLF + 'type TColor = (red, Green);' + CRLF, M, DEF_CASING));
    Check(Format('duplicated statement rejected [%d]', [Ord(M)]),
      not GuardOk(Unit0, StringReplace(Unit0, '  A:= 1;', '  A:= 1;' + CRLF + '  A:= 1;', []), M, DEF_CASING));
    Check(Format('code moved across a directive rejected [%d]', [Ord(M)]),
      not GuardOk('{$IFDEF X} A; {$ENDIF} B;', '{$IFDEF X} A; B; {$ENDIF}', M, DEF_CASING));
    Check(Format('string literal moved past code rejected [%d]', [Ord(M)]),
      not GuardOk('X:= ''a''; Y:= Z;', 'X:= Y; ''a'':= Z;', M, DEF_CASING));
  end;
  Check('#7 split moving a name into an {$IFDEF} rejected (gcSplit)',
    not GuardOk(Dir0, 'var' + CRLF + '  I: Integer; {$IFDEF X}' + CRLF + '  J: Integer;' + CRLF + '  K: Integer;' + CRLF + '{$ENDIF}' + CRLF, gcSplit, DEF_CASING));
  Check('#7 legitimate split before the {$IFDEF} passes (gcSplit)',
    GuardOk(Dir0, 'var' + CRLF + '  I: Integer;' + CRLF + '  J: Integer; {$IFDEF X}' + CRLF + '  K: Integer;' + CRLF + '{$ENDIF}' + CRLF, gcSplit, DEF_CASING));
  Check('#10 --d10 hoist out of an {$IFDEF} rejected (gcD10)',
    not GuardOk(D10S, 'procedure P;' + CRLF + 'var' + CRLF + '  Y: Integer;' + CRLF + 'begin' + CRLF + '{$IFDEF X}' + CRLF + '  Y:= 1;' + CRLF + '  Use(Y);' + CRLF + '{$ENDIF}' + CRLF + 'end;' + CRLF,
      gcD10, DEF_CASING));
  Check('#10 --d10 hoist of a var AFTER an {$IFDEF} block passes (gcD10)',
    GuardOk('procedure P;' + CRLF + 'begin' + CRLF + '{$IFDEF X}' + CRLF + '  Foo;' + CRLF + '{$ENDIF}' + CRLF + '  var Y: Integer:= 1;' + CRLF + '  Use(Y);' + CRLF + 'end;' + CRLF,
      'procedure P;' + CRLF + 'var' + CRLF + '  Y: Integer;' + CRLF + 'begin' + CRLF + '{$IFDEF X}' + CRLF + '  Foo;' + CRLF + '{$ENDIF}' + CRLF + '  Y:= 1;' + CRLF + '  Use(Y);' + CRLF + 'end;' + CRLF,
      gcD10, DEF_CASING));
  Check('#10 a lost statement in a branch rejected (gcD10)',
    not GuardOk(D10S, StringReplace(D10S, '  Use(Y);' + CRLF, '', []), gcD10, DEF_CASING));
end;

procedure TestCasingLicence;
begin
  Check('keyword lowercased passes with gkKeywordsLower', GuardOk('BEGIN X:= 1; END;', 'begin X:= 1; end;', gcStrict, [gkKeywordsLower]));
  Check('keyword lowercased rejected without the licence', not GuardOk('BEGIN X:= 1; END;', 'begin X:= 1; end;', gcStrict, []));
  Check('keyword UPPERcased rejected even with gkKeywordsLower', not GuardOk('begin X:= 1; end;', 'BEGIN X:= 1; END;', gcStrict, [gkKeywordsLower]));
  Check('first-occurrence cascade passes', GuardOk('Foo:= 1; FOO:= 2;', 'Foo:= 1; Foo:= 2;', gcStrict, DEF_CASING));
  Check('identifier re-cased to a NON-first spelling rejected', not GuardOk('Foo:= 1; FOO:= 2;', 'FOO:= 1; FOO:= 2;', gcStrict, DEF_CASING));
  Check('identifier re-cased without gkFirstOccurrence rejected', not GuardOk('Foo:= 1; FOO:= 2;', 'Foo:= 1; Foo:= 2;', gcStrict, [gkKeywordsLower]));
  Check('hex case change passes with gkUpperHex', GuardOk('X:= $ab;', 'X:= $AB;', gcStrict, [gkUpperHex]));
  Check('hex case change rejected without gkUpperHex', not GuardOk('X:= $ab;', 'X:= $AB;', gcStrict, []));
  Check('gkAnyCase keeps the historic lowercase-only comparison', GuardOk('Foo:= 1;', 'FOO:= 1;', gcStrict, [gkAnyCase]));
  Check('gcSplit checks spelling of the expanded copies too',
    not GuardOk('var A, B: Integer;', 'var A: Integer; B: integer;', gcSplit, DEF_CASING));
  Check('gcSplit expanded copies with the original spelling pass',
    GuardOk('var A, B: Integer;', 'var A: Integer; B: Integer;', gcSplit, DEF_CASING));
  Check('gcSplit parameter modifier repeated per name passes',
    GuardOk('procedure P(const A, B: Integer; var C, D: string);', 'procedure P(const A: Integer; const B: Integer; var C: string; var D: string);', gcSplit, DEF_CASING));
  Check('gcSplit untyped parameter list re-spelled per name passes',
    GuardOk('procedure P(var A, B; const C, D);', 'procedure P(var A; var B; const C; const D);', gcSplit, DEF_CASING));
  Check('gcSplit modifier dropped from the second name rejected',
    not GuardOk('procedure P(const A, B: Integer);', 'procedure P(const A: Integer; B: Integer);', gcSplit, DEF_CASING));
  Check('gcD10 enum member re-cased rejected',
    not GuardOk('var red: Integer; type TColor = (Red, Green);', 'var red: Integer; type TColor = (red, Green);', gcD10, DEF_CASING));
end;

// Task 8 (b): FindBlockLabel's 300-token budget counted whitespace, so the same
// routine got the `// procedure` marker verdict on the tight side and not on the
// spaced side (the --d10 snapshot renders a space between every token pair).
procedure TestLabelVerdictIgnoresSpacing;
const
  LIST_LEN = 120; // ~250 significant tokens: under FindBlockLabel's 300 only when spaces do not count
var
  Tight : string;
  Spaced: string;
  Items : string;
  i     : Integer;
begin
  Items:= '';
  for i:= 1 to LIST_LEN do
    Items:= Items + IntToStr(i) + ',';
  Items:= Items + '0';
  Tight := 'procedure P;' + CRLF + 'const' + CRLF + '  C: array[0..120] of Integer = (' + Items + ');' + CRLF + 'begin' + CRLF + '  X:= 1;' + CRLF + 'end; // procedure' + CRLF;
  Spaced:= StringReplace(Tight, ',', ' , ', [rfReplaceAll]);
  Check('label-removal verdict is the same for tight and spaced text',
    GuardOk(Spaced, Tight, gcStrict, DEF_CASING, True));
  Check('...and the other way round', GuardOk(Tight, Spaced, gcStrict, DEF_CASING, True));
end;

// Task 8 (b): the --d10 hoist drops a same-name same-type redeclaration
// (YADF.Layout.DowngradeInlineVars.CommitInline); that is not a lost token.
procedure TestD10SameTypeDedupe;
const
  Src = 'function P(N: Integer): Double; begin if N > 0 then for var I: Integer:= 1 to N do R:= 1 else for var I: Integer:= 1 to -N do R:= 2; end;';
  Fmt = 'function P(N: Integer): Double; var I: Integer; begin if N > 0 then for I:= 1 to N do R:= 1 else for I:= 1 to -N do R:= 2; end;';
begin
  Check('D10 same-type duplicate declaration dropped passes', GuardOk(Src, Fmt, gcD10, DEF_CASING));
  Check('D10 for-var retyped to an earlier same-name var rejected',
    not GuardOk('procedure P(N: Integer); begin begin var R: string:= ''a''; Use(R); end; for var R: Integer:= 1 to N do Use(R); end;',
      'procedure P(N: Integer); var R: string; begin begin R:= ''a''; Use(R); end; for R:= 1 to N do Use(R); end;', gcD10, DEF_CASING));
  Check('D10 the loop itself still may not be lost',
    not GuardOk(Src, 'function P(N: Integer): Double; var I: Integer; begin if N > 0 then for I:= 1 to N do R:= 1; end;', gcD10, DEF_CASING));
end;

// Task 8 (b) end to end: both ORM3 shapes now format under --d10.
procedure TestFormatSourceD10NoFalseDecline;
const
  PAIRS = 30; // ~180 significant tokens, ~360 with the snapshot's spaces
  SrcLabel =
    'unit U;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF +
    'procedure P;' + CRLF + 'const' + CRLF +
    '  C: array[0..3, 0..1] of string = (' + CRLF +
    '    (''A1'',''B1''), (''A2'',''B2''), (''A3'',''B3''), (''A4'',''B4''));' + CRLF +
    'begin' + CRLF + '  try' + CRLF + '    X:= 1;' + CRLF + '  finally' + CRLF + '    Y:= 2;' + CRLF + '  end; // try' + CRLF + 'end; // procedure' + CRLF + 'end.' + CRLF;
  SrcDup =
    'unit U;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF +
    'function P(N: Integer): Double;' + CRLF + 'begin' + CRLF + '  Result:= 1;' + CRLF +
    '  if N > 0 then for var I: Integer:= 1 to N do Result:= Result * 10.0' + CRLF +
    '  else if N < 0 then for var I: Integer:= 1 to -N do Result:= Result / 10.0;' + CRLF + 'end;' + CRLF + 'end.' + CRLF;
var
  Opts  : TYadfOptions;
  Res   : string;
  Reason: string;
  Pad   : string;
  i     : Integer;
begin
  Opts:= DefaultOptions;
  Opts.Delphi10Compat:= True;
  // Enough tight `('An','Bn')` pairs that the spaced snapshot crosses the budget.
  Pad:= '';
  for i:= 1 to PAIRS do
    Pad:= Pad + '(''A' + IntToStr(i) + ''',''B' + IntToStr(i) + '''), ';
  FormatSource(StringReplace(StringReplace(SrcLabel, '0..3,', '0..33,', []), '(''A1'',''B1''), ', Pad + '(''A1'',''B1''), ', []), Opts, Reason);
  Check('--d10: const array + labelled end not declined (' + Reason + ')', Reason = '');
  Res:= FormatSource(SrcDup, Opts, Reason);
  Check('--d10: duplicate same-type for-var not declined (' + Reason + ')', Reason = '');
  Check('--d10: duplicate for-var hoisted once', Res.Contains('for I:=') and not Res.Contains('for var'));
  // Found by task 8 (ORM3 Blueprint4.ViewModel.pas): the hoist retyped a for-var
  // that collides with an earlier DIFFERENT-type inline var (`R: TJVRow` /
  // `for var R: Integer`). It must leave the loop variable in place, flagged.
  Res:= FormatSource('unit U;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF + 'procedure P(N: Integer);' + CRLF + 'begin' + CRLF + '  begin' + CRLF +
    '    var R: string:= ''a'';' + CRLF + '    Use(R);' + CRLF + '  end;' + CRLF + '  for var R: Integer:= 1 to N do Use(R);' + CRLF + 'end;' + CRLF + 'end.' + CRLF, Opts, Reason);
  Check('--d10: colliding for-var is not declined (' + Reason + ')', Reason = '');
  Check('--d10: colliding for-var stays inline and is flagged', Res.Contains('var R: Integer:= 1 to N') and Res.Contains('TODO -oYADF'));
  Check('--d10: the string var is still hoisted', Res.Contains('R: string;'));
  Check('--d10: colliding for-var output is idempotent', FormatSource(Res, Opts, Reason) = Res);
end;

begin
  try
    TestAcceptsLegitimateFormatting;
    TestRejectsDroppedInclude;
    TestRejectsCommentDamage;
    TestRejectsStringDamage;
    TestRejectsReviewFindings;
    TestDuplicationToleranceAndReason;
    TestLabelRemovalTolerance;
    TestLineScanCore;
    TestLineScanDepth;
    TestLineScanAngle;
    TestBlockCommentLock;
    TestLineStartDepths;
    TestCodeTokenStream;
    TestCodeTokenSplitAndD10;
    TestDirectiveWhitespaceKey;
    TestFormatSourceStillFormats;
    TestShieldPrefixAvoidsUserText;
    TestReviewCorruptionClasses;
    TestCasingLicence;
    TestLabelVerdictIgnoresSpacing;
    TestD10SameTypeDedupe;
    TestFormatSourceD10NoFalseDecline;
    Writeln('');
    if GFailures = 0 then
      Writeln('ALL PASS')
    else
      Writeln(Format('%d FAILURE(S)', [GFailures]));
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Inc(GFailures);
    end;
  end;
  ExitCode := GFailures;
end.
