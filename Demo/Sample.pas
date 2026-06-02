unit Sample;

interface

{$I jedi.inc}
{$I extra.inc}

uses
System.SysUtils, System.Classes, System.Generics.Collections;

type
// enum with trailing // comments (regression shape: must not be merged)
TKind = (
knNone=0, // nothing
knLow=1, // low
knHigh=2 // high
);

TPoint = record
X,Y: Integer  ; // combined decl -> split + colon-align
Name: string;
end;

const
Origin: array[0..2] of TPoint = ( (X: 0; Y: 0; Name: 'a'), (X: 10; Y: 20; Name: 'bb'), (X: 7; Y: 3; Name: 'ccc') );

procedure Demo;

implementation

{$R+}

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
A:=B+C;
end);
if TObject(Items) is not TStringList then Exit; // is not operator
J:=Items.Count >= 5?100:0; // if-ternary expression
Writeln(J, Sum);
finally
Items.Free;
end; 
end; 

end.
