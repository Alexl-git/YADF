unit multi_decl_oneline;

interface

implementation

// A var line that packs TWO declarations ("A, B: T1; C: T2;") must not be
// split -- running the type to the last `;` and splitting the names would
// duplicate the tail ("Q: TFDQuery") onto every line and redeclare it.
// Regression for the Micronite uPipeSessionBuilder ClonePlan corruption,
// 2026-06-14.
procedure Demo;
var
  Cols, SelList: string; Q: TQuery;
begin
  Cols := '';
  SelList := '';
  Q := nil;
end;

end.
