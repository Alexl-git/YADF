---
id: case-arm-on-label-line
title: One-statement case arm on its label line
summary: Put a case arm whose body is one short simple statement on its label line ("0: DoZero;"), the case else part included ("else DoOther;"); off = the statement goes on its own line under the label.
group: case-statements
order: 10
default: "true"
ini: CaseArmOnLabelLine
cli: --case-arm-on-label
since: "1.0.21.0"
status: "stable"
---

id: case-arm-on-label-line
title: One-statement case arm on its label line
summary: Put a case arm whose body is one short simple statement on its label line ("0: DoZero;"), the case else part included ("else DoOther;"); off = the statement goes on its own line under the label.
group: case-statements
order: 10
default: "true"
ini: CaseArmOnLabelLine
cli: --case-arm-on-label
since: "1.0.21.0"
status: "stable"
---

# One-statement case arm on its label line

Lays out a case arm whose body is ONE short simple statement. On (default): the statement sits on its label line -- an arm the author broke under its label is joined when the result fits the max line length. Off: the statement goes on its own line, one indent under the label. Unchecked means the opposite layout, not "leave as written".

The case else part follows the same rule when it is one statement: `else DoOther;` on one line when on, `else` / `  DoOther;` when off (since 1.0.21.0; Break if/then/else body never touches it).

Never touched: arms whose body is a begin..end block, a nested case, try, asm or repeat; an else part of several statements; record variant parts; declarations. A // comment on the label line keeps the arm broken; a trailing // comment on the statement line moves with the statement.

An arm whose statement is an if / for / while / with follows its Break*Body option exactly as elsewhere (since 1.0.21.0): when that option breaks the statement over several lines, the whole statement goes under the label (`5:` / `  if C then` / `    A` / `  else` / `    B;`), never half on the label line; when it stays one line, this option decides (`5: if C then A else B;` when on).

The retired option "Pack short bodies" is still read from an INI as an alias: PackShortBodies = true turns this option on.

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

// CaseArmOnLabelLine = true (default)
procedure ShowCaseArms(var K: Integer);
begin
  case K of
    1, 2: Inc(K);
    3, 4: Dec(K);
    else K:= 0;
  end;
end;

// CaseArmOnLabelLine = false
procedure ShowCaseArms(var K: Integer);
begin
  case K of
    1, 2:
      Inc(K);
    3, 4:
      Dec(K);
    else
      K:= 0;
  end;
end;
```

## Related

- [Break if/then/else body onto its own line](break-if-body.md) - if statements inside an arm follow that option.
- [Break case labels one per line](break-case-labels.md) - One label per arm; the statement then follows this option.
- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed the max line length. This option applies whether reflow is on or off.