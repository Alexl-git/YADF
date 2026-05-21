> **STATUS: RESOLVED (2026-05-19).** The `<=` / `>=` operator-splitting bug
> has been fixed in YADF. This document is kept for history / regression
> reference only — the test cases below should pass byte-for-byte. No
> workaround is needed in Micronite code anymore; the old "prefer `= 0` over
> `<= 0`" guidance is withdrawn.

# YADF bug: `<=` operator gets mangled

**Reported:** 2026-05-14, found while running YADF on `Blueprint4.ViewModel.pas` in the Micronite/ORM3 project.

## Symptom

YADF inserts whitespace between `<` and `=` in the `<=` comparison operator, producing output that Delphi's compiler rejects.

**Repro:** any Pascal source line like:
```pascal
if Length(AID) <= 0 then Exit;
```

After `YADF.exe <file.pas> --b`, the formatter writes:
```pascal
if Length(AID) <    = 0 then Exit;
```

`dcc32` / `dcc64` then errors:
```
error E2029: Expression expected but '=' found
```

The exact number of spaces between `<` and `=` varies — looks like the alignment pass is treating `<` as a standalone comparison token then trying to right-align the `=` separately, as if they were two tokens like `:=` operator alignment.

Likely also affects `>=` (not yet confirmed). Possibly also `<>` (also not confirmed).

## Suspected location

YADF.Layout.pas or YADF.Tokens.pas — wherever the tokenizer splits operators and the alignment pass decides on padding. The bug is that `<=`/`>=` aren't being recognized as **single** two-character operators; they're being split into `<` + `=` and then each is padded independently.

## Fix direction

In the tokenizer / lexer:
- `<=`, `>=`, `<>`, and `:=` should all be recognized as single tokens (compound operators) before any alignment / padding logic runs.
- Verify the `:=` case still works (it's the most common compound operator and apparently does work, so check whether `<=`/`>=` go through a different code path).

## Test cases for the fix

Add these lines to a test file and run YADF; the output should match the input byte-for-byte (no inserted whitespace inside the operators):

```pascal
if Length(AID) <= 0 then Exit;
if I >= N then Break;
if A <> B then DoSomething;
X := Y + 1;
```

## Workaround until fixed

In Micronite code that gets YADF-formatted, prefer `= 0` / `< N+1` / `not (X > Y)` over `<= 0` / `<= N` / `<= Y`. Workaround documented in the Claude memory at `~/.claude/projects/C--Users-alexanderl/memory/feedback_yadf_le_operator.md`.

## Where the bug was hit

`C:\Projects\DB\ORM3\CLIENT\Blueprint4.ViewModel.pas` line 1508 (post-YADF), in the new `ApplyActiveField` method added 2026-05-14. Code was:

```pascal
procedure TBlueprint_ViewModel.ApplyActiveField(AID: TArray<Integer>);
...
begin
  ...
  if Length(AID) <= 0 then Exit;   // <-- YADF mangled this to `<    =`
  ...
end;
```

Original source pre-YADF was correct; the mangling happened during YADF's format pass.
