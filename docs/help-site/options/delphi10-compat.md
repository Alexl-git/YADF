---
id: delphi10-compat
title: Hoist inline vars (Delphi 10.2.3)
summary: Hoist inline var declarations into a var block so the code builds on Delphi 10.2.3. Best-effort.
group: delphi-10-compatibility
order: 10
default: "false"
ini: Delphi10Compat
since: "1.0.0.0"
status: "stable"
---

# Hoist inline vars (Delphi 10.2.3)

Hoist inline var declarations into a top-of-routine var block so the code builds on Delphi 10.2.3. Explicit types and simple literals are converted; the rest stay in place with a "// TODO -oYADF -cd10 :" flag to resolve by hand. A run with Delphi10Compat = false removes exactly those flags (never another comment). Best-effort, unverified on a real Tokyo toolchain.

## Example

Real YADF output for the "Delphi10Compat" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowDelphi10Compat;
begin
  var Total:= 1;
  Writeln(Total);
end;

// Delphi10Compat = false (default)
procedure ShowDelphi10Compat;
begin
  var Total:= 1;
  Writeln(Total);
end;

// Delphi10Compat = true
procedure ShowDelphi10Compat;
var
  Total: Integer; // YADF Delphi10: inferred type, verify -- was: var Total:= 1;
begin
  Total:= 1;
  Writeln(Total);
end;
```
