unit break_expr_list_after_operator;

// BreakLongExpressions ON: an or-chain over MaxLen whose third component holds
// a call list that only overflows at the column it has BEFORE the chain is
// broken. The chain is broken one component per line and the list stays
// whole; the list used to be laid out comma-first at the pre-break column
// ((Pos( / 'gamma' / , S) and the next format rejoined it.

interface

function IsKnown(const S: string): Boolean;

implementation

uses
  System.SysUtils;

function IsKnown(const S: string): Boolean;
begin
  Result:= ((Length(S) > 10) and (Pos('alpha', S) > 0)) or ((Length(S) > 20) and (Pos('beta', S) > 0)) or ((Length(S) > 30) and (Pos('gamma', S) > 0)) or ((Length(S) > 40) and (Pos('gammadeltaepsilon', S) > 0)) or (S = 'delta') or (S = 'epsilon');
end;

end.