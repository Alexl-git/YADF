unit polarity_rules6;

// Task 6 (SPEC-2026-11-01 reflow round leftovers): fixed rules at the defaults.

interface

uses
  Types, SysUtils;

type
  TShape6 = record
    Name: string;
    case Kind: Integer of
      0: (Width, Height: Integer);
      1: (Radius: Double);
      22: (A: Byte; LongerName: Word);
  end;

  TAdv6 = record
    var
      Count: Integer;
    case Roomy: Boolean of
      True: (Big: Int64);
      False: (Small: Byte);
  end;

const
  Box1: TRect = (Left: 1; Top: 2; Right: 3; Bottom: 4);
  Box22: TRect = (Left: 10; Top: 20; Right: 300; Bottom: 400);

procedure Run6(K: Integer; C: Boolean);
procedure After6;

implementation

type
  TPart6 = record
    Beta: Integer;
    Th: Integer;
    Delta: Integer;
  end;

procedure Run6(K: Integer; C: Boolean);
var
  X: TProc;
  Alpha: TPart6;
  Gamma: TPart6;
  Eta: TPart6;
  D: Integer;
begin
  X := procedure begin After6; end;
  X := procedure
    begin
      After6;
    end;
  Alpha.Beta := 1;
  Gamma.Delta := 2;
  Eta.Th := 3;
  D := 0;   
  case K of
    3: {three} D := 1;
    4, {four} 5: D := 2;
  end;
  if C then
  begin
    D := 1;
  end else D := 3;
  if C then
  begin
    D := 1;
  end else if D > 2 then D := 6;
  case K of
    1: begin D := 1; end else D := 9;
  end;
  Writeln(Format('%d %d', [K, // keep
    D]));
  Writeln(D, Alpha.Beta, Gamma.Delta, Eta.Th);
  X;
end;

procedure After6;
begin
  Writeln('after');
end;

end.