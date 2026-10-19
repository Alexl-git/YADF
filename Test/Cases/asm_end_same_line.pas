unit asm_end_same_line;

// Regression fixture (review 2026-10-19): the closing `end` of a BASM body
// shares the last instruction line (`ret end;`). The shield used to leave
// `asm //sentinel end;`, the `end` was swallowed by the line comment, the
// depth tracker never closed the block and every later routine plus the
// final `end.` was indented one level too deep.

interface

function A1: Integer;
function AfterAsmEnd: Integer;

implementation

function A1: Integer;
asm
  mov eax,1
  ret end;

function AfterAsmEnd: Integer;
begin
  Result:= 2;
end;

end.
