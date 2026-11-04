unit idem_anon_method_begin;

// Owner rule (2026-11-03): a multi-line anonymous method's `begin` / `end` sit at
// the level of its header line (the line holding `procedure` / `function`), its
// statements one level in -- assigned, wrapped onto its own line, or passed as a
// call argument (alone, after another argument, under an if).

interface

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Defaults, System.Generics.Collections;

procedure Run(const AProc: TProc);
begin
  AProc;
end;

procedure RunWith(ATag: Integer; const AProc: TProc);
begin
  if ATag = 0 then
    AProc;
end;

procedure Shapes;
var
  P: TProc;
  L: TList<Integer>;
begin
  P := procedure
  begin
    Writeln('a very long string literal number zero that pads the line out a lot');
    Writeln('a very long string literal number zero that pads the line out a lot');
  end;
  P :=
    procedure
    begin
      Writeln('a very long string literal number zero that pads the line out a lot');
      Writeln('a very long string literal number zero that pads the line out a lot');
    end;
  Run(procedure
      begin
        Writeln('a very long string literal number one that pads the line out a lot');
        Writeln('a very long string literal number two that pads the line out a lot');
      end);
  Run(
    procedure
    begin
      Writeln('a very long string literal number three that pads the line out a lot');
      Writeln('a very long string literal number four that pads the line out a lot');
    end);
  L := TList<Integer>.Create(TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      if A > B then Result := 1 else if A < B then Result := -1 else Result := 0;
      Writeln('a very long string literal number five that pads the line out a lot');
    end));
  L.Free;
  RunWith(0,
    procedure
    begin
      Writeln('a very long string literal number six that pads the line out a lot');
      Writeln('a very long string literal number seven that pads the line out a lot');
    end);
  if Assigned(P) then
    Run(procedure
      begin
        Writeln('a very long string literal number eight that pads the line out a lot');
        Writeln('a very long string literal number nine that pads the line out a lot');
      end);
  Writeln('after');
end;

end.