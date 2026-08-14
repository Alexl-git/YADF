{
  YADF -- Yet Another Delphi Formatter

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  THE shared line scanner. Before this unit existed, the "am I inside a
  string / brace comment / paren-star comment / at what bracket depth?"
  state machine was hand-copied ~11 times across YADF.Layout.pas, and the
  copies had drifted (some missed the doubled-quote escape, one missed
  paren-star comments entirely) -- each divergence a latent "two passes
  disagree about the same line" bug. Every line-level pass must use this
  scanner instead of rolling its own.

  Model: a caller iterates a line with SkipNonCode, which consumes string
  literals (with doubled-quote escapes) and comment interiors, and stops
  at either a code character (seCode -- the caller inspects it and then
  advances, normally via StepCode so bracket depth stays maintained), a
  line comment (seLineComment -- the rest of the line is commentary), or
  the end of the line. Brace and paren-star comment state persists across
  lines when the same state record is reused; string state never does
  (Pascal string literals do not span lines) -- BeginLine clears it.
}

unit YADF.LineScan;   // dl:shared YADF, YADFOT, YADFSetup

interface

uses
  System.Classes
  ;

type
  /// <summary>Result of TLineScanState.SkipNonCode: what the scan position
  /// landed on after consuming any string/comment content.</summary>
  // seCode: ALine[i] is a plain code character for the caller.
  // seLineComment: ALine[i] starts a `//` comment (rest of line is comment).
  // seEndOfLine: i ran past Length(ALine).
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (YADF.LineScan.pas), YADF.LineScan.TLineScanState.SkipNonCode (YADF.LineScan.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLineScanEvent = (seCode, seLineComment, seEndOfLine);

  /// <summary>Lexical scanner state for line-level formatter passes: tracks
  /// string literals, `{ }` and `(* *)` comments, and `( [` bracket depth.
  /// Reuse one record across consecutive lines to carry multi-line comment
  /// state; call Reset to start a fresh document and BeginLine at each new
  /// line.</summary>
  /// <remarks>
  /// Pure value record, no heap state -- copy/discard freely.
  /// Not thread-shared; give each scan its own record.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: YADF.Layout.FindAnchorAtTopLevel (YADF.Layout.pas), YADF.Layout.SplitMultiVarDeclarations (YADF.Layout.pas), YADF.Layout.TopLevelLineCommentCol (YADF.Layout.pas), YADF.Layout.JoinRoutineHeaders (YADF.Layout.pas), YADF.LineScan.ComputeBlockCommentLock (YADF.LineScan.pas) (+1 more)
  /// Used in units: YADF.Layout, YADF.LineScan
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLineScanState = record
    InBrace    : Boolean; // inside a { ... } comment (may span lines)
    InParenStar: Boolean; // inside a (* ... *) comment (may span lines)
    InString   : Boolean; // inside a '...' literal (never spans lines)
    Depth      : Integer; // ( and [ nesting depth of CODE brackets
    ClampDepth : Boolean; // when True, an unmatched closer keeps Depth at 0
    // instead of going negative (per-site policy)

    /// <summary>Clears all state; call once before scanning a document.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: YADF.Layout.FindAnchorAtTopLevel (YADF.Layout.pas), YADF.Layout.JoinRoutineHeaders (YADF.Layout.pas), YADF.Layout.SplitMultiVarDeclarations (YADF.Layout.pas), YADF.Layout.TopLevelLineCommentCol (YADF.Layout.pas), YADF.LineScan.ComputeBlockCommentLock (YADF.LineScan.pas) (+5 more)
    /// Writes: InBrace, InParenStar, InString, Depth, ClampDepth
    /// <seealso cref="YADF.LineScan.TLineScanState.BeginLine"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.InBlockComment"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.SkipNonCode"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.StepCode"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Reset;

    /// <summary>Per-line reset: clears the string flag only (string literals
    /// never span lines); comment state and depth carry over.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: YADF.Layout.SplitMultiVarDeclarations (YADF.Layout.pas), YADF.LineScan.ComputeBlockCommentLock (YADF.LineScan.pas), YADF.LineScan.ComputeLineStartDepths (YADF.LineScan.pas), YADF.Layout.JoinRoutineHeaders.ScanLine (YADF.Layout.pas) ?, YADF.Layout.JoinRoutineHeaders.WrapHeaderLine (YADF.Layout.pas) ?
    /// Writes: InString
    /// <seealso cref="YADF.LineScan.TLineScanState.InBlockComment"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.Reset"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.SkipNonCode"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.StepCode"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure BeginLine;

    /// <summary>True while inside a multi-line capable comment
    /// (`{ }` or `(* *)`).</summary>
    /// <returns>Observed: InBrace or InParenStar.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: YADF.Layout.JoinRoutineHeaders (YADF.Layout.pas), YADF.Layout.SplitMultiVarDeclarations (YADF.Layout.pas), YADF.LineScan.ComputeBlockCommentLock (YADF.LineScan.pas)
    /// Returns: InBrace or InParenStar
    /// Reads: InBrace, InParenStar
    /// Pure
    /// <seealso cref="YADF.LineScan.TLineScanState.BeginLine"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.Reset"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.SkipNonCode"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.StepCode"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function InBlockComment: Boolean;

    /// <summary>Consumes any non-code content at ALine[i] -- string literals
    /// (handling the '' escape), comment interiors and openers -- advancing
    /// i past it. Returns with i on the first code character (seCode), on
    /// the first '/' of a `//` comment (seLineComment), or past the end of
    /// the line (seEndOfLine). The caller must not read ALine[i] unless the
    /// result is seCode or seLineComment.</summary>
    /// <param name="ALine">The line being scanned (1-based indexing).</param>
    /// <param name="i">Scan position; advanced in place.</param>
    /// <returns>What the position landed on.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: YADF.Layout.FindAnchorAtTopLevel (YADF.Layout.pas), YADF.Layout.SplitMultiVarDeclarations (YADF.Layout.pas), YADF.Layout.TopLevelLineCommentCol (YADF.Layout.pas), YADF.LineScan.ComputeBlockCommentLock (YADF.LineScan.pas), YADF.LineScan.ComputeLineStartDepths (YADF.LineScan.pas) (+5 more)
    /// Returns: seLineComment; seCode; seEndOfLine
    /// Complexity: 20 (cyclomatic, outer body), 54 lines (full implementation)
    /// Reads: InBrace, InParenStar, InString   Writes: InBrace, InParenStar, InString
    /// Mutates: i (var)
    /// <seealso cref="YADF.LineScan.TLineScanState.BeginLine"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.InBlockComment"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.Reset"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.StepCode"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SkipNonCode(const ALine: string; var i: Integer): TLineScanEvent;

    /// <summary>Consumes ONE code character at ALine[i] (only call after
    /// SkipNonCode returned seCode), maintaining Depth for `( [ ) ]`.</summary>
    /// <param name="ALine"><!-- drag-lint:auto type -->const string</param>
    /// <param name="i"><!-- drag-lint:auto type -->var Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: YADF.Layout.FindAnchorAtTopLevel (YADF.Layout.pas), YADF.Layout.SplitMultiVarDeclarations (YADF.Layout.pas), YADF.Layout.TopLevelLineCommentCol (YADF.Layout.pas), YADF.LineScan.ComputeBlockCommentLock (YADF.LineScan.pas), YADF.LineScan.ComputeLineStartDepths (YADF.LineScan.pas) (+5 more)
    /// Reads: Depth, ClampDepth   Writes: Depth
    /// Mutates: i (var)
    /// <seealso cref="YADF.LineScan.TLineScanState.BeginLine"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.InBlockComment"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.Reset"/>
    /// <seealso cref="YADF.LineScan.TLineScanState.SkipNonCode"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure StepCode(const ALine: string; var i: Integer);
  end; // record

/// <summary>Per-line "inside a multi-line block comment" flags for ALines:
/// True for every line that starts inside, ends inside, or opens/closes a
/// `{ }` / `(* *)` comment. Line-level passes use this to leave block-comment
/// interiors verbatim (reflow, collapse, overflow breaking).</summary>
/// <param name="ALines">The document split into lines.</param>
/// <returns>One flag per line, same indexing as ALines.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Layout.BreakControlBodies (YADF.Layout.pas), YADF.Layout.CollapseShortBlocks (YADF.Layout.pas), YADF.Layout.FormatSource.BreakLongLines (YADF.Layout.pas), YADF.Layout.ReflowLineBreaks (YADF.Layout.pas)
/// Calls: YADF.LineScan.TLineScanState.BeginLine, YADF.LineScan.TLineScanState.InBlockComment, YADF.LineScan.TLineScanState.Reset, YADF.LineScan.TLineScanState.SkipNonCode, YADF.LineScan.TLineScanState.StepCode
/// Pure
/// <seealso cref="YADF.LineScan.TLineScanState.BeginLine"/>
/// <seealso cref="YADF.LineScan.TLineScanState.InBlockComment"/>
/// <seealso cref="YADF.LineScan.TLineScanState.Reset"/>
/// <seealso cref="YADF.LineScan.TLineScanState.SkipNonCode"/>
/// <seealso cref="YADF.LineScan.TLineScanState.StepCode"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ComputeBlockCommentLock(ALines: TStringList): TArray<Boolean>;

/// <summary>Bracket depth at the START of each line, tracked across lines
/// (string- and comment-aware, clamped at zero). A line whose start depth is
/// greater than 0 sits inside a multi-line `( )` / `[ ]` group -- an enum
/// body, array literal, or split parameter list -- and must be excluded from
/// the top-level declaration alignment passes.</summary>
/// <param name="ALines">The document split into lines.</param>
/// <returns>One depth per line, same indexing as ALines.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Layout.AlignByAnchor (YADF.Layout.pas), YADF.Layout.AlignDeclarationSemicolons (YADF.Layout.pas)
/// Calls: YADF.LineScan.TLineScanState.BeginLine, YADF.LineScan.TLineScanState.Reset, YADF.LineScan.TLineScanState.SkipNonCode, YADF.LineScan.TLineScanState.StepCode
/// Pure
/// <seealso cref="YADF.LineScan.TLineScanState.BeginLine"/>
/// <seealso cref="YADF.LineScan.TLineScanState.Reset"/>
/// <seealso cref="YADF.LineScan.TLineScanState.SkipNonCode"/>
/// <seealso cref="YADF.LineScan.TLineScanState.StepCode"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ComputeLineStartDepths(ALines: TStringList): TArray<Integer>;

implementation

{ TLineScanState }

procedure TLineScanState.Reset;
begin
  InBrace    := False;
  InParenStar:= False;
  InString   := False;
  Depth      := 0;
  ClampDepth := False;
end;

procedure TLineScanState.BeginLine;
begin
  InString:= False;
end;

function TLineScanState.InBlockComment: Boolean;
begin
  Result:= InBrace or InParenStar;
end;

function TLineScanState.SkipNonCode(const ALine: string; var i: Integer): TLineScanEvent;
var
  n: Integer;
begin
  n:= Length(ALine);
  while i <= n do
  begin
    if InBrace then
    begin
      if ALine[i] = '}' then InBrace:= False;
      Inc(i);
      Continue;
    end;
    if InParenStar then
    begin
      if (i + 1 <= n) and (ALine[i] = '*') and (ALine[i + 1] = ')') then
      begin
        InParenStar:= False;
        Inc(i, 2);
        Continue;
      end;
      Inc(i);
      Continue;
    end;
    if InString then
    begin
      if ALine[i] = '''' then
      begin
        // '' inside a literal is an escaped quote, not a terminator.
        if (i + 1 <= n) and (ALine[i + 1] = '''') then
          Inc(i, 2)
        else
        begin
          InString:= False;
          Inc(i);
        end;
      end
      else
        Inc(i);
      Continue;
    end; // if
    if ALine[i] = '''' then begin InString:= True; Inc(i); Continue; end;
    if ALine[i] = '{'  then begin InBrace := True; Inc(i); Continue; end;
    if (i + 1 <= n) and (ALine[i] = '(') and (ALine[i + 1] = '*') then
    begin
      InParenStar:= True;
      Inc(i, 2);
      Continue;
    end;
    if (i + 1 <= n) and (ALine[i] = '/') and (ALine[i + 1] = '/') then
      Exit(seLineComment);
    Exit  (seCode       );
  end; // while
  Result:= seEndOfLine;
end; // function

procedure TLineScanState.StepCode(const ALine: string; var i: Integer);
begin
  case ALine[i] of
    '(', '[': Inc(Depth)                                      ;
    ')', ']': if (Depth > 0) or not ClampDepth then Dec(Depth);
  end;
  Inc(i);
end;

{ Shared line-array helpers }

function ComputeBlockCommentLock(ALines: TStringList): TArray<Boolean>;
var
  St           : TLineScanState;
  i            : Integer       ;
  k            : Integer       ;
  Line         : string        ;
  StartedInside: Boolean       ;
begin
  SetLength(Result, ALines.Count);
  St.Reset;
  for i:= 0 to ALines.Count - 1 do
  begin
    StartedInside:= St.InBlockComment;
    Line:= ALines[i];
    St.BeginLine;
    k:= 1;
    while St.SkipNonCode(Line, k) = seCode do
      St.StepCode(Line, k);
    Result[i]:= StartedInside or St.InBlockComment;
  end;
end; // function

function ComputeLineStartDepths(ALines: TStringList): TArray<Integer>;
var
  St  : TLineScanState;
  i   : Integer       ;
  k   : Integer       ;
  Line: string        ;
begin
  SetLength(Result, ALines.Count);
  St.Reset;
  St.ClampDepth:= True;
  for i:= 0 to ALines.Count - 1 do
  begin
    Result[i]:= St.Depth; // depth BEFORE this line is processed
    Line:= ALines[i];
    St.BeginLine;
    k:= 1;
    while St.SkipNonCode(Line, k) = seCode do
      St.StepCode(Line, k);
  end;
end; // function

end.

