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
  /// Used by: declaration (YADF.Debug.pas), declaration (YADF.Groups.pas), YADF.Debug.WalkGroup (YADF.Debug.pas), YADF.Groups.CollectBlockLabelComments (YADF.Groups.pas), YADF.Groups.IsVariantPartCase (YADF.Groups.pas), YADF.Groups.ParseGroups (YADF.Groups.pas), YADF.Layout.ApplyBlockEndLabels (YADF.Layout.pas), YADF.Layout.DowngradeInlineVars (YADF.Layout.pas), YADF.Layout.FormatSource/3 (YADF.Layout.pas), YadfMain.DebugTree (YadfMain.pas)
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
/// Called from: YADF.Groups.CollectBlockLabelComments (YADF.Groups.pas), YADF.Layout.ApplyBlockEndLabels (YADF.Layout.pas), YADF.Layout.DowngradeInlineVars (YADF.Layout.pas), YADF.Layout.FormatSource/3 (YADF.Layout.pas), YadfMain.DebugTree (YadfMain.pas)
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

/// <summary>Returns the keyword for the trailing <c>// keyword</c> marker on the
/// closing <c>end</c> of the block opened at AOpenIdx -- one of record, case, try,
/// asm, object, else, procedure, function, constructor, destructor, while, for, if,
/// initialization, finalization, begin.</summary>
/// <param name="ATokens">The lexed token stream the block belongs to.</param>
/// <param name="AOpenIdx">Index of the block's OPENING token (begin/record/case/...).</param>
/// <returns>The keyword, never ''; 'begin' when no introducer is found.</returns>
/// <remarks>
/// Pure. Single source of truth for BOTH adding and removing block-end markers:
/// the formatter may only delete a marker it would itself have written for that
/// exact block, so add and remove must ask the same function.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Groups.CollectBlockLabelComments.Visit (YADF.Groups.pas), YADF.Layout.ApplyBlockEndLabels.Visit (YADF.Layout.pas)
/// Returns: 'begin'
/// Complexity: 23 (cyclomatic, outer body), 45 lines (full implementation)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindBlockLabel(const ATokens: TTokenList; AOpenIdx: Integer): string;

/// <summary>Flags every comment token that is EXACTLY the block-end marker this
/// formatter would write for the block whose closing <c>end</c> it trails --
/// <c>'// ' + FindBlockLabel(&lt;that block&gt;)</c>, on the <c>end</c>'s own physical
/// line, with nothing after it.</summary>
/// <param name="ATokens">The lexed token stream to scan; parsed into groups internally.</param>
/// <returns>An array parallel to ATokens: True at each removable marker's index.</returns>
/// <remarks>
/// Pure. Membership in the keyword set is necessary but NOT sufficient:
/// <c>// procedure</c> trailing an <c>end</c> that closes a <c>while</c> is somebody's
/// note, not our marker, and is NOT flagged. Neither are <c>//procedure</c> (no space),
/// <c>// procedure -- see ticket 42</c> (trailing prose), or <c>{ procedure }</c>
/// (not a <c>//</c> comment).
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Guard.ExtractContent (YADF.Guard.pas)
/// Calls: FindBlockLabel, TrimRight, YADF.Groups.CollectBlockLabelComments.Visit, YADF.Groups.ParseGroups
/// Returns: Flags
/// Pure
/// <seealso cref="YADF.Groups.CollectBlockLabelComments.Visit"/>
/// <seealso cref="YADF.Groups.ParseGroups"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectBlockLabelComments(const ATokens: TTokenList): TArray<Boolean>;

implementation

uses
  System.SysUtils
  ;

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

// Returns the keyword to use in the trailing `// keyword` comment
// appended to a long block's closing `end`. Cheap path: if the
// opener is itself record/case/try/asm/object, use that keyword
// literally. For a plain `begin`, walk backwards through whitespace,
// comments, and conditional directives looking for the introducing
// keyword (while / for / if / else / procedure / function / try /
// initialization / finalization / a prior `end` which we treat as
// "anonymous begin"). The Limit guard caps the backwards scan at 300
// non-trivial tokens so pathological input can't pin the formatter.
function FindBlockLabel(const ATokens: TTokenList; AOpenIdx: Integer): string;  // dl:ok too-many-exit-points@a182
var
  i    : Integer     ;
  k    : TptTokenKind;
  Limit: Integer     ;
begin
  case ATokens[AOpenIdx].Kind of
    ptRecord: Exit('record');
    ptCase  : Exit('case')  ;
    ptTry   : Exit('try')   ;
    ptAsm   : Exit('asm')   ;
    ptObject: Exit('object');
  end;
  i:= AOpenIdx - 1;
  Limit:= 300;  // dl:ok large-magic-number@86da
  while (i >= 0) and (Limit > 0) do
  begin
    Dec(Limit);
    k:= ATokens[i].Kind;
    if k in [
      ptSpace, ptCRLF, ptCRLFCo, ptAnsiComment, ptBorComment, ptSlashesComment, ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect,
      ptIfEndDirect] then
    begin
      Dec(i);
      Continue;
    end;
    case k of
      ptDo, ptThen    :                       ;  // dl:ok empty-case-branch@a369
      ptElse          : Exit('else')          ;
      ptProcedure     : Exit('procedure')     ;
      ptFunction      : Exit('function')      ;
      ptConstructor   : Exit('constructor')   ;
      ptDestructor    : Exit('destructor')    ;
      ptWhile         : Exit('while')         ;
      ptFor           : Exit('for')           ;
      ptIf            : Exit('if')            ;
      ptCase          : Exit('case')          ;
      ptTry           : Exit('try')           ;
      ptInitialization: Exit('initialization');
      ptFinalization  : Exit('finalization')  ;
      ptEnd           : Exit('begin')         ;
    end; // case
    Dec(i);
  end; // while
  Result:= 'begin';
end; // function

function CollectBlockLabelComments(const ATokens: TTokenList): TArray<Boolean>;
var
  Root : TGroup            ;
  Flags: TArray<Boolean>   ;

  procedure Visit(G: TGroup);
  var
    Child  : TGroup ;
    k      : Integer;
    EndLine: Integer;
    Want   : string ;
  begin
    for Child in G.Children do
    begin
      Visit(Child);
      if (Child.Kind <> gkBlock) or Child.ForceClosed or (Child.CloseIdx <= Child.OpenIdx) then
        Continue;
      Want:= '// ' + FindBlockLabel(ATokens, Child.OpenIdx);
      EndLine:= ATokens[Child.CloseIdx].Line;
      k:= Child.CloseIdx + 1;
      while (k < ATokens.Count) and (ATokens[k].Line = EndLine) do
      begin
        if (ATokens[k].Kind = ptSlashesComment) and (TrimRight(ATokens[k].Text) = Want) then
          Flags[k]:= True;
        Inc(k);
      end;
    end; // for
  end; // procedure

begin
  SetLength(Flags, ATokens.Count);
  Root:= ParseGroups(ATokens);
  try
    Visit(Root);
  finally
    Root.Free;
  end;
  Result:= Flags;
end; // function

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


