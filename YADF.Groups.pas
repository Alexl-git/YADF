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

unit YADF.Groups;

interface

uses
  System.Generics.Collections,
  SimpleParser.Lexer.Types,
  YADF.Tokens;

type
  TGroupKind = (
    gkRoot,
    gkParens,
    gkBrackets,
    gkBlock,
    gkUses
  );

  TGroup = class
    Kind:         TGroupKind;
    OpenIdx:      Integer;
    CloseIdx:     Integer;
    OpenerKind:   TptTokenKind;
    Children:     TObjectList<TGroup>;
    Parent:       TGroup;
    ForceClosed:  Boolean;
    constructor Create(AKind: TGroupKind; AOpenIdx: Integer; AOpener: TptTokenKind; AParent: TGroup);
    destructor  Destroy; override;
  end;

function ParseGroups(const ATokens: TTokenList): TGroup;

implementation

constructor TGroup.Create(AKind: TGroupKind; AOpenIdx: Integer; AOpener: TptTokenKind; AParent: TGroup);
begin
  inherited Create;
  Kind        := AKind;
  OpenIdx     := AOpenIdx;
  CloseIdx    := -1;
  OpenerKind  := AOpener;
  ForceClosed := False;
  Parent      := AParent;
  Children    := TObjectList<TGroup>.Create(True);
  if Assigned(AParent) then
    AParent.Children.Add(Self);
end;

destructor TGroup.Destroy;
begin
  Children.Free;
  inherited;
end;

function IsBlockOpener(K: TptTokenKind): Boolean;
begin
  Result := K in [ptBegin, ptRecord, ptCase, ptTry, ptAsm, ptObject];
end;

function ParseGroups(const ATokens: TTokenList): TGroup;
var
  Root: TGroup;
  Cur:  TGroup;
  i:    Integer;
  K:    TptTokenKind;
begin
  Root := TGroup.Create(gkRoot, -1, ptUnknown, nil);
  Cur  := Root;
  for i := 0 to ATokens.Count - 1 do
  begin
    K := ATokens[i].Kind;
    case K of
      ptRoundOpen:
        Cur := TGroup.Create(gkParens, i, K, Cur);
      ptRoundClose:
        if Cur.Kind = gkParens then
        begin
          Cur.CloseIdx := i;
          Cur := Cur.Parent;
        end;
      ptSquareOpen:
        Cur := TGroup.Create(gkBrackets, i, K, Cur);
      ptSquareClose:
        if Cur.Kind = gkBrackets then
        begin
          Cur.CloseIdx := i;
          Cur := Cur.Parent;
        end;
      ptBegin, ptRecord, ptCase, ptTry, ptAsm, ptObject:
        Cur := TGroup.Create(gkBlock, i, K, Cur);
      ptEnd:
        if Cur.Kind = gkBlock then
        begin
          Cur.CloseIdx := i;
          Cur := Cur.Parent;
        end;
      ptUses, ptContains, ptRequires:
        if Cur.Kind <> gkUses then
          Cur := TGroup.Create(gkUses, i, K, Cur);
      ptSemiColon:
        if Cur.Kind = gkUses then
        begin
          Cur.CloseIdx := i;
          Cur := Cur.Parent;
        end;
    end;
  end;
  while Cur <> Root do
  begin
    Cur.CloseIdx    := ATokens.Count - 1;
    Cur.ForceClosed := True;
    Cur := Cur.Parent;
  end;
  Root.CloseIdx := ATokens.Count - 1;
  Result := Root;
end;

end.
