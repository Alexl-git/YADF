{
  YADF -- Yet Another Delphi Formatter

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Post-format safety net. FormatSource's line passes re-derive lexical
  facts from raw strings, and historically every shipped corruption bug
  (dropped $I include directives, comment merge/loss, multiline-string
  interior damage) was a failure of exactly that re-derivation. This unit re-lexes
  the formatter's OUTPUT and verifies that all user CONTENT survived:

    * string literals  -- byte-exact, same order, same count;
    * comments         -- text-exact (modulo trailing spaces / newline
                          style), same order; the formatter may ADD
                          comments (block labels, --d10 TODO flags) but
                          never drop or alter one;
    * compiler directives -- same order and count, compared with case and
                          whitespace normalized (UpperDirectives and the
                          ifdef-spacing pass legitimately touch those).

  Code tokens are deliberately NOT compared: passes such as
  SplitMultiVarDeclarations and DowngradeInlineVars legitimately duplicate
  or rewrite them. The guard therefore catches "user content destroyed",
  not "semantics changed" -- the former is the class that has actually
  shipped.
}

unit YADF.Guard;

interface

/// <summary>Verifies that AFormatted preserves all user content of AOriginal:
/// every string literal byte-exact and in order, every comment present
/// unaltered and in order (formatter-added comments are allowed), and every
/// compiler directive present in order (case/whitespace-insensitive).</summary>
/// <param name="AOriginal">Source text before formatting.</param>
/// <param name="AFormatted">Candidate formatter output to validate.</param>
/// <returns>True when the content is fully preserved; False when anything was
/// dropped or altered -- the caller should then discard AFormatted and keep
/// AOriginal (decline to format rather than corrupt).</returns>
/// <remarks>Pure and thread-safe; lexes both inputs once. If lexing the inputs
/// raises, the guard fails CLOSED (returns False).</remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string): Boolean;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , SimpleParser.Lexer.Types
  , YADF.Tokens
  ;

// Newline-style differences (LF-only input emitted as CRLF) are not content
// damage; fold every newline flavor to #10 before comparing.
function NormalizeNewlines(const S: string): string;
begin
  Result:= StringReplace(S     , #13#10, #10, [rfReplaceAll]);
  Result:= StringReplace(Result, #13   , #10, [rfReplaceAll]);
end;

// Directive comparison key: lowercase with ALL whitespace removed.
// UpperDirectives rewrites `{$ifdef}` as `{$IFDEF}` and the ifdef-spacing
// normalization rewrites `{$IFDEF  x }` as `{$IFDEF x}`; neither is damage.
// Stripping whitespace entirely still catches the bugs that matter here --
// a dropped directive or a changed argument (e.g. the file in `{$I file}`).
function DirectiveKey(const S: string): string;
var
  Sb: TStringBuilder;
  C : Char;
begin
  Sb:= TStringBuilder.Create;
  try
    for C in S do
      if C > ' ' then Sb.Append(C);
    Result:= LowerCase(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

const
  DirectiveKinds = [ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect,
    ptElseDirect, ptElseIfDirect, ptEndIfDirect, ptIfEndDirect, ptDefineDirect,
    ptUndefDirect, ptIncludeDirect, ptResourceDirect, ptCompDirect,
    ptScopedEnumsDirect];
  CommentKinds   = [ptAnsiComment, ptBorComment, ptSlashesComment];
  StringKinds    = [ptStringConst, ptStringDQConst];

// Extracts the three ordered content streams from ASource in one lex.
procedure ExtractContent(const ASource: string;
  const AStrings, AComments, ADirectives: TList<string>);
var
  Tokens: TTokenList;
  T     : TToken;
begin
  Tokens:= LoadTokensFromString(ASource);
  try
    for T in Tokens do
    begin
      if T.Kind in StringKinds then
        AStrings.Add(NormalizeNewlines(T.Text))
      else if T.Kind = ptAsciiChar then
        // `#$AB` vs `#$ab` is a legitimate hex-case normalization.
        AStrings.Add(LowerCase(T.Text))
      else if T.Kind in CommentKinds then
        // TrimRight: the trailing-whitespace pass may trim spaces at the end
        // of a `// comment` line; that is not content damage.
        AComments.Add(TrimRight(NormalizeNewlines(T.Text)))
      else if T.Kind in DirectiveKinds then
        ADirectives.Add(DirectiveKey(T.Text));
    end;
  finally
    Tokens.Free;
  end;
end;

// True when A equals B element-for-element.
function SameSequence(const A, B: TList<string>): Boolean;
var
  i: Integer;
begin
  Result:= A.Count = B.Count;
  if not Result then Exit;
  for i:= 0 to A.Count - 1 do
    if A[i] <> B[i] then Exit(False);
end;

// True when every element of A appears in B, in A's order (two-pointer
// subsequence test). Lets the formatter ADD comments without ever being
// able to drop or alter one.
function IsSubsequence(const A, B: TList<string>): Boolean;
var
  ia, ib: Integer;
begin
  ia:= 0;
  ib:= 0;
  while (ia < A.Count) and (ib < B.Count) do
  begin
    if A[ia] = B[ib] then Inc(ia);
    Inc(ib);
  end;
  Result:= ia = A.Count;
end;

function FormatPreservesContent(const AOriginal, AFormatted: string): Boolean;
var
  OrigStr, FmtStr  : TList<string>;
  OrigCom, FmtCom  : TList<string>;
  OrigDir, FmtDir  : TList<string>;
begin
  OrigStr:= TList<string>.Create;  FmtStr:= TList<string>.Create;
  OrigCom:= TList<string>.Create;  FmtCom:= TList<string>.Create;
  OrigDir:= TList<string>.Create;  FmtDir:= TList<string>.Create;
  try
    try
      ExtractContent(AOriginal , OrigStr, OrigCom, OrigDir);
      ExtractContent(AFormatted, FmtStr , FmtCom , FmtDir );
      Result:= SameSequence (OrigStr, FmtStr) and
               SameSequence (OrigDir, FmtDir) and
               IsSubsequence(OrigCom, FmtCom);
    except
      // Cannot verify -> fail closed; the caller keeps the original text.
      Result:= False;
    end;
  finally
    OrigStr.Free;  FmtStr.Free;
    OrigCom.Free;  FmtCom.Free;
    OrigDir.Free;  FmtDir.Free;
  end;
end;

end.
