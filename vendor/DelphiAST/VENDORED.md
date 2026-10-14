# Vendored DelphiAST lexer

YADF links only DelphiAST's **lexer** -- never its parser -- so only the three
files the lexer needs to compile live here, together with DelphiAST's license
(MPL 2.0, unchanged):

    Source\SimpleParser\SimpleParser.Lexer.pas
    Source\SimpleParser\SimpleParser.Lexer.Types.pas
    Source\SimpleParser\SimpleParser.inc
    LICENSE

They are byte-identical copies, not edited here. Vendoring makes the build
reproducible: before this, YADF compiled against a sibling `..\DelphiAST`
working copy carrying local patches that exist nowhere else, so a fresh clone
could not build YADF and the test suite could not pass.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/RomanYankovsky/DelphiAST |
| Upstream base | `3840253` (2026-01-25, "Support 'is not' and 'not in'") |
| Copied from | local DelphiAST commit `dd5b9b0` (2026-10-14) |

Local patches on top of the upstream base, all present in these copies:

| Commit | Change | Upstream status |
|---|---|---|
| `99f831e` | Multi-line string lexer fix -- `Inc(FBuffer.Run)` inside the until-loop | PR #337 (Uwe Raabe), not in upstream master as last fetched |
| `ba8bf07` | `unsafe` is a directive, not a keyword -- set `FExID`, not `Result` | PR #346, not in upstream master as last fetched |
| `dfb2326`, `dd5b9b0` | drag-lint autodoc doc-comments | local only (comments, no code) |

`Test\Golden\unsafe_identifier.pas.golden` and the multi-line string fixtures
depend on the two code patches; `Test\run_tests.ps1` fails without them.

## Refreshing

1. Update the DelphiAST working copy (merge upstream, keep or drop the patches
   above as upstream accepts them).
2. Copy the three files and `LICENSE` over these, byte-for-byte.
3. Update the table above with the new commits.
4. Rebuild and run `pwsh Test\run_tests.ps1`; a lexer change can move any
   golden.
