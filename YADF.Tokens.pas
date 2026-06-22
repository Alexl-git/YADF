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

unit YADF.Tokens;

interface

uses
  System.Classes
  , System.SysUtils
  , System.Generics.Collections
  , SimpleParser.Lexer
  , SimpleParser.Lexer.Types
  ;

type
  TToken = record
    Kind: TptTokenKind;
    ExID: TptTokenKind;
    Text: string;
    Pre : string;
    Line: Integer;
    Col : Integer;
  end;

  TTokenList = TList<TToken>;

function LoadTokensFromString(const ASource: string): TTokenList;
function EmitTokens(const ATokens: TTokenList): string;

implementation

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
  IncSentinel = 'ZQYADF'; // appended to the directive word; unique enough
                          // that real source never collides.

// True for a 7-bit ASCII letter (A-Z / a-z). Shared by the include-directive
// shield and unshield scans; deliberately ASCII-only (not Unicode-aware
// TCharacter.IsLetter) to match the lexer's directive-word grammar.
function IsAsciiAlpha(C: Char): Boolean;
begin
  Result:= ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

function ShieldIncludeDirectives(const ASource: string): string;
var
  i, n   : Integer;
  Sb     : TStringBuilder;
  WordEnd: Integer;
  Wrd    : string;
  NextCh : Char;
begin
  n:= Length(ASource);
  Sb:= TStringBuilder.Create;
  try
    i:= 1;
    while i <= n do
    begin
      // Skip string literals verbatim.
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
        end;
        Continue;
      end;
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
      end;
      // `{ ... }` -- a directive `{$...}` or a plain brace comment.
      if ASource[i] = '{' then
      begin
        if (i + 1 <= n) and (ASource[i + 1] = '$') then
        begin
          // Compiler directive. Read the directive word.
          WordEnd:= i + 2;
          while (WordEnd <= n) and IsAsciiAlpha(ASource[WordEnd]) do Inc(WordEnd);
          Wrd:= Copy(ASource, i + 2, WordEnd - (i + 2));
          if WordEnd <= n then NextCh:= ASource[WordEnd] else NextCh:= '}';
          // Include form: `{$INCLUDE ...}` always; `{$I ...}` only when
          // the char after the word is NOT `+`/`-`/`}` (those are the
          // IOCHECKS toggle, not an include).
          if SameText(Wrd, 'INCLUDE') or
             (SameText(Wrd, 'I') and (NextCh <> '+') and (NextCh <> '-') and (NextCh <> '}')) then
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
        end;
        // Plain brace comment: copy through `}` verbatim.
        while (i <= n) and (ASource[i] <> '}') do
        begin
          Sb.Append(ASource[i]);
          Inc(i);
        end;
        Continue;
      end;
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
var
  P  : Integer;
  Wrd: string;
  WE : Integer;
begin
  Result:= False;
  if (Length(AToken.Text) < 4) or (AToken.Text[1] <> '{') or (AToken.Text[2] <> '$') then Exit;
  WE:= 3;
  while (WE <= Length(AToken.Text)) and IsAsciiAlpha(AToken.Text[WE]) do Inc(WE);
  Wrd:= Copy(AToken.Text, 3, WE - 3);
  if not SameText(Copy(Wrd, Length(Wrd) - Length(IncSentinel) + 1, Length(IncSentinel)), IncSentinel) then Exit;
  P:= Length(Wrd) - Length(IncSentinel);
  if not (SameText(Copy(Wrd, 1, P), 'I') or SameText(Copy(Wrd, 1, P), 'INCLUDE')) then Exit;
  AToken.Text:= '{$' + Copy(Wrd, 1, P) + Copy(AToken.Text, WE, MaxInt);
  AToken.Kind:= ptIncludeDirect;
  Result:= True;
end;

function LoadTokensFromString(const ASource: string): TTokenList;
var
  Src     : string;
  Lex     : TmwPasLex;
  T       : TToken;
  PrevEnd : Integer;
  CurStart: Integer;
  k       : Integer;
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
        T.ExID:= Lex.ExID   ;
        T.Text:= Lex.Token  ;
        T.Line:= Lex.PosXY.Y;
        T.Col := Lex.PosXY.X;
        Result.Add(T);
        PrevEnd:= CurStart + Length(T.Text);
        Lex.Next;
      end;
      if PrevEnd < Length(Src) then
      begin
        T.Kind:= ptNull   ;
        T.ExID:= ptUnknown;
        T.Text:= ''       ;
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
  except
    Result.Free;
    raise;
  end; // try
end; // function

function EmitTokens(const ATokens: TTokenList): string;
var
  Sb: TStringBuilder;
  T : TToken;
begin
  Sb:= TStringBuilder.Create;
  try
    for T in ATokens do
    begin
      Sb.Append(T.Pre);
      Sb.Append(T.Text);
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
