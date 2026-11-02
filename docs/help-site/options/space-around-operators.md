---
id: space-around-operators
title: Space around operators
summary: One space around binary operators (A+B -> A + B). Unary signs and generic brackets are left alone. Off = kept as written.
group: spacing
order: 30
default: "true"
ini: SpaceAroundOperators
since: "1.0.0.0"
status: "stable"
---

# Space around operators

On (default): one space around binary operators (`K*2+1` becomes `K * 2 + 1`): + - * / = < > <= >= <> and the word operators. Unary +/- and generic brackets (`TList<Integer>`) are left intact.

Off: kept as written -- YADF neither adds nor removes spaces around operators. (Runs of several blanks inside code still become one: see [Rules (always on)](rules-always-on.md).)

## Example

Real YADF output for the "SpaceAroundOperators" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowSpaceAroundOperators(var K: Integer);
begin
  K:= K*2+1;
end;

// SpaceAroundOperators = true (default)
procedure ShowSpaceAroundOperators(var K: Integer);
begin
  K:= K * 2 + 1;
end;

// SpaceAroundOperators = false
procedure ShowSpaceAroundOperators(var K: Integer);
begin
  K:= K*2+1;
end;
```
