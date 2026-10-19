unit attr_multi_names;

interface

uses System.Rtti;

type
  MyAttr = class(TCustomAttribute)
  public
    constructor Create(const S: string = '');
  end;
  TFoo = class
  public
    [MyAttr] // both fields are tagged
    A, B: Integer;
    [MyAttr('a rather long attribute argument string that pushes the joined line well past the configured MaxLen of one hundred and eighty characters, so reflow cannot join it to the field list below')]
    C, D: Integer;
    [weak]
    FX, FY: IInterface;
  end;

implementation

constructor MyAttr.Create(const S: string);
begin
  inherited Create;
end;

end.