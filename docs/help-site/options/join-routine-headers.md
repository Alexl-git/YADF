---
id: join-routine-headers
title: Join routine headers
summary: Join a routine header the author split across lines back onto one line, wrapping it at the max length. Off = one parameter per line instead (implies "Break parameters one per line"). On by default.
group: declarations
order: 50
default: "true"
ini: JoinRoutineHeaders
since: "1.0.21.0"
status: "stable"
---

# Join routine headers

A routine header the author split across lines is joined back onto one line; when the joined line is longer than the max length it is re-wrapped after the rightmost ';' or ',' that fits, continuing one indent step in. On by default (this is the standard behaviour).

Off gives the opposite layout: one parameter per line. Off therefore IMPLIES [Break parameters one per line](break-params-one-per-line.md) -- the engine treats that option as on, and the Options page shows its box checked and disabled while this one is unchecked. A header with fewer than two parameters is not broken. A `//` comment inside a split header still blocks the join, as before.

Independent of [Reflow long lines](reflow-lines.md): turning that off does not stop headers from being joined.

## Example

Input (a header split by hand):

```
procedure JhSplit(
  const PA: string;
  PB: Integer);
```

On (default):

```
procedure JhSplit(const PA: string; PB: Integer);
```

Off (a one-parameter header such as `procedure JhOne(const PA: string);` stays on one line):

```
procedure JhSplit(
    const PA: string
    ; PB: Integer
    );
```

## Related

- [Split multi-var decls](split-multi-var-decls.md) - Split "I, J: integer;" into one line per name so the type colons align.
- [Align decl semicolons](align-decl-semicolons.md) - Align the trailing ; of consecutive declaration lines (after "Align type :").
- [Break case labels](break-case-labels.md) - Break a multi-label case arm ("a, b, c: Stmt;") into one label per line. Off by default.
