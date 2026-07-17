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

// The extended overload: BreakCaseLabels duplicates arm bodies (strings
// included), so with AAllowStringDuplication the original sequence need only
// survive IN ORDER; loss/alteration still fails, and AReason names the cause.
procedure TestDuplicationToleranceAndReason;
var
  Reason: string;
begin
  Check('strict mode rejects duplicated string',
    not FormatPreservesContent('1, 2: Log(''x'');', '1: Log(''x''); 2: Log(''x'');', False, Reason));
  Check('strict rejection carries a reason', Reason <> '');
  Check('duplication-tolerant mode accepts duplicated string',
    FormatPreservesContent('1, 2: Log(''x'');', '1: Log(''x''); 2: Log(''x'');', True, Reason));
  Check('acceptance carries empty reason', Reason = '');
  Check('duplication-tolerant mode still rejects a LOST string',
    not FormatPreservesContent('S := ''a'' + ''b'';', 'S := ''a'';', True, Reason));
  Check('lost-string reason names the stream', Pos('string', Reason) > 0);
  Check('duplication-tolerant mode still rejects an ALTERED string',
    not FormatPreservesContent('S := ''a  b'';', 'S := ''a b'';', True, Reason));
  Check('directives stay strict under duplication tolerance',
    not FormatPreservesContent('{$IFDEF X} A; {$ENDIF}', '{$IFDEF X} A; {$ENDIF} {$IFDEF X} B; {$ENDIF}', True, Reason));
  Check('dropped-comment reason names the stream',
    (not FormatPreservesContent('X; { note }', 'X;', False, Reason)) and (Pos('comment', Reason) > 0));
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

begin
  try
    TestAcceptsLegitimateFormatting;
    TestRejectsDroppedInclude;
    TestRejectsCommentDamage;
    TestRejectsStringDamage;
    TestDuplicationToleranceAndReason;
    TestLineScanCore;
    TestLineScanDepth;
    TestBlockCommentLock;
    TestLineStartDepths;
    TestFormatSourceStillFormats;
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
