unit inline_var_multi;

interface

implementation

// An inline multi-name var STATEMENT must stay one line (each split line would
// otherwise need its own `var` -- dropping it breaks compilation). Regression
// for the Micronite uFOLDERS_CLIENT corruption, 2026-06-14.
procedure Demo;
begin
  var Payload, RspPayload: TBytes;
  var GLE: DWORD;
  RspPayload := Payload;
  GLE := 0;
end;

end.
