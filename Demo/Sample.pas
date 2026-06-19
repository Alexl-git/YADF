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

// --- UsesAlwaysBreak --------------------------------------------------------
// true  (default): one unit per line, comma-first, ';' on its own line.
// false          : kept on a single line when it fits MaxLen (uses A, B, C;).
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
J:=Items.Count >= 5?100:0; // if-ternary expression
Writeln(J, Sum);
finally
Items.Free;
end;
end;

end.
