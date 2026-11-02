---
id: reflow-lines
title: Reflow lines (join and wrap)
summary: Join a statement broken by hand when it fits the max line length and wrap longer lines. Off = the author's line breaks are kept and long lines are left as-is.
group: expressions
order: 10
default: "true"
ini: ReflowLines
since: "1.0.0.0"
status: "stable"
---

# Reflow lines (join and wrap)

YADF treats each statement as one long string and breaks it according to the settings.

On (default): a line break the author put inside a statement is dropped when the statement fits the max line length (`Format('%s %d',` / `[S, Length(S)])` becomes one line), and a statement longer than the max length is wrapped -- how, is decided by [Long expressions: one part per line](break-long-expressions.md).

Off: the author's line breaks inside statements are kept and a line over the max length is left as it is; lines are still re-indented and aligned. Off preserves only what this option covers. Every other construct still follows its own option -- routine headers ([Join routine headers split by hand](join-routine-headers.md)), if / loop / with bodies (the Break ... body options), case arms, begin placement, statement packing -- and the fixed rules always apply (see [Rules (always on)](rules-always-on.md)).

A `//` comment anywhere in a statement keeps its line breaks either way; a one-line `{...}` comment moves with the token next to it.

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

// ReflowLines = true (default)
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

// ReflowLines = false
const
  BigTable: array[0..3] of array[0..5] of Integer = ((100001, 100002, 100003, 100004, 100005, 100006), (200001, 200002, 200003, 200004, 200005, 200006), (300001, 300002, 300003, 300004, 300005, 300006), (400001, 400002, 400003, 400004, 400005, 400006));

function ShowReflow(const S: string): Boolean;
begin
  Writeln(Format('%s %d',
    [S, Length(S)]));

  Result:= ((Length(S) > 10) and (Pos('alpha', S) > 0)) or ((Length(S) > 20) and (Pos('beta', S) > 0)) or ((Length(S) > 30) and (Pos('gamma', S) > 0)) or (S = 'delta') or (S = 'epsilon');
end;
```

## Related

- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
- [Blanks before section](blanks-before-section.md) - Blank lines forced before each interface section. 0 = no change.
