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
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  SimpleParser.Lexer,
  SimpleParser.Lexer.Types;

type
  TToken = record
    Kind: TptTokenKind;
    ExID: TptTokenKind;
    Text: string;
    Pre:  string;
    Line: Integer;
    Col:  Integer;
  end;

  TTokenList = TList<TToken>;

function LoadTokensFromString(const ASource: string): TTokenList;
function LoadTokensFromFile(const AFileName: string): TTokenList;
function EmitTokens(const ATokens: TTokenList): string;

implementation

function LoadTokensFromString(const ASource: string): TTokenList;
var
  Lex:      TmwPasLex;
  T:        TToken;
  PrevEnd:  Integer;
  CurStart: Integer;
begin
  Result := TTokenList.Create;
  try
    Lex := TmwPasLex.Create;
    try
      Lex.Origin := ASource;
      PrevEnd := 0;
      while Lex.TokenID <> ptNull do
      begin
        CurStart := Lex.TokenPos;
        if CurStart > PrevEnd then
          T.Pre := Copy(ASource, PrevEnd + 1, CurStart - PrevEnd)
        else
          T.Pre := '';
        T.Kind := Lex.TokenID;
        T.ExID := Lex.ExID;
        T.Text := Lex.Token;
        T.Line := Lex.PosXY.Y;
        T.Col  := Lex.PosXY.X;
        Result.Add(T);
        PrevEnd := CurStart + Length(T.Text);
        Lex.Next;
      end;
      if PrevEnd < Length(ASource) then
      begin
        T.Kind := ptNull;
        T.ExID := ptUnknown;
        T.Text := '';
        T.Pre  := Copy(ASource, PrevEnd + 1, Length(ASource) - PrevEnd);
        T.Line := 0;
        T.Col  := 0;
        Result.Add(T);
      end;
    finally
      Lex.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function LoadTokensFromFile(const AFileName: string): TTokenList;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('', TEncoding.ANSI);
  try
    Stream.LoadFromFile(AFileName);
    Result := LoadTokensFromString(Stream.DataString);
  finally
    Stream.Free;
  end;
end;

function EmitTokens(const ATokens: TTokenList): string;
var
  Sb: TStringBuilder;
  T:  TToken;
begin
  Sb := TStringBuilder.Create;
  try
    for T in ATokens do
    begin
      Sb.Append(T.Pre);
      Sb.Append(T.Text);
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

end.
