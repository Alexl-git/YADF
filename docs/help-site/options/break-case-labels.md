---
id: break-case-labels
title: Break case labels one per line
summary: Break a multi-label case arm ("a, b, c: Stmt;") into one label per line. Off by default.
group: case-statements
order: 20
default: "false"
ini: BreakCaseLabels
cli: --break-case
since: "1.0.0.0"
status: "stable"
---

id: break-case-labels
title: Break case labels one per line
summary: Break a multi-label case arm ("a, b, c: Stmt;") into one label per line. Off by default.
group: case-statements
order: 20
default: "false"
ini: BreakCaseLabels
cli: --break-case
since: "1.0.0.0"
status: "stable"
---

# Break case labels one per line

Break a multi-label case arm ("a, b, c: Stmt;") into one label per line, duplicating the statement. Off by default -- multi-label case arms are kept on one line (only genuine variable/field declarations are split, per SplitMultiVarDecls).

Off also joins a multi-label arm the author broke across lines (`7,` / `8: X;` -> `7, 8: X;`) when it fits the max line length; the colons of consecutive arms stay aligned. Where the statement goes (label line or under it) follows [One-statement case arm on its label line](case-arm-on-label-line.md).

## Example

Real YADF output for the "CaseArmOnLabelLine + BreakCaseLabels" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowCaseArms(var K: Integer);
begin
  case K of
    1, 2:
      Inc(K);
    3, 4: Dec(K);
  else
    K:= 0;
  end;
end;

// BreakCaseLabels = false (default)
procedure ShowCaseArms(var K: Integer);
begin
  case K of
    1, 2: Inc(K);
    3, 4: Dec(K);
    else K:= 0;
  end;
end;

// BreakCaseLabels = true
procedure ShowCaseArms(var K: Integer);
begin
  case K of
    1: Inc(K);
    2: Inc(K);
    3: Dec(K);
    4: Dec(K);
    else K:= 0;
  end;
end;
```

## Related

- [Split "A, B: T" into one per name](split-multi-var-decls.md) - Split "I, J: integer;" into one line per name so the type colons align.
- [Align ; at the end of declarations](align-decl-semicolons.md) - After AlignTypeColon, align the trailing ; on consecutive declaration lines.
- [Break parameters one per line](break-params-one-per-line.md) - Lay out a routine declaration with one parameter per line ("procedure Go(const A: string; B: Integer);" -> one parameter per line). Fires on named routine declarations with 2 or more parameters; a grouped declaration ("const A, B: string") is split into one name per line, repeating the modifier. Separator placement follows UsesCommaLast. A group carrying an attribute, an interior comment, or an "=" default value is kept whole. Call-site argument lists are never touched. Off by default.
