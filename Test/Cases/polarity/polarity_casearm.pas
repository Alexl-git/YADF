unit polarity_casearm;

// CaseArmOnLabelLine polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\case-arm-on-label-line.md. CaA..CaD = case arms with
// simple one-statement bodies; CaE = else arm; DecKind = record variant.

interface

type
  TKind = (kA, kB, kC);

procedure RunCaseArm(N: Integer);

implementation

procedure RunCaseArm(N: Integer);
var
  CaA: Integer;
  CaB: Integer;
  CaC: Integer;
  CaD: Integer;
begin
  CaA:= 0;
  CaB:= 0;
  CaC:= 0;
  CaD:= 0;
  case N of
    0:
      Inc(CaA);
    1: Inc(CaB);
    2: begin
         CaC:= 1;
         CaC:= CaC + 1;
       end;
    3: Inc(CaD); // keep
  else
    CaA:= 1;
  end;
  case TKind(N) of
    kA:
      (IntVal: Integer);
    kB: (StrVal: string);
  end;
end;

end.