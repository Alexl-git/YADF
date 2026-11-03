---
id: break-params-one-per-line
title: Break parameters one per line
summary: Lay out routine declarations with 2+ parameters one parameter per line. Off by default; always on while "Join routine headers split by hand" is off. The separator side follows "Put the separator last in broken lists".
group: declarations
order: 20
default: "false"
ini: BreakParamsOnePerLine
cli: --break-params
since: "1.0.0.0"
status: "stable"
---

id: break-params-one-per-line
title: Break parameters one per line
summary: Lay out routine declarations with 2+ parameters one parameter per line. Off by default; always on while "Join routine headers split by hand" is off. The separator side follows "Put the separator last in broken lists".
group: declarations
order: 20
default: "false"
ini: BreakParamsOnePerLine
cli: --break-params
since: "1.0.0.0"
status: "stable"
---

# Break parameters one per line

Lay out a routine declaration with one parameter per line ("procedure Go(const A: string; B: Integer);" -> one parameter per line). Fires on named routine declarations with 2 or more parameters; a grouped declaration ("const A, B: string") is split into one name per line, repeating the modifier. Separator placement follows UsesCommaLast. A group carrying an attribute, an interior comment, or an "=" default value is kept whole. Call-site argument lists are never touched. Off by default.

Always on while [Join routine headers split by hand](join-routine-headers.md) is off: that option implies this one, and the Options page shows this box checked and disabled meanwhile. Your own value is kept and applies again once Join routine headers is back on.

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

// BreakParamsOnePerLine = false (default)
procedure ShowJoinHeader(const AName: string; ACount: Integer);
begin
  Writeln(AName, ACount);
end;

procedure ShowBreakParams(const AName: string; ACount: Integer);
begin
  Writeln(AName, ACount);
end;

// BreakParamsOnePerLine = true
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
- [Align ; at the end of declarations](align-decl-semicolons.md) - After AlignTypeColon, align the trailing ; on consecutive declaration lines.
- [Break case labels one per line](break-case-labels.md) - Break a multi-label case arm ("a, b, c: Stmt;") into one label per line, duplicating the statement. Off by default -- multi-label case arms are kept on one line (only genuine variable/field declarations are split, per SplitMultiVarDecls).
