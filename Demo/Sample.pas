unit Sample;

// ============================================================================
// YADF live-preview sample (auto-loaded by YADFSetup).
//
// The panel on the LEFT is this raw source; the panel on the RIGHT is YADF's
// formatted output. Each block below is labelled with the option(s) it shows
// off -- toggle that option in the settings list and watch this block change
// on the right. (This file is parsed, not compiled; some bodies are illustrative.)
// ============================================================================

interface

{$I jedi.inc}
{$I extra.inc}

// --- UsesAlwaysBreak / UsesCommaLast ----------------------------------------
// UsesAlwaysBreak true (default): one unit per line; false: single line if it fits.
// UsesCommaLast   false (default): comma-FIRST (', Unit', ';' on its own line);
//                 true: comma-LAST ('Unit,' ... 'LastUnit;').
uses
System.SysUtils, System.Classes, System.Generics.Collections;

type
// --- enum with trailing // comments (regression shape: must not be merged) --
TKind = (
knNone=0, // nothing
knLow=1, // low
knHigh=2 // high
);

// --- AlignTypeColon + AlignDeclSemicolons -----------------------------------
// Both true (default): the ':' and the trailing ';' line up into columns.
// Both false         : plain declarations -- "Name: Type;", one space, no
//                      padding. (Set AlignMatchingShapes=false too for wide
//                      multi-anchor tables.)
TConn = record
lPLUID: TGUID;
lProv: boolean;
Name: string;
Handle: THandle;
end;

// --- SplitMultiVarDecls -----------------------------------------------------
// true (default): "X, Y: Integer" becomes one declaration per line.
TPoint = record
X,Y: Integer; // combined decl -> split + colon-align
Name: string;
end;

// --- AlignMatchingShapes ----------------------------------------------------
// true (default): the repeated (X: _; Y: _; Name: _) records align column-wise.
const
Origin: array[0..2] of TPoint = ( (X: 0; Y: 0; Name: 'a'), (X: 10; Y: 20; Name: 'bb'), (X: 7; Y: 3; Name: 'ccc') );

// --- BlanksBeforeMethod (interface side) ------------------------------------
// The floor applies only to TOP-LEVEL routines (see implementation). It must
// NEVER insert blank lines between these in-class method declarations.
type
TThing = class
procedure Alpha;
procedure Beta;
function Sum(const A, B: Integer): Integer;
end;

procedure Demo;

implementation

{$R+}

// --- BlanksBeforeMethod (implementation side) -------------------------------
// With BlanksBeforeMethod=2 each of these top-level routines gets two blank
// lines before it; the in-class Alpha/Beta/Sum declarations above stay tight.
procedure TThing.Alpha;
begin
end;

procedure TThing.Beta;
begin
end;

function TThing.Sum(const A, B: Integer): Integer;
begin
Result:= A+B;
end;

// --- CollapseShortBlocks ('Collapse short begin..end') ----------------------
// ON: a short control begin..end body (header ends in then/do/else, body is
// simple one-statement-per-line code) folds onto one line ->
//   if K > 0 then begin A := 1; B := 2; end;
// --- BreakCaseLabels ('Break case labels') ----------------------------------
// ON: a multi-label case arm splits one label per line, the statement
// duplicated to each -> "1, 2, 3: A := K;" becomes "1: A := K;" "2: A := K;" ...
procedure OptionShowcase(K: Integer);
var
A, B: Integer;
begin
if K > 0 then
begin
A := 1;
B := 2;
end;
case K of
1, 2, 3: A := K;
4, 5: B := K;
else
A := 0;
end;
Writeln(A, B);
end;

// --- BreakParamsOnePerLine ('Break parameters one per line') ---------------
// ON: a named routine declaration with 2+ parameters gets one parameter per
// line, and a grouped 'const ASrc, ADest: string' splits into one name per
// line with the modifier repeated. Separator placement follows UsesCommaLast.
procedure ShowcaseParams(const ASrc, ADest: string; AFlags: Integer; out AErr: string);
begin
end;

// --- BreakLoopBody / BreakWithBody / BreakIfBody ----------------------------
// Three independent options, all OFF by default -- so with stock settings the
// one-line control statements below stay exactly as they are. Turn one on and
// that construct's body drops onto its own indented line:
//   BreakLoopBody ('Break loop body') -> 'for ... do' and 'while ... do'
//   BreakWithBody ('Break with body') -> 'with ... do'
//   BreakIfBody   ('Break if body')   -> 'if ... then', and the 'else' arm
// They are the inverse of PackShortBodies; when both apply, the split wins.
// NOTE: labels are on their own lines here on purpose -- a trailing // comment
// disqualifies a line from being split, as the last case below demonstrates.
procedure BreakBodiesShowcase(K: Integer);
var
P: TPoint;
Sum, I: Integer;
begin
Sum:= 0;
P:= Origin[0];
// BreakLoopBody -- header ends in 'do'
for I:= 0 to High(Origin) do Sum:= Sum+Origin[I].X;
while (K > 0) and (Sum < 100) do Dec(K);
// BreakWithBody -- 'with' is deliberately separate from the loops
with P do X:= 1;
// BreakIfBody -- 'then' alone, then 'then' + 'else'
if K > 0 then Sum:= K;
if K > 0 then Sum:= K else Sum:= 0;
// 'else if' chains stay glued: 'else if K = 2 then' remains one line
if K = 1 then Sum:= 10 else if K = 2 then Sum:= 20 else Sum:= 30;
// Never split by these options, whatever is enabled:
// a 'begin' body is left alone (the indent engine still formats it),
while K > 0 do begin Dec(K); Inc(Sum); end;
// a nested control header is left alone (no ambiguous half-splits),
while K > 0 do while Sum > 0 do Dec(Sum);
// and a line carrying a trailing line comment is left alone.
if K > 0 then Sum:= 1; // this comment blocks the split
Writeln(Sum, P.Name);
end;

procedure Demo;
var
I,J: Integer; // combined -> split
begin
const Factor=2; // inline const
var Sum:=0.0; // inline var + type inference
for var K:=0 to High(Origin) do Sum:= Sum+Origin[K].X;
var Items: TList<Integer>:= TList<Integer>.Create; // inline var + generic
try
for I:= 0 to 9 do if I <= 4 then Items.Add(I*Factor); // <= must stay intact
Items.Sort(
function(const A, B: Integer): Integer // inline anon method
begin
Result:=A-B;
end);
if TObject(Items) is not TStringList then Exit; // is not operator
J:= if Items.Count >= 5 then 100 else 0; // if-ternary expression
Writeln(J, Sum);
finally
Items.Free;
end;
end;

end.
