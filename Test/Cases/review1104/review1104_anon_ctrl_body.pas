unit review1104_anon_ctrl_body;
// REVIEW-2026-11-04-corruption L1: a one-line anonymous method as a controlled
// body was cut at its first `;` (BreakControlBodies took the `;` inside the
// anonymous method's begin..end as the end of the controlled statement), and an
// `else` body holding then/else of its own inside the anonymous method was not
// moved off the `else` line. The anonymous method's begin..end is skipped: each
// body goes on its own line whole.

interface

uses
  System.SysUtils;

procedure Go(Flag: Boolean; var P: TProc; var F: TFunc<Integer, Integer>);

implementation

procedure Go(Flag: Boolean; var P: TProc; var F: TFunc<Integer, Integer>);
var
  I: Integer;
begin
  if Flag then P := procedure begin Writeln('then'); end else P := procedure begin Writeln('else'); end;
  for I := 0 to 1 do P := procedure begin Writeln('for'); end;
  if Assigned(P) then P := nil else P := procedure begin Writeln('x'); end;
  if Flag then F := function(A: Integer): Integer begin Result := A * 10; end
  else F := function(A: Integer): Integer begin if A > 0 then Result := A else Result := -A; end;
  if Flag then P := procedure begin Writeln('a'); end; Writeln('sibling');
end;

end.