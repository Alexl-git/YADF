---
id: join-routine-headers
title: Join routine headers split by hand
summary: Join a routine header the author split across lines back onto one line, wrapping it at the max length. Off = one parameter per line instead (implies "Break parameters one per line"). On by default.
group: declarations
order: 10
default: "true"
ini: JoinRoutineHeaders
cli: --join-headers
since: "1.0.21.0"
status: "stable"
---

# Join routine headers split by hand

A routine header the author split across lines is joined back onto one line; when the joined line is longer than the max length it is re-wrapped after the rightmost ';' or ',' that fits, continuing one indent step in. On by default (this is the standard behaviour).

Off gives the opposite layout: one parameter per line. Off therefore IMPLIES [Break parameters one per line](break-params-one-per-line.md) -- the engine treats that option as on, and the Options page shows its box checked and disabled while this one is unchecked. A header with fewer than two parameters is not broken. A `//` comment inside a split header still blocks the join, as before.

Independent of [Reflow lines (join and wrap)](reflow-lines.md): turning that off does not stop headers from being joined.

## Example

Real YADF output for the "JoinRoutineHeaders + BreakParamsOnePerLine" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowJoinHeader(
  const AName: string;
  ACount: Integer);
begin
  Writeln(AName, ACount);
end;

procedure ShowBreakParams(const AName: string; ACount: Integer);
begin
  Writeln(AName, ACount);
end;

// JoinRoutineHeaders = true (default)
procedure ShowJoinHeader(const AName: string; ACount: Integer);
begin
  Writeln(AName, ACount);
end;

procedure ShowBreakParams(const AName: string; ACount: Integer);
begin
  Writeln(AName, ACount);
end;

// JoinRoutineHeaders = false
procedure ShowJoinHeader(
    const AName: string
    ; ACount: Integer
    );
begin
  Writeln(AName, ACount);
end;

procedure ShowBreakParams(
    const AName: string
    ; ACount: Integer
    );
begin
  Writeln(AName, ACount);
end;
```

## Related

- [Split "A, B: T" into one per name](split-multi-var-decls.md) - Split "I, J: integer;" into one line per name so the type colons align.
- [Align ; at the end of declarations](align-decl-semicolons.md) - Align the trailing ; of consecutive declaration lines (after "Align : in declarations").
- [Break case labels one per line](break-case-labels.md) - Break a multi-label case arm ("a, b, c: Stmt;") into one label per line. Off by default.
