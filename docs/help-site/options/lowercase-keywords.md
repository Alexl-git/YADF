---
id: lowercase-keywords
title: Lowercase keywords
summary: Lowercase Pascal keywords (begin, end, if, then ...).
group: casing
order: 10
default: "true"
ini: LowercaseKeywords
cli: --lowercase-keywords
since: "1.0.0.0"
status: "stable"
---

# Lowercase keywords

Lowercase reserved keywords (begin, end, if, else, var, ...).

## Example

Real YADF output for the "LowercaseKeywords" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowLowercaseKeywords(var K: Integer);
begin
  REPEAT
    Dec(K);
  UNTIL K <= 0;
end;

// LowercaseKeywords = true (default)
procedure ShowLowercaseKeywords(var K: Integer);
begin
  repeat
    Dec(K);
  until K <= 0;
end;

// LowercaseKeywords = false
procedure ShowLowercaseKeywords(var K: Integer);
begin
  REPEAT
    Dec(K);
  UNTIL K <= 0;
end;
```

## Related

- [Uppercase hex](upper-hex-numbers.md) - Uppercase hex digits in numeric literals ($AB not $ab).
- [Uppercase directives](upper-directives.md) - Uppercase compiler-directive keywords ({$IFDEF}, {$R+} ...).
- [First-occurrence casing](first-occ-casing.md) - Cascade casing from the first occurrence of each identifier to all later uses.
