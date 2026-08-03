{
  YADF -- Yet Another Delphi Formatter

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Uses lexer/parser code from DelphiAST:
  Copyright (c) 2014-2020 Roman Yankovsky (roman@yankovsky.me) et al
  https://github.com/RomanYankovsky/DelphiAST
}

unit YADF.Debug;

interface

uses
  YADF.Tokens
  , YADF.Groups
  ;

/// <summary></summary>
/// <param name="ATokens"></param>
/// <param name="ARoot"></param>
/// <returns>Observed: Lines.Text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YadfMain.DebugTree (YadfMain.pas)
/// Calls: YADF.Debug.WalkGroup
/// Returns: Lines.Text
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function RenderGroupTree(const ATokens: TTokenList; ARoot: TGroup): string;

implementation

uses
  System.SysUtils
  , System.Classes
  ;

function KindName(K: TGroupKind): string;
begin
  case K of
    gkRoot    : Result:= 'ROOT';
    gkParens  : Result:= 'PARENS';
    gkBrackets: Result:= 'BRACKETS';
    gkBlock   : Result:= 'BLOCK';
    gkUses    : Result:= 'USES';
    else
      Result:= 'UNKNOWN';
  end;
end; // function

function PreviewSpan(const ATokens: TTokenList; AStart, AEnd: Integer): string;
var
  i  : Integer       ;
  Sb : TStringBuilder;
  Lim: Integer       ;
begin
  Lim:= AEnd;
  if Lim - AStart > 6 then
    Lim:= AStart + 6;
  Sb:= TStringBuilder.Create;
  try
    for i:= AStart to Lim do if i >= 0 then
      Sb.Append(ATokens[i].Text + ' ');
    if Lim < AEnd then
      Sb.Append('...');
    Result:= StringReplace(StringReplace(Sb.ToString.Trim, #13, '', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  finally
    Sb.Free;
  end;
end; // function

procedure WalkGroup(const ATokens: TTokenList; G: TGroup; ADepth: Integer; ALines: TStringList);
var
  Indent  : string ;
  Line    : string ;
  StartTok: Integer;
  EndTok  : Integer;
  Child   : TGroup ;
begin
  Indent:= StringOfChar(' ', ADepth * 2);
  StartTok:= G.OpenIdx;
  EndTok  := G.CloseIdx;
  if G.Kind = gkRoot then
    Line:= Indent + Format('%s [tokens 0..%d]', [KindName(G.Kind), EndTok])
  else
    Line:= Indent + Format('%s [%d..%d]  %s', [ KindName(G.Kind), StartTok, EndTok, PreviewSpan(ATokens, StartTok, EndTok)]);
  if G.ForceClosed then
    Line:= Line + '  <FORCE-CLOSED at EOF>';
  ALines.Add(Line);
  for Child in G.Children do
    WalkGroup(ATokens, Child, ADepth + 1, ALines);
end; // procedure

function RenderGroupTree(const ATokens: TTokenList; ARoot: TGroup): string;
var
  Lines: TStringList;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= #13#10;
    WalkGroup(ATokens, ARoot, 0, Lines);
    Result:= Lines.Text;
  finally
    Lines.Free;
  end;
end;

end.

