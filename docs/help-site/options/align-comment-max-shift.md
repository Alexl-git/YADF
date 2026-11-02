---
id: align-comment-max-shift
title: Comment max shift
summary: Maximum columns a trailing comment may shift when aligning to a shape.
group: alignment
order: 80
default: "7"
ini: AlignCommentMaxShift
since: "1.0.0.0"
status: "stable"
---

# Comment max shift

In a shape-matched run where EVERY line carries a trailing `//`
comment, pull those comments to one shared column -- but only
when no line has to move more than this many spaces to get
there. Comments further apart than this are left where the
author put them (avoids tearing a ragged gap across the block).
The shared comment column is still bounded by AlignMaxColumn.
Set 0 to disable trailing-comment alignment entirely.

## Example

Real YADF output for the "AlignCommentMaxShift" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowAlignCommentMaxShift(var R: TRect);
begin
  R.Left := 1; // a
  R.Top  := 2000; // b
  R.Right:= 2000000000; // c
end;

// AlignCommentMaxShift = 7 (default)
procedure ShowAlignCommentMaxShift(var R: TRect);
begin
  R.Left := 1; // a
  R.Top  := 2000; // b
  R.Right:= 2000000000; // c
end;

// AlignCommentMaxShift = 30
procedure ShowAlignCommentMaxShift(var R: TRect);
begin
  R.Left := 1;          // a
  R.Top  := 2000;       // b
  R.Right:= 2000000000; // c
end;
```

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align = in const blocks](align-const-equals.md) - Vertical-align = in const blocks.
