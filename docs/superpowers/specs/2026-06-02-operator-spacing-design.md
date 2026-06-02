# Operator Spacing + Anon-Method Indent Fix — Design

**Date:** 2026-06-02
**Status:** Approved
**Repo:** `C:\Projects\YADF`
**Target release:** 1.0.5.0

---

## 1. Summary

Two engine changes, surfaced through the existing option pipeline:

1. **New option `SpaceAroundOperators` (default `true`)** — a token-level pass
   that puts exactly one space around binary `+ - * / = <= >= <>`, unary-safe
   and generics-safe.
2. **Fix the anonymous-method-as-argument indentation bug** — a multi-line
   `function`/`procedure` passed as a call argument currently under-indents its
   `function` header line.

`:=` spacing is **unchanged** (current enforce-or-leave behavior is kept).

## 2. Background

- Spacing is token-based. `NormalizeAssignSpacing(Tokens, AOpts)` runs in Stage 1
  (`YADF.Layout.pas:3497`), after `ApplyCapitalization`, before `ParseGroups`.
- Options are defined once in the `YADF_OPTIONS` descriptor table in
  `YADF.Options.pas`; a new row automatically yields the INI key, template entry,
  `--help` line, and a YADFSetup control.
- The lexer (DelphiAST `SimpleParser`) emits distinct operator tokens; `//` and
  `(* *)` are their own comment tokens (never `ptSlash`/`ptStar` pairs), and
  string/char literals are their own tokens — so a pass that iterates only real
  operator tokens naturally skips comments and strings.

## 3. Part 1 — `SpaceAroundOperators`

### Option wiring
- `TYadfOptions.SpaceAroundOperators: Boolean`.
- `DefaultOptions`: `True`.
- `YADF_OPTIONS` row: Ident `SpaceAroundOperators`, Group **`Spacing`**, Caption
  `Space around operators`, Hint `Put one space around binary operators
  (A+B -> A + B): + - * / = <= >= <>. Unary +/- and generics are left intact.
  Default: true`, Kind `okBool`, `AffectsPreview = True`.
- `OptionsTest` `EXPECTED_OPTION_COUNT`: 33 -> 34.

### The pass
`procedure NormalizeOperatorSpacing(const ATokens: TTokenList; const AOpts: TYadfOptions);`
called at `YADF.Layout.pas:~3498`, immediately after `NormalizeAssignSpacing`,
guarded by `if AOpts.SpaceAroundOperators`.

**Target operator token kinds** (exact `pt*` names verified against the lexer at
implementation time): `+`, `-`, `*`, `/`, `=`, `<=`, `>=`, `<>`.
Bare `<` and `>` are deliberately excluded (generics).

**Per operator token T at index i:**
- Determine `PrevReal` = nearest preceding token that is not `ptSpace`.
- **Binary test for `+`/`-`:** treat as binary (space it) only when `PrevReal`
  ends an operand: an identifier, a number, a string/char literal, `)`, `]`, or
  `^` (dereference). Otherwise it is unary -> leave attached, do nothing.
- `* / = <= >= <>` are always binary -> space them.
- **Ensure single space before:** if `PrevReal` exists and is not `ptCRLF` and
  not the leading-indent token: collapse an existing `ptSpace` to one, or insert
  one if missing. (Never create a space at start-of-line.)
- **Ensure single space after:** if the next token is not `ptCRLF`: collapse to
  one space or insert one. (Leave an operator that sits at end-of-line untouched,
  mirroring the `:=` rule, so multi-line RHS reflow still works.)

**Explicitly left alone:** unary `+`/`-`, bare `<`/`>` (generics), `..` ranges,
`^` pointer/deref, `@` address-of, float exponents (`1e-5` is a single number
token), and anything inside comments/strings (different token kinds).

### Pipeline interaction
Runs before `ParseGroups` (added `ptSpace` tokens don't affect group parsing).
Later `CollapseInteriorSpaces` keeps single spaces; alignment passes still pad at
anchors. Default-on will change many corpus files (every binary expression) —
expected and acceptable.

## 4. Part 2 — Anon-method indentation fix

**Symptom (reproduced):**
```
    Items.Sort(
  function(const A, B: Integer): Integer // inline anon method   <- under-indented
      begin
        Result := A - B;
      end);
```
The `function` header line is indented to column 2 instead of aligning under the
`Items.Sort(` argument. `ReindentByDepth` mis-handles a multi-line anonymous
`function`/`procedure` in argument position (ParensDepth > 0). Fix: make the
anon-method header indent consistently with its `begin`/`end` and the enclosing
call. Exact cause to be confirmed in `ReindentByDepth` during implementation;
change scoped to the anonymous-method-as-argument case (do not disturb the
1.0.0.15 fix that requires `ParensDepth = 0` for top-level procedure regions).

## 5. Part 3 — `:=` spacing

No change. `AssignNoSpaceBefore` / `AssignSpaceAfter` keep enforce-or-leave
semantics.

## 6. Testing

- New `Test\Cases\operator_spacing.pas`: binary `+ - * /`; `= <= >= <>`; unary
  `-1`, `:= -X`, `(-A)`; generic `TList<Integer>`; range `0..9`; pointer `P^` /
  `^T`; address `@X`; float `1.0e-5`; a multi-line anon method as argument.
- Corpus (`Test\Cases\*`): no crash + idempotent; capture before/after with the
  pre-change engine and confirm only intended spacing changes; spot-check a few
  remain valid Delphi.
- `OptionsTest`: ALL PASS with `EXPECTED_OPTION_COUNT = 34`.
- Rebuild all three artifacts; `YADFSetup` smoke OK.

## 7. Release

New feature -> **1.0.5.0**. Bump `build_all.bat` (`YADF_RELEASE=5`) and
`YADF.Version.inc` (`1.0.5.0`); CHANGELOG entry; rebuild all three with the
unified stamp.

## 8. Risks

- **Default-on is a broad behavior change.** Mitigated by the corpus
  no-crash/idempotency/before-after review and the unary/generics guards; users
  can set `SpaceAroundOperators=false`.
- **Unary misclassification** would attach/space wrongly. Mitigated by the
  operand-terminator test and explicit unit cases.
- **Lexer token-kind names** must be verified before coding the target set.
