---
id: align-type-colon
title: Align : in declarations
summary: Vertical-align : in type / var / parameter blocks.
group: alignment
order: 30
default: "true"
ini: AlignTypeColon
since: "1.0.0.0"
status: "stable"
---

# Align : in declarations

Align `:` in adjacent declaration lines (var/field/parameter).

## Example

Real YADF output for the "AlignTypeColon" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
type
  TColonDemo = record
    Id: Integer;
    Count: Integer;
  end;

// AlignTypeColon = true (default)
type
  TColonDemo = record
    Id   : Integer;
    Count: Integer;
  end;

// AlignTypeColon = false
type
  TColonDemo = record
    Id: Integer   ;
    Count: Integer;
  end;
```

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align = in const blocks](align-const-equals.md) - Vertical-align = in const blocks.
