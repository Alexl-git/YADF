unit nested_indent;

interface

implementation

// then -> nested if -> begin/end: inner if, begin and end all one level
// under the outer if; the block body one level under that.
procedure A(X, Y: Boolean);
begin
  if X then
    if Y then
    begin
      DoA;
      DoB;
    end;
  AfterIt;
end;

// then -> comment -> nested if -> single statement (the reported case).
procedure B(X, Y: Boolean);
begin
  if X then
    // note explaining the inner test
    if Y then
      DoNested;
end;

// do -> nested if (loop body is a nested if).
procedure C(N: Integer);
begin
  for I := 0 to N do
    if Odd(I) then
      DoOdd(I);
end;

// case arm whose body is a nested if, and a begin arm.
procedure D(K: Integer; Flag: Boolean);
begin
  case K of
    1:
      if Flag then
        DoOne;
    2:
    begin
      DoTwo;
    end;
  end;
end;

// same-line else-if ladder must stay FLAT (no creeping indent).
procedure E(N: Integer);
begin
  if N = 1 then
    DoOne
  else if N = 2 then
    DoTwo
  else
    DoOther;
end;

end.
