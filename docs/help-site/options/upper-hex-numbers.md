---
id: upper-hex-numbers
title: Uppercase hex
summary: Uppercase hex digits and the exponent letter in numeric literals ($AB not $ab, 1E5 not 1e5).
group: casing
order: 20
default: "true"
ini: UpperHexNumbers
cli: --upper-hex
since: "1.0.0.0"
status: "stable"
---

# Uppercase hex

Uppercase hex digits in $NN literals and the exponent letter
in floats: $FF, 1E5.

## Example

Real YADF output for the "UpperHexNumbers" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowUpperHexNumbers(var K: Integer);
begin
  K:= $ff;
end;

// UpperHexNumbers = true (default)
procedure ShowUpperHexNumbers(var K: Integer);
begin
  K:= $FF;
end;

// UpperHexNumbers = false
procedure ShowUpperHexNumbers(var K: Integer);
begin
  K:= $ff;
end;
```

## Related

- [Lowercase keywords](lowercase-keywords.md) - Lowercase Pascal keywords (begin, end, if, then ...).
- [Uppercase directives](upper-directives.md) - Uppercase compiler-directive keywords ({$IFDEF}, {$R+} ...).
- [First-occurrence casing](first-occ-casing.md) - Cascade casing from the first occurrence of each identifier to all later uses.
