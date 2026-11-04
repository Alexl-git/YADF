unit idem_nojoin_long_header;

// JoinRoutineHeaders OFF (--no-join-headers) implies one parameter per line. A
// header that the source wrote on one long line was laid out one per line on
// the first format; the second format re-joined those lines into one line over
// MaxLen, greedy-wrapped it (WrapHeaderLine only skipped headers when
// BreakParamsOnePerLine was on), and BreakRoutineParams -- which needs the whole
// header on one line -- left the wrapped pair alone.

interface

function Compute(Other1: Integer; Other2: Integer; Other3: Integer; Other4: Integer; Other5: Integer; Other6: Integer; Other7: Integer; Other8: Integer; Other9: Integer; Other10: Integer; Other11: Integer; Other12: Integer; Other13: Integer; Other14: Integer): Integer;

implementation

function Compute(Other1: Integer; Other2: Integer; Other3: Integer; Other4: Integer; Other5: Integer; Other6: Integer; Other7: Integer; Other8: Integer; Other9: Integer; Other10: Integer; Other11: Integer; Other12: Integer; Other13: Integer; Other14: Integer): Integer;
begin
  Result:= Other1 + Other14;
end;

end.