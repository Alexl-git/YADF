---
id: delphi10-compat
title: Hoist inline vars (Delphi 10.2.3)
summary: Hoist inline var declarations into a var block so the code builds on Delphi 10.2.3. Best-effort: every comment it adds (an inferred type to verify, a var it could not hoist) starts "// TODO -oYADF -cd10 :", and a run with this option off removes exactly those comments.
group: delphi-10-compatibility
order: 10
default: "false"
ini: Delphi10Compat
cli: --d10
since: "1.0.0.0"
status: "stable"
---

id: delphi10-compat
title: Hoist inline vars (Delphi 10.2.3)
summary: Hoist inline var declarations into a var block so the code builds on Delphi 10.2.3. Best-effort: every comment it adds (an inferred type to verify, a var it could not hoist) starts "// TODO -oYADF -cd10 :", and a run with this option off removes exactly those comments.
group: delphi-10-compatibility
order: 10
default: "false"
ini: Delphi10Compat
cli: --d10
since: "1.0.0.0"
status: "stable"
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

Hoist inline var declarations into a top-of-routine var block so the code builds on Delphi 10.2.3. Explicit types and simple literals are converted: an integer literal gets the type Delphi infers for it (Integer, Cardinal or Int64 by magnitude, decimal, hex or binary), a real literal (1.5, 1e3) Extended, a string literal string. Every comment the option adds starts with the marker "// TODO -oYADF -cd10 :" -- the "inferred type, verify" note on a hoisted declaration whose type was inferred, and the flag on an inline var left in place to resolve by hand. A run with Delphi10Compat = false removes exactly those marked comments (never another comment); the hoisted declarations stay. Best-effort, unverified on a real Tokyo toolchain.

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
  Total: Integer; // TODO -oYADF -cd10 : inferred type, verify for Delphi 10 -- was: var Total:= 1;
begin
  Total:= 1;
  Writeln(Total);
end;
```
