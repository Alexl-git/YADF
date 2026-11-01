---
id: pack-short-bodies
title: Pack short bodies & case arms
summary: Pull a short loop/if body or case arm onto one line when reflowing; implies "Case arm on its label line". Off by default.
group: reflow-whitespace
order: 70
default: "false"
ini: PackShortBodies
since: "1.0.0.0"
status: "stable"
---

# Pack short bodies & case arms

When reflowing, pull a SHORT body onto one line: a loop/if header keeps its simple statement ("for I := 0 to N do Inc(X);", "if X then DoIt;") and a case arm collapses onto its label ("0: DoZero;"). Off by default -- every body/arm stays on its own line. A nested control header (if/case/begin...) is never half-merged onto a do/then/label either way.

Off means only "don't pack": a body already on its header line is not un-packed. On implies [Case arm on its label line](case-arm-on-label-line.md) on. An explicit Break loop/with/if body option wins over Pack for its own construct; Pack decides only what no Break option covers.

## Related

- [Reflow long lines](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
