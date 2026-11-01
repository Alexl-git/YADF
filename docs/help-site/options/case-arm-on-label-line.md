---
id: case-arm-on-label-line
title: Case arm on its label line
summary: Put a case arm whose body is one short simple statement on its label line ("0: DoZero;"); off = the statement goes on its own line under the label. Always on while "Pack short bodies" is on.
group: reflow-whitespace
order: 80
default: "true"
ini: CaseArmOnLabelLine
since: "1.0.0.0"
status: "stable"
---

# Case arm on its label line

Lays out a case arm whose body is ONE short simple statement. On (default): the statement sits on its label line -- an arm the author broke under its label is joined when the result fits the max line length. Off: the statement goes on its own line, one indent under the label. Unchecked means the opposite layout, not "leave as written".

Never touched: arms whose body is a begin..end block, a nested case, try, asm or repeat; the case else part; record variant parts; declarations. A // comment on the label line keeps the arm broken; a trailing // comment on the statement line moves with the statement.

"Pack short bodies & case arms" on implies this option on: the Options page shows the box checked and disabled while Pack is checked.

## Example

```pascal
// input
case N of
  0:
    Inc(CaA);
  1: Inc(CaB);
  3: Inc(CaD); // keep
end;

// on (default)
case N of
  0: Inc(CaA);
  1: Inc(CaB);
  3: Inc(CaD); // keep
end;

// off
case N of
  0:
    Inc(CaA);
  1:
    Inc(CaB);
  3:
    Inc(CaD); // keep
end;
```

## Related

- [Pack short bodies & case arms](pack-short-bodies.md) - On implies this option on.
- [Break case labels](break-case-labels.md) - One label per arm; the statement then follows this option.
- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed the max line length. This option applies whether reflow is on or off.