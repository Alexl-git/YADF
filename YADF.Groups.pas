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

unit YADF.Groups;   // dl:shared YADF, YADFOT, YADFSetup

interface

uses
  System.Generics.Collections
  , SimpleParser.Lexer.Types
  , YADF.Tokens
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (YADF.Groups.pas), YADF.Groups.TGroup.Create (YADF.Groups.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGroupKind = ( gkRoot, gkParens, gkBrackets, gkBlock, gkUses );

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (YADF.Debug.pas), declaration (YADF.Groups.pas), YADF.Debug.WalkGroup (YADF.Debug.pas), YADF.Groups.IsVariantPartCase (YADF.Groups.pas), YADF.Groups.ParseGroups (YADF.Groups.pas), YADF.Layout.DowngradeInlineVars (YADF.Layout.pas), YADF.Layout.FormatSource/3 (YADF.Layout.pas), YadfMain.DebugTree (YadfMain.pas)
  /// Used in units: YADF.Debug, YADF.Groups, YADF.Layout, YadfMain
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGroup = class
    Kind       : TGroupKind         ;
    OpenIdx    : Integer            ;
    CloseIdx   : Integer            ;
    OpenerKind : TptTokenKind       ;
    Children   : TObjectList<TGroup>;
    Parent     : TGroup             ;
    ForceClosed: Boolean            ;
    /// <param name="AKind"><!-- drag-lint:auto type -->TGroupKind</param>
    /// <param name="AOpenIdx"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AOpener"><!-- drag-lint:auto type -->TptTokenKind</param>
    /// <param name="AParent"><!-- drag-lint:auto type -->TGroup</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: YADF.Groups.ParseGroups (YADF.Groups.pas)
    /// constructor
    /// Writes: Kind, OpenIdx, CloseIdx, OpenerKind, ForceClosed, Parent, Children
    /// <seealso cref="YADF.Groups.TGroup.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(AKind: TGroupKind; AOpenIdx: Integer; AOpener: TptTokenKind; AParent: TGroup);
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Reads: Children
    /// Pure
    /// <seealso cref="YADF.Groups.TGroup.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
  end;

/// <param name="ATokens"><!-- drag-lint:auto type -->const TTokenList</param>
/// <returns>Observed: Root.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Layout.DowngradeInlineVars (YADF.Layout.pas), YADF.Layout.FormatSource/3 (YADF.Layout.pas), YadfMain.DebugTree (YadfMain.pas)
/// Calls: YADF.Groups.IsVariantPartCase, YADF.Groups.PrevSignificantIdx, YADF.Groups.TGroup.Create
/// Returns: Root
/// Complexity: 21 (cyclomatic, outer body), 57 lines (full implementation)
/// Pure
/// <seealso cref="YADF.Groups.IsVariantPartCase"/>
/// <seealso cref="YADF.Groups.PrevSignificantIdx"/>
/// <seealso cref="YADF.Groups.TGroup.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseGroups(const ATokens: TTokenList): TGroup;

implementation

constructor TGroup.Create(AKind: TGroupKind; AOpenIdx: Integer; AOpener: TptTokenKind; AParent: TGroup);
begin
  inherited Create;
  Kind   := AKind;
  OpenIdx:= AOpenIdx;
  CloseIdx:= -1;
  OpenerKind := AOpener;
  ForceClosed:= False;
  Parent     := AParent;
  Children:= TObjectList<TGroup>.Create(True);
  if Assigned(AParent) then
    AParent.Children.Add(Self);
end; // constructor

destructor TGroup.Destroy;
begin
  Children.Free;
  inherited;  // dl:ok inherited-bare@246d
end;

// Index of the previous significant token (skipping whitespace/CRLF), or -1.
function PrevSignificantIdx(const ATokens: TTokenList; AFrom: Integer): Integer;
begin
  Result:= AFrom;
  while (Result >= 0) and (ATokens[Result].Kind in [ptSpace, ptCRLF, ptCRLFCo]) do
    Dec(Result);
end;

// True when a `case` at the current nesting position is the VARIANT PART of a
// record/object declaration (`case Tag: T of` inside the decl, possibly nested
// inside the variant parens): the nearest enclosing BLOCK -- looking through
// parens/brackets -- is a record/object. A variant part has NO `end` of its
// own (the record's end closes it), so it must not open a block group: doing
// so made the record's end close the case instead, leaving the record group
// open and creeping everything after it one level right.
function IsVariantPartCase(ACur: TGroup): Boolean;
var
  G: TGroup;
begin
  G:= ACur;
  while (G <> nil) and (G.Kind in [gkParens, gkBrackets]) do
    G:= G.Parent;
  Result:= (G <> nil) and (G.Kind = gkBlock) and (G.OpenerKind in [ptRecord, ptObject]);
end;

function ParseGroups(const ATokens: TTokenList): TGroup;
var
  Root: TGroup      ;
  Cur : TGroup      ;
  i   : Integer     ;
  p   : Integer     ;
  K   : TptTokenKind;
begin
  Root:= TGroup.Create(gkRoot, -1, ptUnknown, nil);
  Cur:= Root;
  for i:= 0 to ATokens.Count - 1 do
  begin
    K:= ATokens[i].Kind;
    case K of
      ptRoundOpen : Cur:= TGroup.Create(gkParens, i, K, Cur);
      ptRoundClose: if Cur.Kind = gkParens then
      begin
        Cur.CloseIdx:= i;
        Cur:= Cur.Parent;
      end;
      ptSquareOpen : Cur:= TGroup.Create(gkBrackets, i, K, Cur);
      ptSquareClose: if Cur.Kind = gkBrackets then
      begin
        Cur.CloseIdx:= i;
        Cur:= Cur.Parent;
      end;
      ptBegin, ptRecord, ptTry, ptAsm: Cur:= TGroup.Create(gkBlock, i, K, Cur)                                   ;
      ptCase                         : if not IsVariantPartCase(Cur) then Cur:= TGroup.Create(gkBlock, i, K, Cur);
      ptObject                       :
      begin
        // `object` opens a block in `type T = object ... end`, but in `of object`
        // (method-pointer / event types) it is a modifier, not a block opener.
        p:= PrevSignificantIdx(ATokens, i - 1);
        if (p < 0) or (ATokens[p].Kind <> ptOf) then
          Cur:= TGroup.Create(gkBlock, i, K, Cur);
      end;
      ptEnd : if Cur.Kind = gkBlock then
      begin
        Cur.CloseIdx:= i;
        Cur:= Cur.Parent;
      end;
      ptUses, ptContains, ptRequires: if Cur.Kind <> gkUses then Cur:= TGroup.Create(gkUses, i, K, Cur);
      ptSemiColon                   : if Cur.Kind = gkUses then
      begin
        Cur.CloseIdx:= i;
        Cur:= Cur.Parent;
      end;
    end; // case
  end; // for
  while Cur <> Root do
  begin
    Cur.CloseIdx:= ATokens.Count - 1;
    Cur.ForceClosed:= True;
    Cur:= Cur.Parent;
  end;
  Root.CloseIdx:= ATokens.Count - 1;
  Result:= Root;
end; // function

end.


