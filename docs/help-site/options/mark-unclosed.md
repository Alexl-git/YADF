---
id: mark-unclosed
title: Mark unclosed blocks
summary: Add a "// TODO -oYADF" marker where a begin/record/... has no matching end.
group: labels-markers
order: 30
default: "false"
ini: MarkUnclosed
cli: --mark-unclosed
since: "1.0.0.0"
status: "stable"
---

# Mark unclosed blocks

When true, force-closed openers (a `begin` with no matching
`end`, etc.) emit a `// TODO -oYADF : '<keyword>' on line N has
no matching 'end'` marker so they show up in the IDE's To-Do list.

## Example

Real YADF output for a unit whose record has no `end` (the preview sample cannot show this: it must compile):

```pascal
// input
type
  TRec = record
    X: Integer;

implementation
...
end.

// MarkUnclosed = true
(the same code, then at the end of the file:)
// TODO -oYADF : 'record' on line 6 has no matching 'end'

// MarkUnclosed = false (default)
(the same code, no marker)
```

## Related

- [Label the end of long blocks](label-long-blocks.md) - After a block longer than LabelMinLines, mark its end with the block keyword: "end; // while", "end; // procedure".
- [Label min lines](label-min-lines.md) - Minimum lines a block must span before LabelLongBlocks adds the marker.
