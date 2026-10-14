unit asm_blocks;

// Regression fixture (review 2026-10-14): BASM bodies must survive
// formatting verbatim -- one instruction per line, mnemonic case, operand
// spacing, labels and data directives untouched. With ReflowLines on, YADF
// used to join instruction lines, re-case `add` to `Add` (first-occurrence
// casing of the function name) and space `[esp+4]`; the output failed to
// compile (E2109) and the guard did not notice.

interface

function Add(A, B: Integer): Integer;
procedure Twice;
function AfterAsm: Integer;

implementation

function Add(A, B: Integer): Integer;
asm
  mov eax, A
  add eax, B
  and eax, $FFFF
  jmp @@End
@@loop:
  cmp eax, -1
  je @@loop
@@End:
  mov eax, -1
end;

procedure Twice;
asm
  mov eax, 1  // trailing comment stays on its instruction
  mov ecx, 2
  add eax, ecx
end;

function AfterAsm: Integer;
begin
  Result:= 1;
end;

end.
