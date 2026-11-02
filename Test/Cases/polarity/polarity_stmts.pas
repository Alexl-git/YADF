unit polarity_stmts;

// PackStatements + the fixed "block keywords start a line" rule + owner
// decision Q7 (test_option_polarity.ps1). Spec:
// docs\help-site\options\pack-statements.md. StA..StC are written packed on one
// line (OFF splits them), StD / StE one per line (ON packs them). OneLine is a
// one-line routine body; repeat / try / case are written on one line; TStRec /
// TStObj are a one-line record / class; GStA, GStB and RA, RB are two
// declarations on one line (Q7: always one per line). The if block is what
// CollapseShortBlocks may fold.

interface

type
  TStRec = record RA: Integer; RB: Integer; end;
  TStObj = class(TObject) private FX: Integer; public procedure P; end;

procedure RunStmts(N: Integer);
procedure OneLine;

implementation

var
  GStA: Integer; GStB: string;

procedure TStObj.P;
begin
  FX:= 1;
end;

procedure OneLine; begin GStA:= 1; GStB:= 'a'; end;

procedure RunStmts(N: Integer);
var
  StA: Integer;
  StB: Integer;
  StC: Integer;
  StD: Integer;
  StE: Integer;
begin
  StA:= 1; StB:= 2; StC:= 3;
  StD:= 4;
  StE:= 5;
  repeat Dec(StA); until StA <= 0;
  try StB:= N; finally StC:= 0; end;
  case N of 0: StD:= 1; 1: StD:= 2; end;
  if N > 0 then
  begin
    StE:= 6;
  end;
  GStA:= StA + StB + StC + StD + StE;
end;

end.