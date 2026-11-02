---
id: align-smart-assign
title: Align := runs (master switch for shapes)
summary: Master switch for shape-aware alignment of := runs and, with "Align lines of the same shape", other matching shapes.
group: alignment
order: 10
default: "true"
ini: AlignSmartAssign
since: "1.0.0.0"
status: "stable"
---

# Align := runs (master switch for shapes)

When adjacent assignment lines share the same token shape (same
sequence of operators/punctuation, identifier names may differ),
pad every common anchor (`:=`, `(`, `,`, `)`, `;`) to its
max column so they line up. A member `.` (`A.B`) must match but
is never padded.

## Example

Real YADF output for the "AlignSmartAssign" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowAlignSmartAssign(var R: TRect);
begin
  R.Left:= 1; // x
  R.Top:= 20; // y
end;

// AlignSmartAssign = true (default)
procedure ShowAlignSmartAssign(var R: TRect);
begin
  R.Left:= 1;  // x
  R.Top := 20; // y
end;

// AlignSmartAssign = false
procedure ShowAlignSmartAssign(var R: TRect);
begin
  R.Left:= 1; // x
  R.Top:= 20; // y
end;
```

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align = in const blocks](align-const-equals.md) - Vertical-align = in const blocks.
