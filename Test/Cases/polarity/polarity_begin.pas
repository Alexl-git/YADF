unit polarity_begin;

// BeginOnHeaderLine polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\begin-on-header-line.md. BgA = "then begin" on the
// header line; BgB = begin on its own line under "then"; BgC = "end else begin";
// BgD = end / else / begin on three lines; BgE = "do begin"; BgF = do / begin;
// BgG = a // comment after begin; BgH = a // comment after then (pins the line).
// The case holds "9: begin" (on the label line), "11:" / begin, a one-line
// block arm 10 (Collapse owns it, Q5) and a case else begin..end part.

interface

procedure RunBegin(C: Boolean; N: Integer);

implementation

procedure RunBegin(C: Boolean; N: Integer);
var
  BgA: Integer;
  BgB: Integer;
  BgC: Integer;
  BgD: Integer;
  BgE: Integer;
  BgF: Integer;
  BgG: Integer;
  BgH: Integer;
begin
  BgA:= 0;
  BgE:= 3;
  if C then begin
    BgA:= 1;
    BgB:= 2;
  end;
  if not C then
  begin
    BgB:= 1;
    BgC:= 2;
  end;
  if BgA > 0 then begin
    BgC:= 1;
    BgD:= 2;
  end else begin
    BgC:= 3;
    BgD:= 4;
  end;
  if BgB > 0 then begin
    BgD:= 1;
    BgC:= 2;
  end
  else
  begin
    BgD:= 3;
    BgC:= 4;
  end;
  while BgE > 0 do begin
    Dec(BgE);
    BgF:= BgE;
  end;
  for BgF:= 0 to N do
  begin
    BgE:= BgF;
    Inc(BgE);
  end;
  if C then begin // note G
    BgG:= 1;
    BgH:= 2;
  end;
  if not C then // note H
  begin
    BgH:= 1;
    BgG:= 2;
  end;
  case N of
    9: begin
      BgA:= 9;
      BgB:= 9;
    end;
    10: begin BgA:= 10; BgB:= 10; end;
    11:
      begin
        BgA:= 11;
        BgB:= 11;
      end;
  else begin
    BgA:= 0;
    BgB:= 0;
  end;
  end;
end;

end.