program FormatBridgeTest;

{ Console tests for YADF.FormatBridge -- the IDE-independent logic behind the
  Delphi 13.2 IOTACodeFormatter adapter (YADFOT.CodeFormatter): UTF-8 round
  trip, decline -> original text, selection -> whole-line mapping, caret
  remap. No ToolsAPI, no IDE. Style mirrors GuardTest.dpr. }

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
  YADF.Guard in '..\YADF.Guard.pas',
  YADF.FormatBridge in '..\YADF.FormatBridge.pas';

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

function U(const S: string): UTF8String;
begin
  Result := TextToUtf8(S);
end;

procedure TestExtensions;
begin
  Check('ext .pas', IsPascalSourceFile('C:\a\Unit1.pas'));
  Check('ext .DPR (case-insensitive)', IsPascalSourceFile('P.DPR'));
  Check('ext .dpk', IsPascalSourceFile('x.dpk'));
  Check('ext .inc', IsPascalSourceFile('x.inc'));
  Check('ext .dfm refused', not IsPascalSourceFile('x.dfm'));
  Check('ext none refused', not IsPascalSourceFile('Makefile'));
  Check('empty name refused', not IsPascalSourceFile(''));
end;

procedure TestUtf8RoundTrip;
var
  S, B: string;
  R   : UTF8String;
begin
  S := 'x:= ''' + #$0416#$0436 + ' ' + #$D83D#$DE00 + ' caf' + #$00E9 + ''';';
  R := TextToUtf8(S);
  Check('utf8: non-ASCII is multi-byte UTF-8', Length(R) > Length(S));
  Check('utf8: no BOM added', not ((Length(R) >= 3) and (R[1] = #$EF) and (R[2] = #$BB)));
  B := Utf8ToText(R);
  Check('utf8: text -> bytes -> text identity (incl. surrogate pair)', B = S);
  Check('utf8: empty', (Length(TextToUtf8('')) = 0) and (Utf8ToText('') = ''));
end;

function FakeDecline(const ASrc: string; const AOpts: TYadfOptions; out ADecl: string): string;
begin
  ADecl := 'guard says no';
  Result := 'GARBAGE ' + ASrc;
end;

function FakeRaise(const ASrc: string; const AOpts: TYadfOptions; out ADecl: string): string;
begin
  ADecl := '';
  raise EInvalidOperation.Create('boom');
end;

function FakeUpper(const ASrc: string; const AOpts: TYadfOptions; out ADecl: string): string;
begin
  ADecl := '';
  Result := AnsiUpperCase(ASrc);
end;

procedure TestFormatContent;
var
  Src, Out1: UTF8String;
  Decl     : string;
  Ok       : Boolean;
  Opts     : TYadfOptions;
  Txt      : string;
begin
  Opts := DefaultOptions;
  Src := U('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'x:=1;'#10'end;'#10'end.'#10);
  Ok := FormatUtf8Content(Src, Opts, Out1, Decl);
  Check('format: succeeds on a plain unit (' + Decl + ')', Ok and (Decl = ''));
  Txt := Utf8ToText(Out1);
  Check('format: engine applied (assignment spacing)', Pos('x:= 1;', Txt) > 0);
  Check('format: LF input comes back CRLF-only',
    (Pos(#13#10, Txt) > 0) and (Pos(#10, StringReplace(Txt, #13#10, '', [rfReplaceAll])) = 0));
  Check('format: no BOM inserted', not ((Length(Out1) >= 3) and (Out1[1] = #$EF)));

  Out1 := 'stale';
  Ok := FormatUtf8Content(Src, Opts, Out1, Decl, FakeDecline);
  Check('decline: returns False', not Ok);
  Check('decline: output is the ORIGINAL bytes, never the garbage', Out1 = Src);
  Check('decline: reason surfaced', Decl = 'guard says no');

  Out1 := 'stale';
  Ok := FormatUtf8Content(Src, Opts, Out1, Decl, FakeRaise);
  Check('exception: returns False', not Ok);
  Check('exception: output is the ORIGINAL bytes', Out1 = Src);
  Check('exception: reason carries class and message', (Pos('EInvalidOperation', Decl) > 0) and (Pos('boom', Decl) > 0));

  Ok := FormatUtf8Content(U('abc'), Opts, Out1, Decl, FakeUpper);
  Check('seam: custom formatter result is UTF-8 encoded back', Ok and (Out1 = U('ABC')));
  Ok := FormatUtf8Content(U(#$0436), Opts, Out1, Decl, FakeUpper);
  Check('seam: non-ASCII survives the engine hop', Ok and (Utf8ToText(Out1) = #$0416));
  Ok := FormatUtf8Content('', Opts, Out1, Decl, FakeUpper);
  Check('empty content formats to empty', Ok and (Length(Out1) = 0));
end;

procedure TestLineMapping;
var
  C   : UTF8String;
  S, E: Integer;
begin
  // offsets: aaa 0-2, CRLF 3-4, bbb 5-7, CRLF 8-9, ccc 10-12
  C := U('aaa'#13#10'bbb'#13#10'ccc');
  Check('lines: caret in middle line', ExpandToWholeLines(C, 6, 0, S, E) and (S = 5) and (E = 10));
  Check('lines: selection inside one line', ExpandToWholeLines(C, 6, 1, S, E) and (S = 5) and (E = 10));
  Check('lines: selection spanning two lines', ExpandToWholeLines(C, 1, 6, S, E) and (S = 0) and (E = 10));
  Check('lines: selection ending exactly at next line start excludes it', ExpandToWholeLines(C, 0, 5, S, E) and (S = 0) and (E = 5));
  Check('lines: last line has no break -> ends at content length', ExpandToWholeLines(C, 11, 1, S, E) and (S = 10) and (E = 13));
  Check('lines: LF-only content', ExpandToWholeLines(U('a'#10'b'#10), 2, 0, S, E) and (S = 2) and (E = 4));
  Check('lines: negative offset invalid', not ExpandToWholeLines(C, -1, 0, S, E));
  Check('lines: past end invalid', not ExpandToWholeLines(C, 14, 0, S, E));
  Check('lines: range beyond end invalid', not ExpandToWholeLines(C, 10, 9, S, E));
  Check('lines: negative length invalid', not ExpandToWholeLines(C, 0, -1, S, E));
  Check('whole: select-all covers content', SelectionCoversWholeContent(C, 0, Length(C)));
  Check('whole: line-to-line selection covering every line', SelectionCoversWholeContent(C, 2, 11));
  Check('whole: partial does not', not SelectionCoversWholeContent(C, 5, 3));
  Check('whole: empty content never', not SelectionCoversWholeContent('', 0, 0));
end;

procedure TestCursorRemap;
var
  A, B: UTF8String;
begin
  A := U('aaaa'#13#10'bbbbbb'#13#10'cc');
  B := U('aa'#13#10'bbbbbbbbbb'#13#10'cc');
  Check('remap: same line, same column', RemapCursorOffset(A, B, 9) = 7);
  Check('remap: column clamps to shorter line',
    RemapCursorOffset(U('abcdef'#13#10'zzzzzz'), U('ab'#13#10'zz'), 5) = 2);
  Check('remap: line clamps to last line of shorter result',
    RemapCursorOffset(U('a'#13#10'b'#13#10'c'), U('a'), 6) = 0);
  Check('remap: negative offset -> 0', RemapCursorOffset(A, B, -4) = 0);
  Check('remap: offset past end -> end of last line', RemapCursorOffset(A, B, 999) = Length(B));
  Check('remap: never lands inside a multi-byte character',
    RemapCursorOffset(U('abcd'), U(#$0436#$0436), 3) = 2);
  Check('remap: empty result -> 0', RemapCursorOffset(A, '', 5) = 0);
end;

begin
  TestExtensions;
  TestUtf8RoundTrip;
  TestFormatContent;
  TestLineMapping;
  TestCursorRemap;
  if GFailures > 0 then
    Writeln(GFailures, ' FAILED');
  ExitCode := GFailures;
end.
