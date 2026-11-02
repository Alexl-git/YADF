---
id: pack-short-bodies
title: Pack short bodies & case arms (retired)
summary: Retired in 1.0.21.0. PackShortBodies = true in an INI is still read: it turns the three Break ... body options off and Case arm on its label line on.
group: reflow-whitespace
order: 900
default: "false"
ini: PackShortBodies
since: "1.0.0.0"
status: "retired"
manual: true
---

# Pack short bodies & case arms (retired)

Retired in 1.0.21.0 and removed from the Options page. The Break if/then/else body, Break loop body and Break with body options are now two-way (on = body on its own line, off = body joined onto its header when it fits), and Case arm on its label line owns case arms, so this option has no construct of its own left.

An INI that still says `PackShortBodies = true` keeps formatting as before: on load it sets [Break if/then/else body](break-if-body.md), [Break loop body](break-loop-body.md) and [Break with body](break-with-body.md) to false -- except one the same INI sets to true explicitly, which still wins for its own construct -- and [Case arm on its label line](case-arm-on-label-line.md) to true. Saving the settings writes those values and drops the old key. `PackShortBodies = false` changes nothing. The CLI flag `--pack-bodies` is the same alias; `--no-pack-bodies` is accepted and does nothing.
