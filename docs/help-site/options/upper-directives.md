---
id: upper-directives
title: Uppercase directives
summary: Uppercase compiler-directive keywords ({$IFDEF}, {$R+} ...).
group: casing
order: 30
default: "true"
ini: UpperDirectives
cli: --upper-directives
since: "1.0.0.0"
status: "stable"
---

# Uppercase directives

Uppercase compiler-directive names: {$IFDEF}, {$DEFINE}, ...

## Example

Real YADF output for the "UpperDirectives" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowUpperDirectives(var K: Integer);
begin
  {$ifdef DEBUG}
  Inc(K);
  {$endif}
end;

// UpperDirectives = true (default)
procedure ShowUpperDirectives(var K: Integer);
begin
  {$IFDEF DEBUG}
  Inc(K);
  {$ENDIF}
end;

// UpperDirectives = false
procedure ShowUpperDirectives(var K: Integer);
begin
  {$ifdef DEBUG}
  Inc(K);
  {$endif}
end;
```

## Related

- [Lowercase keywords](lowercase-keywords.md) - Lowercase Pascal keywords (begin, end, if, then ...).
- [Uppercase hex](upper-hex-numbers.md) - Uppercase hex digits in numeric literals ($AB not $ab).
- [First-occurrence casing](first-occ-casing.md) - Cascade casing from the first occurrence of each identifier to all later uses.
