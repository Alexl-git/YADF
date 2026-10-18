unit review_r3_field_method;

interface

type
  TFoo = class
  private
    FVar: Integer;
    FVar2: string;
    function GetSomething(AIndex: Integer): Boolean;
    procedure SetSomething(AIndex: Integer; AValue: Boolean);
  end;

implementation

function TFoo.GetSomething(AIndex: Integer): Boolean;
begin
  Result := AIndex > 0;
end;

procedure TFoo.SetSomething(AIndex: Integer; AValue: Boolean);
begin
  FVar := AIndex;
end;

end.
