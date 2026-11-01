unit polarity_uses;

// UsesAlwaysBreak / UsesCommaLast polarity fixture (test_option_polarity.ps1).
// Specs: docs\help-site\options\uses-always-break.md, uses-comma-last.md.
// Interface uses = one line; implementation uses = broken, comma-LAST.

interface

uses SysUtils, Classes;

function PolarityUsesName: string;

implementation

uses
  Math,
  Types;

function PolarityUsesName: string;
var
  P: TPoint;
  L: TStringList;
begin
  P:= Point(1, 2);
  L:= TStringList.Create;
  try
    Result:= IntToStr(Max(P.X, L.Count));
  finally
    L.Free;
  end;
end;

end.
