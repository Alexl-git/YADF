# Golden-format baseline

`*.golden` files here are the **expected formatted output** of each corpus fixture
(`Test/Cases/*.pas`, `Test/Snippets/*.pas`), produced by `YADF.exe` and stored
byte-for-byte.

They exist because `--check` / `--check-dir` only verify byte-faithful **round-trip**,
not the **formatted shape** — so they cannot catch an indentation/alignment change. The
goldens are a **change detector** for edits to the formatting engine (`ReindentByDepth`,
the `Align*` passes), not a claim that the current output is perfect.

```
pwsh Test\test_golden_format.ps1            # verify: report any file whose output changed
pwsh Test\test_golden_format.ps1 -Capture   # regenerate after an INTENTIONAL format change
```

When you intentionally change formatting, the diff shows here — review it, confirm it's
the improvement you meant, then re-capture. A WIP fixture with known-bad output can be
added to the `$exclude` list in the harness so it doesn't lock in a bug (the list is
empty right now — the historical #333 / procedural-indent exclusions are all fixed).
