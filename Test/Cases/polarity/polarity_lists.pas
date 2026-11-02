unit polarity_lists;

// Q6 + bracketed-list polarity fixture (test_option_polarity.ps1, SPEC-2026-11-01
// task 2d-4a). Spec: docs\help-site\options\break-long-expressions.md.
// OpJoin: operator-leading hand breaks in statements that fit MaxLen (joined
// under BreakLongExpressions ON). Pts: a short typed-constant array written
// comma-first (joins: it fits). Recs / Grid / the Total call: bracketed lists
// longer than MaxLen (180) -> comma-first, one whole top-level branch per line.

interface

type
  TPt = record
    X: Integer;
    Y: Integer;
  end;

const
  Pts: array[0..2] of TPt = (
    (X: 1; Y: 2)
  , (X: 3; Y: 4)
  , (X: 5; Y: 6)
  );
  Recs: array[0..9] of TPt = ((X: 1000001; Y: 2000002), (X: 3000003; Y: 4000004), (X: 5000005; Y: 6000006), (X: 7000007; Y: 8000008), (X: 9000009; Y: 1000010), (X: 1100011; Y: 1200012), (X: 1300013; Y: 1400014), (X: 1500015; Y: 1600016), (X: 1700017; Y: 1800018), (X: 1900019; Y: 2000020));
  Grid: array[0..1, 0..23] of Integer = ((100001, 100002, 100003, 100004, 100005, 100006, 100007, 100008, 100009, 100010, 100011, 100012, 100013, 100014, 100015, 100016, 100017, 100018, 100019, 100020, 100021, 100022, 100023, 100024), (200001, 200002, 200003, 200004, 200005, 200006, 200007, 200008, 200009, 200010, 200011, 200012, 200013, 200014, 200015, 200016, 200017, 200018, 200019, 200020, 200021, 200022, 200023, 200024));

function OpJoin(I: Integer): Integer;
function Sum8(A, B, C, D, E, F, G, H: Integer): Integer;
function Total: Integer;

implementation

function OpJoin(I: Integer): Integer;
var
  J: Integer;
begin
  J:= I
    + 1;
  Result:= J;
  if (I > 0)
  and (J > 0) then
    Result:= 0;
end;

function Sum8(A, B, C, D, E, F, G, H: Integer): Integer;
begin
  Result:= A + B + C + D + E + F + G + H;
end;

function Total: Integer;
begin
  Result:= Sum8(Recs[0].X + Recs[1].X + Recs[2].X, Recs[3].X + Recs[4].X + Recs[5].X, Recs[6].X + Recs[7].X, Recs[8].X + Recs[9].X, Pts[0].X + Pts[1].X, Pts[2].Y + Pts[1].Y, Grid[0, 0], Grid[1, 23]);
end;

end.