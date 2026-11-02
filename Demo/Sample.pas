unit Sample;

// ============================================================================
// YADF live preview (Tools > Options > YADF, and YADFSetup).
//
// LEFT: this source as written. RIGHT: YADF's output with the settings on the
// page. Each "// == Option: X ==" block shows ONE option: toggle that box and
// only that block changes on the right. A block named "X + Y" is shared by two
// options that work on the same construct. "// == Rule: ... ==" blocks show
// fixed rules that apply whatever the settings. Outside the spot each block
// demonstrates, the code is written the way YADF formats it by default, so
// the other blocks stay put while you experiment.
// The file compiles (Delphi 13); Test\test_sample_sections.ps1 checks that it
// does, and that each option changes only its own block.
// ============================================================================

interface
// == Option: BlanksBeforeType ==
// Blank lines forced before each "type" keyword; 1 puts one above "type".
type
  TSampleKind = (skNone, skLow, skHigh);

  // == Option: BlanksBeforeSection ==
  // Blank lines forced before each unit section; 1 puts one above
  // "implementation".
implementation

// == Option: UsesAlwaysBreak + UsesCommaLast ==
// UsesAlwaysBreak ON (default): one unit per line; OFF: one line when it fits.
// UsesCommaLast OFF (default): comma-first (", Unit" and ";" alone); ON:
// comma-last ("Unit," ... "LastUnit;").
uses System.SysUtils, System.Types, System.Math;

// == Rule: block keywords start a line ==
// repeat / until / try / finally / end always start a line, whatever
// "Pack several statements on one line" says.

procedure RuleBlockKeywords(var K: Integer);
begin
  repeat Dec(K); until K <= 0; try Inc(K); finally Dec(K); end;
end;

// == Rule: one declaration per line ==
// "A: T; B: T;" written on one line is always split.

procedure RuleOneDeclPerLine;
var
  RuleA: Integer; RuleB: Integer;
begin
  RuleA:= 1;

  RuleB:= RuleA;

  Writeln(RuleB);
end;

// == Rule: tight parens and single spaces ==
// No blank after "(" or before ")"; runs of blanks inside code become one.

procedure RuleTightParens;
begin
  Writeln( Format( '%d',   [1] ) );
end;

// == Rule: comments ==
// A one-line brace comment travels with its neighbour token when lines are
// split or joined; a // comment anywhere in a span blocks the join.

procedure RuleComments(var K: Integer);
begin
  repeat {count down} Dec(K); until K <= 0;

  Writeln(Format('%d %d', [K, // keeps the line break
        K]));
end;

// == Option: ReflowLines + BreakLongExpressions ==
// ReflowLines ON (default): a statement broken by hand is joined when it fits
// the max line length, and a longer one is wrapped. OFF: the author's line
// breaks are kept and long lines are left as-is.
// BreakLongExpressions ON (default): a statement over the max line length gets
// one component per line, the operator or comma leading; a long bracketed list
// becomes a tree, one whole branch per line. OFF: greedy packing, comma-last.
const
  BigTable: array[0..3] of array[0..5] of Integer = ((100001, 100002, 100003, 100004, 100005, 100006), (200001, 200002, 200003, 200004, 200005, 200006), (300001, 300002, 300003, 300004, 300005, 300006), (400001, 400002, 400003, 400004, 400005, 400006));

function ShowReflow(const S: string): Boolean;
begin
  Writeln(Format('%s %d',
    [S, Length(S)]));

  Result:= ((Length(S) > 10) and (Pos('alpha', S) > 0)) or ((Length(S) > 20) and (Pos('beta', S) > 0)) or ((Length(S) > 30) and (Pos('gamma', S) > 0)) or (S = 'delta') or (S = 'epsilon');
end;

// == Option: MaxLen ==
// A statement of about 165 columns: it fits the default 180; set the max line
// length to 150 and it is wrapped.

procedure ShowMaxLen(const S: string);
begin
  Writeln(Format('%s has %d characters, %d of them before the first "a", %d before the first "b" and %d before "c"', [S, Length(S), Pos('a', S), Pos('b', S), Pos('c', S)]));
end;

// == Option: Indent ==
// The indentation step: every nesting level adds this many spaces (it changes
// every indented line, not only this block).

procedure ShowIndent(var K: Integer);
begin
  repeat
    Dec(K);
  until K <= 0;
end;

// == Option: TabWidth ==
// Width of a tab in the input. The "//." comment below keeps its authored
// indentation, which starts with a tab.

procedure ShowTabWidth(var K: Integer);
begin
	//. pinned comment, indented with one tab
  Inc(K);
end;

// == Option: TrimTrailing ==
// The comment line below ends with three blanks: removed when ON (default).

procedure ShowTrimTrailing(var K: Integer);
begin
  // three blanks follow   
  Inc(K);
end;

// == Option: MaxBlankLines ==
// Two blank lines between the statements: one survives with the default 1.

procedure ShowMaxBlankLines(var K: Integer);
begin
  Inc(K);


  Dec(K);
end;

// == Option: BlanksBeforeMethod ==
// Blank lines forced before each routine; 1 puts one above the header below.
procedure ShowBlanksBeforeMethod(var K: Integer);
begin
  Inc(K);
end;

// == Option: LowercaseKeywords ==
// ON (default): REPEAT / UNTIL become repeat / until. OFF: keyword case kept.

procedure ShowLowercaseKeywords(var K: Integer);
begin
  REPEAT
    Dec(K);
  UNTIL K <= 0;
end;

// == Option: UpperHexNumbers ==
// ON (default): $ff becomes $FF. OFF: kept as written.

procedure ShowUpperHexNumbers(var K: Integer);
begin
  K:= $ff;
end;

// == Option: UpperDirectives ==
// ON (default): {$ifdef} becomes {$IFDEF}. OFF: kept as written.

procedure ShowUpperDirectives(var K: Integer);
begin
  {$ifdef DEBUG}
  Inc(K);
  {$endif}
end;

// == Option: FirstOccCasing ==
// ON (default): later uses of an identifier take the casing of its first
// occurrence (mixedvalue becomes MixedValue). OFF: kept as written.

procedure ShowFirstOccCasing;
var
  MixedValue: Integer;
begin
  mixedvalue:= 1;

  Writeln(MIXEDVALUE);
end;

// == Option: AssignNoSpaceBefore ==
// ON (default): "K := 1" becomes "K:= 1". OFF: kept as written.

procedure ShowAssignNoSpaceBefore(var K: Integer);
begin
  K := 1;
end;

// == Option: AssignSpaceAfter ==
// ON (default): "K:=1" becomes "K:= 1". OFF: kept as written.

procedure ShowAssignSpaceAfter(var K: Integer);
begin
  K:=1;
end;

// == Option: SpaceAroundOperators ==
// ON (default): one blank around binary operators ("K*2+1" becomes
// "K * 2 + 1"). OFF: kept as written.

procedure ShowSpaceAroundOperators(var K: Integer);
begin
  K:= K*2+1;
end;

// == Option: AlignSmartAssign ==
// Master switch of the shape-aware alignment. ON (default): a run of := lines
// lines up (and so do the shape blocks below). OFF: plain "Name:= Value".

procedure ShowAlignSmartAssign(var R: TRect);
begin
  R.Left:= 1; // x
  R.Top:= 20; // y
end;

// == Option: AlignCommentMaxShift ==
// How far a trailing comment may move to line up with its neighbours (default
// 7). These comments need 9 columns, so they line up only with a larger value.

procedure ShowAlignCommentMaxShift(var R: TRect);
begin
  R.Left := 1; // a
  R.Top  := 2000; // b
  R.Right:= 2000000000; // c
end;

// == Option: AlignMatchingShapes + AlignShapeMinAnchors ==
// AlignMatchingShapes ON (default): adjacent lines of the same shape line up
// column by column.
// AlignShapeMinAnchors: a shape needs at least this many anchors (default 3).
// The second pair has five ( , , ) ; and lines up; set 6 and it does not.

procedure ShowAlignMatchingShapes;
begin
  Writeln(Format('%d', [1]), 'a', 22); // one
  Writeln(Format('%d', [333]), 'bb', 4); // two
end;

procedure ShowAlignShapeMinAnchors(var K: Integer);
begin
  Writeln(K, 'a', 22); // one
  Writeln(K, 'bbbbbb', 4); // two
end;

// == Option: AlignMaxColumn ==
// Alignment never pushes past this column (default 140). The := below line up
// at column 59; set 50 and this pair is left unaligned.

procedure ShowAlignMaxColumn(var AParameterWithALongNameToPushTheColumnOut: TRect);
begin
  AParameterWithALongNameToPushTheColumnOut.Left:= 1; // x
  AParameterWithALongNameToPushTheColumnOut.Bottom:= 2; // y
end;

// == Option: AlignConstEquals ==
// ON (default): the = of a const block lines up. OFF: "Name = Value".
const
  CA = 1;
  CBbb = 22;

  // == Option: AlignTypeColon ==
  // ON (default): the : of consecutive declarations lines up. OFF: "Name: Type".

type
  TColonDemo = record
    Id: Integer;
    Count: Integer;
  end;

  // == Option: AlignDeclSemicolons ==
  // ON (default): the trailing ; of consecutive declarations lines up.

type
  TSemiDemo = record
    Alpha: Integer;
    Gamma: string;
  end;

  // == Option: SplitMultiVarDecls ==
  // ON (default): "X, Y: Integer" becomes one declaration per name. OFF: kept.

type
  TSplitDemo = record
    X, Y: Integer;
  end;

  // == Option: JoinRoutineHeaders + BreakParamsOnePerLine ==
  // JoinRoutineHeaders ON (default): a header split by hand is joined; OFF: one
  // parameter per line (implies BreakParamsOnePerLine).
  // BreakParamsOnePerLine ON: every header with 2+ parameters, one per line.

procedure ShowJoinHeader(
  const AName: string;
  ACount: Integer);
begin
  Writeln(AName, ACount);
end;

procedure ShowBreakParams(const AName: string; ACount: Integer);
begin
  Writeln(AName, ACount);
end;

// == Option: Delphi10Compat ==
// ON: inline var declarations move to a var block (builds on Delphi 10.2.3).

procedure ShowDelphi10Compat;
begin
  var Total:= 1;
  Writeln(Total);
end;

// == Option: BreakIfBody ==
// ON (default): then / else bodies on their own lines. OFF: the whole if on
// one line when it fits.

procedure ShowBreakIfBody(var K: Integer);
begin
  if K > 0 then Inc(K) else Dec(K);
end;

// == Option: BreakLoopBody ==
// ON (default): a for / while body on its own line. OFF: joined onto the do
// line when it fits.

procedure ShowBreakLoopBody(var K: Integer);
begin
  while K > 0 do Dec(K);
end;

// == Option: BreakWithBody ==
// ON (default): a with body on its own line. OFF: joined when it fits.

procedure ShowBreakWithBody(var R: TRect);
begin
  with R do Left:= 1;
end;

// == Option: BeginOnHeaderLine + CollapseShortBlocks ==
// BeginOnHeaderLine OFF (default): begin on its own line, "end" / "else" /
// "begin" on three lines; ON: begin joins its then / do / else.
// CollapseShortBlocks ON: a short begin..end folds onto one line (the //
// comments in the first routine keep its blocks from folding).

procedure ShowBeginOnHeaderLine(var K: Integer);
begin
  if K > 0 then begin
    Inc(K); // up
    Inc(K);
  end else begin
    Dec(K); // down
    Dec(K);
  end;
end;

procedure ShowCollapseShortBlocks(var K: Integer);
begin
  while K > 5 do
  begin
    Dec(K);
  end;
end;

// == Option: PackStatements ==
// OFF (default): one statement per line. ON: adjacent plain statements share
// a line while it fits.

procedure ShowPackStatements(var K: Integer);
begin
  K:= 1; Inc(K);
end;

// == Option: CaseArmOnLabelLine + BreakCaseLabels ==
// CaseArmOnLabelLine ON (default): a one-statement arm sits on its label line;
// OFF: the statement goes under the label.
// BreakCaseLabels OFF (default): "1, 2: X;" stays one arm; ON: one label per
// line, the statement repeated.

procedure ShowCaseArms(var K: Integer);
begin
  case K of
    1, 2:
      Inc(K);
    3, 4: Dec(K);
  else
    K:= 0;
  end;
end;

// == Option: IndentComments ==
// ON (default): a comment line takes the indentation of the code around it.

procedure ShowIndentComments(var K: Integer);
begin
// re-indented when ON
  Inc(K);
end;

// == Option: LabelLongBlocks + LabelMinLines ==
// LabelLongBlocks ON (default): a block of LabelMinLines (15) lines or more
// gets "// procedure" after its end.

procedure ShowLabelLongBlocks(var K: Integer);
begin
  Inc(K); // 1
  Inc(K); // 2
  Inc(K); // 3
  Inc(K); // 4
  Inc(K); // 5
  Inc(K); // 6
  Inc(K); // 7
  Inc(K); // 8
  Inc(K); // 9
  Inc(K); // 10
  Inc(K); // 11
  Inc(K); // 12
  Inc(K); // 13
  Inc(K); // 14
end;

end.
