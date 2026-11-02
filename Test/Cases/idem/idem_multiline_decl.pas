unit idem_multiline_decl;

// Task 10 mechanism C: a multi-name field declaration written across lines and
// too long to join was wrapped at a comma, and only its last line was split
// into one declaration per name; the next format split the rest.

interface

type
  TFieldSet = class
  private
    FfID, FfMasterID, FfNotation, FfSpecType, FfFtrType, FfUSL, FfLSL,
      FfDecimals, FfNominal, FfUpperTol, FfLowerTol, FfMathLine, FfDimAbbr,
      FfDimName, FfFtrSuffix, FfAttrName, FfAttrType, FfAttrCode, FfFtrName: TObject;
  public
    function Count: Integer;
  end;

implementation

function TFieldSet.Count: Integer;
begin
  Result:= 19;
end;

end.