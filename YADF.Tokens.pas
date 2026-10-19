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

unit YADF.Tokens;   // dl:shared YADF, YADFOT, YADFSetup

interface

uses
  System.Classes
  , System.SysUtils
  , System.Generics.Collections
  , SimpleParser.Lexer
  , SimpleParser.Lexer.Types
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]YADF.Guard.ExtractContent (YADF.Guard.pas), [YADF]YADF.Layout.ApplyCapitalization (YADF.Layout.pas), [YADF]YADF.Layout.CollapseInteriorSpacesInLine (YADF.Layout.pas), [YADF]YADF.Layout.CollectParensItems (YADF.Layout.pas), [YADF]YADF.Layout.CollectUsesItems (YADF.Layout.pas), [YADF]YADF.Layout.DowngradeInlineVars (YADF.Layout.pas), [YADF]YADF.Layout.DowngradeInlineVars.MakeTok (YADF.Layout.pas), [YADF]YADF.Layout.NormalizeAssignSpacing (YADF.Layout.pas), [YADF]YADF.Layout.NormalizeOperatorSpacing (YADF.Layout.pas), [YADF]YADF.Layout.NormalizeOperatorSpacing.MakeSpace (YADF.Layout.pas), [YADF]YADF.Layout.ReindentByDepth (YADF.Layout.pas), [YADF]YADF.Layout.RenderUsesGroup (YADF.Layout.pas), [YADF]YADF.Layout.ShieldAsmBodies (YADF.Layout.pas), [YADF]YADF.Layout.ShieldMultilineTokens (YADF.Layout.pas), [YADF]YADF.Layout.TightenAnchorSpacingInLine (YADF.Layout.pas), [YADF]YADF.Tokens.EmitTokens (YADF.Tokens.pas),
  /// [YADF]YADF.Tokens.LoadTokensFromString (YADF.Tokens.pas), [YADF]YADF.Tokens.UnshieldIncludeToken (YADF.Tokens.pas), [YADF]YadfMain.ParseDprUnits (YadfMain.pas)</para>
  /// <para>Used in units: YADF.Guard, YADF.Layout, YADF.Tokens, YadfMain</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TToken = record
    Kind: TptTokenKind;
    ExID: TptTokenKind;
    Text: string      ;
    Pre : string      ;
    Line: Integer     ;
    Col : Integer     ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Debug.pas), [YADF]declaration (YADF.Groups.pas), [YADF]declaration (YADF.Tokens.pas), [YADF]YADF.Debug.PreviewSpan (YADF.Debug.pas), [YADF]YADF.Debug.WalkGroup (YADF.Debug.pas), [YADF]YADF.Groups.IsRecordConstraint (YADF.Groups.pas), [YADF]YADF.Groups.PrevSignificantIdx (YADF.Groups.pas), [YADF]YADF.Guard.AddAsmLines (YADF.Guard.pas), [YADF]YADF.Guard.ExtractContent (YADF.Guard.pas), [YADF]YADF.Layout.ApplyBlockEndLabels (YADF.Layout.pas), [YADF]YADF.Layout.ApplyCapitalization (YADF.Layout.pas), [YADF]YADF.Layout.CollapseInteriorSpacesInLine (YADF.Layout.pas), [YADF]YADF.Layout.CollectParensItems (YADF.Layout.pas), [YADF]YADF.Layout.CollectUsesItems (YADF.Layout.pas), [YADF]YADF.Layout.DowngradeInlineVars (YADF.Layout.pas), [YADF]YADF.Layout.FormatSource/3 (YADF.Layout.pas), [YADF]YADF.Layout.InlineRenderRange (YADF.Layout.pas), [YADF]YADF.Layout.MarkEnumMembers (YADF.Layout.pas), [YADF]YADF.Layout.MarkExternalName (YADF.Layout.pas),
  /// [YADF]YADF.Layout.NormalizeAssignSpacing (YADF.Layout.pas), [YADF]YADF.Layout.NormalizeOperatorSpacing (YADF.Layout.pas), [YADF]YADF.Layout.RangeHasConditionalDirective (YADF.Layout.pas), [YADF]YADF.Layout.RangeHasLineComment (YADF.Layout.pas), [YADF]YADF.Layout.RangeHasMultiLineToken (YADF.Layout.pas), [YADF]YADF.Layout.ReindentByDepth (YADF.Layout.pas), [YADF]YADF.Layout.RenderTokensForGuard (YADF.Layout.pas), [YADF]YADF.Layout.RenderUsesGroup (YADF.Layout.pas), [YADF]YADF.Layout.ShieldAsmBodies (YADF.Layout.pas), [YADF]YADF.Layout.ShieldMultilineTokens (YADF.Layout.pas), [YADF]YADF.Layout.SpellingSensitiveIdents (YADF.Layout.pas), [YADF]YADF.Layout.TightenAnchorSpacingInLine (YADF.Layout.pas), [YADF]YADF.Layout.TokIs (YADF.Layout.pas), [YADF]YADF.Tokens.LoadTokensFromString (YADF.Tokens.pas), [YADF]YadfMain.DebugTree (YadfMain.pas), [YADF]YadfMain.ParseDprUnits (YadfMain.pas), [YADF]YadfMain.RoundTrip (YadfMain.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTokenList = TList<TToken>;

/// <param name="ASource"><!-- drag-lint:auto type -->const string</param>
/// <returns>Observed: TTokenList.Create.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Guard.ExtractContent (YADF.Guard.pas), YADF.Layout.ApplyBlockEndLabels (YADF.Layout.pas), YADF.Layout.CollapseInteriorSpacesInLine (YADF.Layout.pas), YADF.Layout.FormatSource/3 (YADF.Layout.pas), YADF.Layout.ReindentByDepth (YADF.Layout.pas), YADF.Layout.TightenAnchorSpacingInLine (YADF.Layout.pas), YadfMain.DebugTree (YadfMain.pas), YadfMain.ParseDprUnits (YadfMain.pas), YadfMain.RoundTrip (YadfMain.pas)</para>
/// <para>Calls: Copy, SimpleParser.Lexer.TmwBasePasLex.GetPosXY, SimpleParser.Lexer.TmwBasePasLex.GetToken, SimpleParser.Lexer.TmwBasePasLex.Next, SimpleParser.Lexer.TmwBasePasLex.SetOrigin, SimpleParser.Lexer.TmwPasLex.Create, YADF.Tokens.ShieldIncludeDirectives, YADF.Tokens.UnshieldIncludeToken</para>
/// <para>Returns: TTokenList.Create</para>
/// <para>Catches: Exception (re-raise)</para>
/// <seealso cref="SimpleParser.Lexer.TmwBasePasLex.GetPosXY"/>
/// <seealso cref="SimpleParser.Lexer.TmwBasePasLex.GetToken"/>
/// <seealso cref="SimpleParser.Lexer.TmwBasePasLex.Next"/>
/// <seealso cref="SimpleParser.Lexer.TmwBasePasLex.SetOrigin"/>
/// <seealso cref="SimpleParser.Lexer.TmwPasLex.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadTokensFromString(const ASource: string): TTokenList;
/// <param name="ATokens"><!-- drag-lint:auto type -->const TTokenList</param>
/// <returns>Observed: Sb.ToString.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YadfMain.RoundTrip (YadfMain.pas)</para>
/// <para>Returns: Sb.ToString</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EmitTokens(const ATokens: TTokenList): string;

/// <summary>True when ATokens[AIdx] is the `end` that closes an `asm` block --
/// i.e. a ptEnd token that is NOT a BASM label such as `@@End` / `@End`.</summary>
/// <param name="ATokens">The token list.</param>
/// <param name="AIdx">Index to test; out-of-range returns False.</param>
/// <returns>False for any other token, and for an `end` glued to a preceding
/// `@` (the lexer reports the `End` of `@@End:` as the keyword).</returns>
/// <remarks>
/// Shared by the asm shield (YADF.Layout) and the guard's asm-line
/// stream (YADF.Guard), which must agree on where an asm body stops.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Guard.AddAsmLines (YADF.Guard.pas), YADF.Guard.ExtractContent (YADF.Guard.pas), YADF.Layout.ShieldAsmBodies (YADF.Layout.pas)</para>
/// <para>Returns: (AIdx &gt;= 0) and (AIdx &lt; ATokens.Count) and (ATokens[AIdx].Kind = ptEnd); not ((Prev &lt;&gt; '') and (Prev[Length(Prev)] = '@'))</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsAsmBlockEnd(const ATokens: TTokenList; AIdx: Integer): Boolean;

implementation

function IsAsmBlockEnd(const ATokens: TTokenList; AIdx: Integer): Boolean;
var
  Prev: string;
begin
  Result:= (AIdx >= 0) and (AIdx < ATokens.Count) and (ATokens[AIdx].Kind = ptEnd);
  if Result and (AIdx > 0) and (ATokens[AIdx].Pre = '') then
  begin
    Prev:= ATokens[AIdx - 1].Text;
    Result:= not ((Prev <> '') and (Prev[Length(Prev)] = '@'));
  end;
end;

// ---------------------------------------------------------------------------
// Include-directive shield.
//
// The DelphiAST lexer SILENTLY DROPS `{$I file}` / `{$INCLUDE file}`
// directives: in TmwBasePasLex.Next the `PtIncludeDirect` branch is
// `if Assigned(FIncludeHandler) ... else Next;` -- with no include
// handler set (YADF deliberately doesn't expand includes) it calls
// Next, advancing past the directive WITHOUT emitting a token. The
// directive never reaches YADF, so a reformat deletes it -- flipping
// off the conditional symbols it defined (critical data loss; see
// BUG_DROPPED_INCLUDE_DIRECTIVE).
//
// DelphiAST is an upstream sibling repo compiled as-is (not vendored
// in YADF's repo), so it can't be patched in a way that ships. The
// fix is a YADF-side shield: before lexing, append a unique sentinel
// suffix to the directive WORD of true include directives so the
// lexer classifies them as a generic `ptCompDirect` (which it emits
// normally) instead of `ptIncludeDirect` (which it eats). After the
// token list is built, the sentinel is stripped and the token's Kind
// restored to ptIncludeDirect. Toggle forms `{$I+}` / `{$I-}`
// (IOCHECKS, not include) are left untouched. The scan skips string
// literals and `//`, `(* *)`, `{ }` comments so a `{$I` inside those
// is never transformed.
const
  ML_MIN_QUOTES = 3; // a multi-line string opens with an ODD run of at least this many apostrophes
  IncSentinel = 'ZQYADF'; // appended to the directive word; unique enough
  // that real source never collides.

  // True for a 7-bit ASCII letter (A-Z / a-z). Shared by the include-directive
  // shield and unshield scans; deliberately ASCII-only (not Unicode-aware
  // TCharacter.IsLetter) to match the lexer's directive-word grammar.
function IsAsciiAlpha(C: Char): Boolean;
begin
  Result:= ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

function ShieldIncludeDirectives(const ASource: string): string;  // dl:ok deep-nesting@4396, cyclomatic-complexity@fc29, cognitive-complexity@0679
var
  i      : Integer       ;
  n      : Integer       ;
  Sb     : TStringBuilder;
  WordEnd: Integer       ;
  Wrd    : string        ;
  NextCh : Char          ;
  Run    : Integer       ; // apostrophes opening a multi-line string
  EndRun : Integer       ; // apostrophes in a run inside one
begin
  n:= Length(ASource);
  Sb:= TStringBuilder.Create;
  try
    i:= 1;
    while i <= n do
    begin
      // Skip a multi-line ''' string verbatim, by the lexer's own rule
      // (SimpleParser.Lexer StringProc): an ODD run of 3+ apostrophes followed
      // directly by a line break opens it; the next run of the SAME length
      // closes it. Without this an odd apostrophe in the body (`don't`)
      // desynchronised the scan for the rest of the file.
      if ASource[i] = '''' then
      begin
        Run:= 0;
        while (i + Run <= n) and (ASource[i + Run] = '''') do
          Inc(Run);
        if (Run >= ML_MIN_QUOTES) and Odd(Run) and (i + Run <= n) and CharInSet(ASource[i + Run], [#13, #10]) then
        begin
          Sb.Append(ASource, i - 1, Run);
          Inc(i, Run);
          while i <= n do
          begin
            if ASource[i] = '''' then
            begin
              EndRun:= 0;
              while (i + EndRun <= n) and (ASource[i + EndRun] = '''') do
                Inc(EndRun);
              Sb.Append(ASource, i - 1, EndRun);
              Inc(i, EndRun);
              if EndRun = Run then
                Break;
            end
            else
            begin
              Sb.Append(ASource[i]);
              Inc(i);
            end;
          end; // while
          Continue;
        end; // if
      end; // if
      // Skip single-line string literals verbatim.
      if ASource[i] = '''' then
      begin
        Sb.Append(ASource[i]);
        Inc(i);
        while i <= n do
        begin
          Sb.Append(ASource[i]);
          if ASource[i] = '''' then
          begin
            if (i + 1 <= n) and (ASource[i + 1] = '''') then
            begin
              Sb.Append(ASource[i + 1]);
              Inc(i, 2);
              Continue;
            end;
            Inc(i);
            Break;
          end;
          Inc(i);
        end; // while
        Continue;
      end; // if
      // Skip // line comments verbatim.
      if (ASource[i] = '/') and (i + 1 <= n) and (ASource[i + 1] = '/') then
      begin
        while (i <= n) and (ASource[i] <> #10) do
        begin
          Sb.Append(ASource[i]);
          Inc(i);
        end;
        Continue;
      end;
      // Skip (* *) block comments verbatim.
      if (ASource[i] = '(') and (i + 1 <= n) and (ASource[i + 1] = '*') then
      begin
        Sb.Append('(*');
        Inc(i, 2);
        while i <= n do
        begin
          if (ASource[i] = '*') and (i + 1 <= n) and (ASource[i + 1] = ')') then
          begin
            Sb.Append('*)');
            Inc(i, 2);
            Break;
          end;
          Sb.Append(ASource[i]);
          Inc(i);
        end;
        Continue;
      end; // if
      // `{ ... }` -- a directive `{$...}` or a plain brace comment.
      if ASource[i] = '{' then
      begin
        if (i + 1 <= n) and (ASource[i + 1] = '$') then
        begin
          // Compiler directive. Read the directive word.
          WordEnd:= i + 2;
          while (WordEnd <= n) and IsAsciiAlpha(ASource[WordEnd]) do
            Inc(WordEnd);
          Wrd:= Copy(ASource, i + 2, WordEnd - (i + 2));
          if WordEnd <= n then
            NextCh:= ASource[WordEnd]
          else
            NextCh:= '}';
          // Include form: `{$INCLUDE ...}` always; `{$I ...}` only when
          // the char after the word is NOT `+`/`-`/`}` (those are the
          // IOCHECKS toggle, not an include).
          if SameText(Wrd, 'INCLUDE') or (SameText(Wrd, 'I') and (NextCh <> '+') and (NextCh <> '-') and (NextCh <> '}')) then
          begin
            Sb.Append(Copy(ASource, i, WordEnd - i)); // `{$` + word
            Sb.Append(IncSentinel);
            i:= WordEnd;
            Continue;
          end;
          // Other directive: copy through the closing `}` verbatim.
          while (i <= n) and (ASource[i] <> '}') do
          begin
            Sb.Append(ASource[i]);
            Inc(i);
          end;
          Continue;
        end; // if
        // Plain brace comment: copy through `}` verbatim.
        while (i <= n) and (ASource[i] <> '}') do
        begin
          Sb.Append(ASource[i]);
          Inc(i);
        end;
        Continue;
      end; // if
      Sb.Append(ASource[i]);
      Inc(i);
    end; // while
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

// Reverses ShieldIncludeDirectives on one token's text: strips the
// sentinel from the directive word and returns True (caller resets
// Kind to ptIncludeDirect). No-op (returns False) for any other token.
function UnshieldIncludeToken(var AToken: TToken): Boolean;
const
  MIN_DIRECTIVE_LEN = 4;  // shortest shielded directive: '{$' + one letter + '}'
  DIRECTIVE_WORD   = 3;  // 1-based index of the first directive-word char, after '{$'
var
  P  : Integer;
  Wrd: string ;
  WE : Integer;
begin
  Result:= False;
  if (Length(AToken.Text) < MIN_DIRECTIVE_LEN) or (AToken.Text[1] <> '{') or (AToken.Text[2] <> '$') then
    Exit;
  WE:= DIRECTIVE_WORD;
  while (WE <= Length(AToken.Text)) and IsAsciiAlpha(AToken.Text[WE]) do
    Inc(WE);
  Wrd:= Copy(AToken.Text, DIRECTIVE_WORD, WE - DIRECTIVE_WORD);
  if not SameText(Copy(Wrd, Length(Wrd) - Length(IncSentinel) + 1, Length(IncSentinel)), IncSentinel) then
    Exit;
  P:= Length(Wrd) - Length(IncSentinel);
  if not (SameText(Copy(Wrd, 1, P), 'I') or SameText(Copy(Wrd, 1, P), 'INCLUDE')) then
    Exit;
  AToken.Text:= '{$' + Copy(Wrd, 1, P) + Copy(AToken.Text, WE, MaxInt);
  AToken.Kind:= ptIncludeDirect;
  Result:= True;
end; // function

function LoadTokensFromString(const ASource: string): TTokenList;
var
  Src     : string   ;
  Lex     : TmwPasLex;
  T       : TToken   ;
  PrevEnd : Integer  ;
  CurStart: Integer  ;
  k       : Integer  ;
begin
  Src:= ShieldIncludeDirectives(ASource);
  Result:= TTokenList.Create;
  try
    Lex:= TmwPasLex.Create;
    try
      Lex.Origin:= Src;
      PrevEnd:= 0;
      while Lex.TokenID <> ptNull do
      begin
        CurStart:= Lex.TokenPos;
        if CurStart > PrevEnd then
          T.Pre:= Copy(Src, PrevEnd + 1, CurStart - PrevEnd)
        else
          T.Pre:= '';
        T.Kind:= Lex.TokenID;
        T.ExID:= Lex.ExID;
        T.Text:= Lex.Token;
        T.Line:= Lex.PosXY.Y;
        T.Col := Lex.PosXY.X;
        Result.Add(T);
        PrevEnd:= CurStart + Length(T.Text);
        Lex.Next;
      end; // while
      if PrevEnd < Length(Src) then
      begin
        T.Kind:= ptNull;
        T.ExID:= ptUnknown;
        T.Text:= '';
        T.Pre:= Copy(Src, PrevEnd + 1, Length(Src) - PrevEnd);
        T.Line:= 0;
        T.Col := 0;
        Result.Add(T);
      end;
      // Restore shielded include directives: strip the sentinel and
      // reset Kind to ptIncludeDirect so the token round-trips to its
      // exact original text.
      for k:= 0 to Result.Count - 1 do
      begin
        T:= Result[k];
        if UnshieldIncludeToken(T) then
          Result[k]:= T;
      end;
    finally
      Lex.Free;
    end; // try
  except  // dl:ok bare-except@041e
    Result.Free;
    raise;
  end; // try
end; // function

function EmitTokens(const ATokens: TTokenList): string;
var
  Sb: TStringBuilder;
  T : TToken        ;
begin
  Sb:= TStringBuilder.Create;
  try
    for T in ATokens do
    begin
      Sb.Append(T.Pre );
      Sb.Append(T.Text);
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end; // function

end.


