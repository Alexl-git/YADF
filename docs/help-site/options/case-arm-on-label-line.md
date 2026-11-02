---
id: case-arm-on-label-line
title: Case arm on its label line
summary: Put a case arm whose body is one short simple statement on its label line ("0: DoZero;"), the case else part included ("else DoOther;"); off = the statement goes on its own line under the label.
group: reflow-whitespace
order: 70
default: "true"
ini: CaseArmOnLabelLine
since: "1.0.21.0"
status: "stable"
---

# Case arm on its label line

Lays out a case arm whose body is ONE short simple statement. On (default): the statement sits on its label line -- an arm the author broke under its label is joined when the result fits the max line length. Off: the statement goes on its own line, one indent under the label. Unchecked means the opposite layout, not "leave as written".

The case else part follows the same rule when it is one statement: `else DoOther;` on one line when on, `else` / `  DoOther;` when off (since 1.0.21.0; Break if/then/else body never touches it).

Never touched: arms whose body is a begin..end block, a nested case, try, asm or repeat; an else part of several statements; record variant parts; declarations. A // comment on the label line keeps the arm broken; a trailing // comment on the statement line moves with the statement.

The retired option "Pack short bodies" is still read from an INI as an alias: PackShortBodies = true turns this option on.

## Example

```pascal
// input
case N of
  0:
    Inc(CaA);
  1: Inc(CaB);
  3: Inc(CaD); // keep
else
  Dec(CaA);
end;

// on (default)
case N of
  0: Inc(CaA);
  1: Inc(CaB);
  3: Inc(CaD); // keep
  else Dec(CaA);
end;

// off
case N of
  0:
    Inc(CaA);
  1:
    Inc(CaB);
  3:
    Inc(CaD); // keep
  else
    Dec(CaA);
end;
```

## Related

- [Break if/then/else body onto its own line](break-if-body.md) - if statements inside an arm follow that option.
- [Break case labels](break-case-labels.md) - One label per arm; the statement then follows this option.
- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed the max line length. This option applies whether reflow is on or off.