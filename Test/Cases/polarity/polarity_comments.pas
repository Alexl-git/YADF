unit polarity_comments;

// Comment rule polarity fixture (test_option_polarity.ps1, SPEC-2026-11-01 task 3).
// Only // line comments pin a line; a short one-line {...} / (*...*) comment
// travels with its neighbouring token through every join and split; a multi-line
// block comment pins; {$...} directives are not comments and never move across
// lines. Each construct is written once with a brace comment (must follow the
// option) and once with a // comment (must stay where it is).

interface

type
  TCmPt = record
    X: Integer;
    Y: Integer;
  end;

const
  CmRecs: array[0..9] of TCmPt = ((X: 1000001; Y: 2000002), {first} (X: 3000003; Y: 4000004), (X: 5000005; Y: 6000006), (X: 7000007; Y: 8000008), (X: 9000009; Y: 1000010), (X: 1100011; Y: 1200012), (X: 1300013; Y: 1400014), (X: 1500015; Y: 1600016), (X: 1700017; Y: 1800018), (X: 1900019; Y: 2000020));

function Sum2(A: Integer; B: Integer): Integer;
procedure CmHeadBrace(const CmA: string; { first }
  CmB: Integer);
procedure CmHeadSlash(const CmC: string; // first
  CmD: Integer);
procedure RunComments(N: Integer);

implementation

function Sum2(A: Integer; B: Integer): Integer;
begin
  Result:= A + B;
end;

procedure CmHeadBrace(const CmA: string; { first }
  CmB: Integer);
begin
end;

procedure CmHeadSlash(const CmC: string; // first
  CmD: Integer);
begin
end;

procedure RunComments(N: Integer);
var
  CmE: Integer;
  CmF: Integer;
  CmG: Integer;
  CmH: Integer;
  CmI: Integer;
  CmJ: Integer;
  CmK: Integer;
  CmL: Integer;
  CmM: Integer;
  CmN: Integer;
begin
  CmE:= Sum2(1, {one}
    2);
  CmF:= Sum2(1, // one
    2);
  CmG:= CmE {+ CmF}
    + N;
  CmH:= CmE // keep
    + N;
  CmG:= CmF { two
    lines }
    + N;

  if N > 0 then {why} Inc(CmI);
  if N > 1 then
    {short} Inc(CmI);
  if N > 2 then // why
    Inc(CmI);
  while CmI > 0 do (*loop*)
    Dec(CmI);

  case N of
    0: {zero}
      Inc(CmJ);
    1:
      {one} Inc(CmJ);
    2: // two
      Inc(CmJ);
    3: {three} Inc(CmJ);
    4, {four}
    5: Inc(CmJ);
    6, // six
    7: Inc(CmJ);
  end;

  if N > 3 then
  begin {blk}
    CmK:= 1;
    CmL:= 2;
  end;
  if N > 4 then
  begin
    CmK:= 3; (*mid*)
    CmL:= 4;
  end;
  if N > 5 then
  begin // blk
    CmK:= 5;
    CmL:= 6;
  end;
  if N > 6 then
  begin
    CmK:= 7; { two
    lines }
    CmL:= 8;
  end;
  if N > 7 then begin CmK:= 9; {nine} CmL:= 10; end;

  CmM:= 1; {a} CmN:= 2;

  CmM:= 3; (*b*)
  CmN:= 4;

  CmM:= 5; // c
  CmN:= 6;

  {$IFDEF DEBUG} CmM:= 7; {$ENDIF}

  CmM:= 8;
  {$IFDEF DEBUG}
  CmN:= 9;
  {$ENDIF}
end;

end.
