unit review_r2_declines;

// Regression fixture (review 2026-10-14, reviewer 2): two passes moved CODE
// into a trailing `//` comment. The content guard caught both and declined
// the WHOLE file, so a valid unit could not be formatted at all.
//  * a directive-only line (`overload;`) after a header ending in `// c`
//    was appended to the comment;
//  * `then` / `do` at the end of a long line's trailing comment was taken
//    for a code keyword and cut out of the comment.

interface

type
  TFoo = class
    procedure Foo(A: string); // second
      overload;
    procedure Foo(A: Integer); overload;
  end;

var
  X, Alpha, Bravo, Charlie, Delta, Echo, Foxtrot: Int64;

implementation

procedure TFoo.Foo(A: string);
begin
end;

procedure TFoo.Foo(A: Integer);
begin
  X:= Alpha + Bravo + Charlie + Delta + Echo + Foxtrot + Alpha + Bravo + Charlie + Delta + Echo; // see what we do
end;

end.
