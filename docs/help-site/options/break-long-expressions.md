---
id: break-long-expressions
title: Long expressions: one part per line
summary: A statement over the max length gets one component per line, the operator or comma leading; a long bracketed list becomes a tree, one whole branch per line. Off = greedy packing, comma-last.
group: expressions
order: 20
default: "true"
ini: BreakLongExpressions
cli: --break-expr
since: "1.0.0.0"
status: "stable"
---

# Long expressions: one part per line

ON (default): when a line exceeds MaxLen, break it at every top-level operator -- one component per line, with the connecting operator LEADING each line ("and X" / "or Y"). A parenthesised group is one component and stays whole; a component that still does not fit is broken the same way, one indent step deeper. A trailing "then" or "do" moves to its own line at the column of the "if" / "while" that introduced it. A line that already fits is never broken. A statement written across lines with an operator (or a lone then / do) leading a line is joined when the WHOLE statement fits MaxLen; those breaks are kept only when it does not fit. A bracketed list that does not fit (a typed-constant array, an argument list) is laid out comma-first: the "(" ends the header line, one whole top-level item per line with the "," leading, the closing ")" on its own line; an item that still does not fit is broken the same way one level down, so an array of records breaks between records, never inside one that fits. A list that fits is joined onto one line. OFF reverts to the greedy breaker: as many components per line as fit, and a long bracketed list packed comma-last (`(1, 2, 3,` / `4, 5)`); the comma-first tree layout is used only while this option is on.

Applies only while [Reflow lines (join and wrap)](reflow-lines.md) is on: with that off, long lines are left as they are.

## Example

Real YADF output for the "ReflowLines + BreakLongExpressions" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
const
  BigTable: array[0..3] of array[0..5] of Integer = ((100001, 100002, 100003, 100004, 100005, 100006), (200001, 200002, 200003, 200004, 200005, 200006), (300001, 300002, 300003, 300004, 300005, 300006), (400001, 400002, 400003, 400004, 400005, 400006));

function ShowReflow(const S: string): Boolean;
begin
  Writeln(Format('%s %d',
    [S, Length(S)]));

  Result:= ((Length(S) > 10) and (Pos('alpha', S) > 0)) or ((Length(S) > 20) and (Pos('beta', S) > 0)) or ((Length(S) > 30) and (Pos('gamma', S) > 0)) or (S = 'delta') or (S = 'epsilon');
end;

// BreakLongExpressions = true (default)
const
  BigTable: array[0..3] of array[0..5] of Integer = (
    (100001, 100002, 100003, 100004, 100005, 100006)
  , (200001, 200002, 200003, 200004, 200005, 200006)
  , (300001, 300002, 300003, 300004, 300005, 300006)
  , (400001, 400002, 400003, 400004, 400005, 400006)
  );

function ShowReflow(const S: string): Boolean;
begin
  Writeln(Format('%s %d', [S, Length(S)]));

  Result:= ((Length(S) > 10) and (Pos('alpha', S) > 0))
    or ((Length(S) > 20) and (Pos('beta', S) > 0))
    or ((Length(S) > 30) and (Pos('gamma', S) > 0))
    or (S = 'delta')
    or (S = 'epsilon');
end;

// BreakLongExpressions = false
const
  BigTable: array[0..3] of array[0..5] of Integer = (
    (100001, 100002, 100003, 100004, 100005, 100006), (200001, 200002, 200003, 200004, 200005, 200006), (300001, 300002, 300003, 300004, 300005, 300006),
    (400001, 400002, 400003, 400004, 400005, 400006));

function ShowReflow(const S: string): Boolean;
begin
  Writeln(Format('%s %d', [S, Length(S)]));

  Result:= ((Length(S) > 10) and (Pos('alpha', S) > 0)) or ((Length(S) > 20) and (Pos('beta', S) > 0)) or ((Length(S) > 30) and (Pos('gamma', S) > 0)) or (S = 'delta')
    or (S = 'epsilon');
end;
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
