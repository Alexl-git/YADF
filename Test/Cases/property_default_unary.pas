unit PropDefault;

interface

type
  TFoo = class
  private
    FX: Integer;
    function GetV(AIdx: Integer): Integer;
  public
    property X: Integer read FX write FX default -1;
    property V: Integer index -2 read GetV;
  end;

function IndexMinus(Index: Integer): Integer;

implementation

function TFoo.GetV(AIdx: Integer): Integer;
begin
  Result:= AIdx;
end;

function IndexMinus(Index: Integer): Integer;
begin
  Result:= Index - 1;
end;

end.