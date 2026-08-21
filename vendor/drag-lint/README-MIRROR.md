# Vendored from drag-lint -- DO NOT EDIT

`DRagLint.Lint.ReviewMarker.pas` in this folder is a **byte-identical mirror** of

```
C:\Projects\Delphi-RAG-lint\src\lint\DRagLint.Lint.ReviewMarker.pas
```

It is copied, not forked. The mirror carries no local header precisely so the
copy can be verified by hash; this file is where the "it is a mirror" statement
lives instead. Drift is caught by `tests\autotest\run_reviewmarker_yadf_mirror.ps1`
in the drag-lint battery, which compares the two files' SHA256.

## What it is for

drag-lint writes `dl:ok` review markers into YADF's own source:

```pascal
except // dl:ok bare-except@7f3a -- rethrown by the caller
```

The `@7f3a` is 4 hex of a hash over that line's **code tokens** -- comments
excluded, whitespace dropped, identifiers lowercased, string-literal content kept
verbatim. That normalisation exists so YADF's reindentation and case
normalisation do **not** invalidate a human's review, while a real edit does.

As of 2026-08-17 YADF holds **147** such markers, written by drag-lint. YADF was
already a consumer of this hash without owning the function; this mirror closes
that gap.

## VERIFY AND WARN. NEVER REWRITE. This is the whole design.

A correct normalisation-invariant hash gives YADF **nothing to keep current**.
Every edit YADF makes is already inside the normalisation, so after a YADF pass
the hash is bit-for-bit what it was.

The only edits that move the hash are edits that change what the code MEANS --
`i` renamed to `j`, `0` changed to `1`. Those are exactly the edits that must
invalidate a review. **A "refresh the hash" feature would therefore fire only in
the cases where refreshing is wrong**: it would silently re-validate a review of
code no human re-examined, which is the one failure the whole design exists to
prevent.

So the supported YADF behaviour is: on a line carrying a `dl:ok` marker whose
hash no longer matches, **emit a warning** naming the file and line. That makes
YADF a second detector for stale reviews, at zero risk.

## Use `HashWindow`, not `HashLine`

`TReviewMarkers.HashWindow` hashes a bounded WINDOW for lone-keyword anchors
(`except`, `begin`, ...); `HashLine` hashes a single line. A checker built on
`HashLine` alone would disagree with drag-lint on exactly the anchors that
motivated `HashWindow` -- and the disagreement would look like a batch of stale
reviews rather than a version skew. Use `HashWindow` together with
`NormalizedIsLoneKeyword`, which is what decides when the window applies.

## Do not change `NormalizeLine`

Counted 2026-08-16 across the three repos: **249 `dl:ok` markers**
(drag-lint 43, YADF 147, DataCopy 59). Any change to `NormalizeLine` invalidates
every one of them and turns the whole set into mass "stale review" re-reports.
Treat it as frozen unless there is a correctness reason, and budget the
re-stamp. Changing it **here** would be worse still: it would make this file
differ from its source, which the battery reports as drift.
