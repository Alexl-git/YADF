unit asm_same_line;

interface

function SameLineAsm(A, B: Integer): Integer;

implementation

function SameLineAsm(A, B: Integer): Integer;
asm mov eax,[rcx+8]
  lea eax,[rcx+rdx]
  add eax,1
end;

end.
