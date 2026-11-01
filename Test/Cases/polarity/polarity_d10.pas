unit polarity_d10;

// Delphi10Compat polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\delphi10-compat.md. DcA = an explicitly typed inline
// var; DcB = an ordinary var-block declaration.

interface

function RunD10: Integer;

implementation

function RunD10: Integer;
var
  DcB: Integer;
begin
  DcB:= 2;
  var DcA: Integer:= 3;
  Result:= DcA + DcB;
end;

end.
