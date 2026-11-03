---
id: pack-short-bodies
title: Pack short bodies onto their header line
summary: "Preset for the four rules above: if/loop/with bodies are joined onto their header line when they fit, and a one-statement case arm goes on its label line. Each of the four stays its own rule: change one after checking Pack and that choice is kept (shown below the rules). Off by default."
group: short-bodies
order: 50
default: "false"
ini: PackShortBodies
cli: --pack-bodies
since: "1.0.0.0"
status: "stable"
manual: true
---

# Pack short bodies onto their header line

A one-click preset. Checking it sets four independent rules at once:

- [Break if/then/else body onto its own line](break-if-body.md) = off
- [Break loop body onto its own line](break-loop-body.md) = off
- [Break with body onto its own line](break-with-body.md) = off
- [One-statement case arm on its label line](case-arm-on-label-line.md) = on

The result: short if / for / while / with bodies are joined onto their header line when they fit the max length (`with R do Clear;`), and a one-statement case arm sits on its label line. Off by default. Saved in the INI as `PackShortBodies`; CLI: `--pack-bodies` (preset on), `--no-pack-bodies` (preset off).

The four rules stay separate options. Pack does not lock them: you can still change any of them, and a rule you set yourself is respected over the preset.

## On the Options page

The five checkboxes sit together in the "Short bodies" group, all at the same level, because the four rules are independent of Pack.

- Checking Pack sets the four rules to the preset values and highlights them.
- If, while Pack is checked, you move one of the four away from its preset value, that choice is kept and a message appears under the rules. Only the lines that apply are listed (one per rule you moved), always in this order; no conflicts means no message:

```
Respected over Pack:
- if bodies stay on their own line
- loop bodies stay on their own line
- with bodies stay on their own line
- case arm statements stay under their label
```

- Unchecking Pack leaves the four rules as they are; the highlight and the message go away.
- On opening, the Pack box shows the INI's `PackShortBodies`; the four rules show the values that actually apply (after the layering below); the message reflects any conflict. Saving writes `PackShortBodies` and all four keys.
- The preview formats with exactly what the boxes show.

## Which value wins (layers)

Settings are applied in layers; the order of keys or switches inside one layer never matters.

1. Built-in defaults.
2. The INI file (skipped entirely with `--no-ini`). If it has `PackShortBodies = true`, the preset is applied, then every one of the four rules the INI sets explicitly (key present) is put back to the INI's value.
3. The command line. If `--pack-bodies` is given (and no `--no-pack-bodies`), the preset is applied over layers 1 and 2, then every one of the four rules set by an explicit switch (`--break-if` / `--no-break-if`, `--break-loop` / `--no-break-loop`, `--break-with` / `--no-break-with`, `--case-arm-on-label` / `--no-case-arm-on-label`) is put back.

So: the command line beats the INI, and inside one layer an explicit rule beats the preset. `--no-pack-bodies` cancels the preset in both layers. `--no-ini` skips the INI layer completely (it cannot be combined with `--ini`).

Source used below: `if Ok then Run; for I:= 0 to 9 do Inc(N); with R do Clear;`

| # | INI | CLI | if | loop | with | case arm |
|---|-----|-----|----|------|------|----------|
| 1 | nothing | `--pack-bodies` | joined | joined | joined | on label |
| 2 | `BreakIfBody = true` only | `--pack-bodies` | joined (CLI beats INI) | joined | joined | on label |
| 3 | nothing | `--break-loop --pack-bodies` (either order) | joined | broken | joined | on label |
| 4 | written by YADF (all four keys true) | `--pack-bodies` | joined | joined | joined | on label |
| 5 | nothing | `--no-case-arm-on-label --pack-bodies` | joined | joined | joined | under label |
| 6 | any | `--pack-bodies --no-pack-bodies` (either order) | INI / default values | | | |
| 7 | `PackShortBodies = true` + `BreakIfBody = true` | nothing | broken (INI key beats INI preset) | joined | joined | on label |
| 8 | `PackShortBodies = true` | `--no-pack-bodies` | defaults (broken) | | | |
| 9 | anything | `--no-ini --pack-bodies` | joined | joined | joined | on label (INI not read) |

Example 4 matters: an INI saved by YADF lists all four keys, so on its own it never changes under Pack -- but `--pack-bodies` on the command line still wins over it.

## Example

```pascal
// input
if K > 0 then Inc(K) else Dec(K);
while K > 0 do Dec(K);
with R do Left:= 1;

// PackShortBodies = true (the three Break rules off)
if K > 0 then Inc(K) else Dec(K);
while K > 0 do Dec(K);
with R do Left:= 1;

// defaults (the three Break rules on)
if K > 0 then
  Inc(K)
else
  Dec(K);
while K > 0 do
  Dec(K);
with R do
  Left:= 1;
```
