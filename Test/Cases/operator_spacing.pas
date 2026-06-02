unit operator_spacing;

// Regression for SpaceAroundOperators (default true) and the anonymous-method
// argument indentation fix.
//   - Binary + - * / = <= >= <> get one surrounding space.
//   - Unary +/- stay attached (-5, := -X, (-A)).
//   - Generic brackets <, > are NEVER spaced (TList<Integer>).
//   - .. ranges, ^ pointers, @ address-of are left intact.
//   - An anonymous method passed as an argument indents under the call.

interface

uses System.Generics.Collections;

type
  TRange = 0..9;
  PInt = ^Integer;

procedure Demo;

implementation

procedure Demo;
var
  I: Integer;
  P: PInt;
  L: TList<Integer>;
begin
  I := 1 + 2 * 3 - 4 div 5;
  I := (I + 1) * (I - 1);
  I := -5;
  if I <= 3 then I := I + 1;
  if I >= 3 then I := I - 1;
  if I <> 0 then I := 0;
  L := TList<Integer>.Create;
  P := @I;
  I := P^ + 1;
  L.Sort(
    function(const A, B: Integer): Integer // inline anon method
    begin
      Result := A - B;
    end);
  L.Free;
end;

end.
