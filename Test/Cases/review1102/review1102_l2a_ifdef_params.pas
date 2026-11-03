unit review1102_l2a_ifdef_params;
// REVIEW-2026-11-02 corruption L2a: a parameter list whose ")" sits on a line
// holding a {$IFDEF} left the statement splitter inside brackets for the rest
// of the file -- pass 1 split nothing after it, pass 2 did.
interface
type
  TC = class
    procedure M2(A: Integer;
      {$IFDEF FOO} B: string {$ELSE} B: Integer {$ENDIF});
  end;
procedure M1;
implementation
procedure TC.M2(A: Integer; {$IFDEF FOO} B: string {$ELSE} B: Integer {$ENDIF}); begin Writeln(A, B); end;
procedure M1;
begin Writeln(1); Writeln(2); end;
end.