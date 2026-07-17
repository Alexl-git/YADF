program GuardTest;

{ Console tests for YADF.Guard -- the post-format content-preservation
  safety net. Style mirrors OptionsTest.dpr: plain Check() procedures,
  ExitCode = failure count. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  YADF.Tokens in '..\YADF.Tokens.pas',
  YADF.Options in '..\YADF.Options.pas',
  YADF.Groups in '..\YADF.Groups.pas',
  YADF.Debug in '..\YADF.Debug.pas',
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
