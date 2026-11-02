unit polarity_casearm;

// CaseArmOnLabelLine polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\case-arm-on-label-line.md. CaA = an arm body under
// its label; CaB = an arm already on the label line; CaC = a begin..end arm;
// CaD = an arm with a trailing // comment; arm 4 holds a nested case, arm 5 an
// if..else, arm 6 a statement whose continuation line leads with an operator. Arm 7 = a longer statement (no ; padding, Q16).
// The case else part follows CaseArmOnLabelLine (Q11); the variant part of TCaRec must never move.

interface

type
  TCaRec = record
    case Kind: Integer of
      0: (IntVal: Integer);
      1: (DblVal: Double);
  end;

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
    2:
      begin
        CaC:= 1;
        CaC:= CaC + 1;
      end;
    3: Inc(CaD); // keep
    4:
      case CaB of
        0: Inc(CaB);
      else
        Dec(CaB);
      end;
    5: if CaA > 0 then Inc(CaA) else Dec(CaA);
    6: CaB:= CaA
         + CaC;
    7: Inc(CaA, CaB);
  else
    CaA:= 1;
  end;
end;

end.