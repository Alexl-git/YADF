unit review_r3_if_comment;

interface

type
  TFoo = class
  private
    FVar: Integer;
    FVar2: string;
    procedure Bar;
  end;

function Foo(I: Integer): Boolean;

implementation

function Foo(I: Integer): Boolean;
begin
  Result := I > 0;
end;

procedure TFoo.Bar;
var
  A, B: Boolean;
begin
  A := True;
  B := False;
  if Foo(1) and // c
    (A) and // c
    (B) then
    FVar := 1;
end;

end.
