---
id: label-long-blocks
title: Label the end of long blocks
summary: Mark the end of long blocks with the block keyword: "end; // while".
group: labels-markers
order: 10
default: "true"
ini: LabelLongBlocks
since: "1.0.0.0"
status: "stable"
---

# Label the end of long blocks

On (default): a long begin / record / case / try / asm / object block -- at least [Label min lines](label-min-lines.md) lines -- gets a trailing `// while`, `// procedure`, ... comment after its closing `end;` so the end is self-describing.

Off: kept as written -- no labels are added and labels already in the source are left alone.

## Example

Real YADF output for the "LabelLongBlocks + LabelMinLines" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowLabelLongBlocks(var K: Integer);
begin
  Inc(K); // 1
  Inc(K); // 2
  Inc(K); // 3
  Inc(K); // 4
  Inc(K); // 5
  Inc(K); // 6
  Inc(K); // 7
  Inc(K); // 8
  Inc(K); // 9
  Inc(K); // 10
  Inc(K); // 11
  Inc(K); // 12
  Inc(K); // 13
  Inc(K); // 14
end;

end.

// LabelLongBlocks = true (default)
procedure ShowLabelLongBlocks(var K: Integer);
begin
  Inc(K); // 1
  Inc(K); // 2
  Inc(K); // 3
  Inc(K); // 4
  Inc(K); // 5
  Inc(K); // 6
  Inc(K); // 7
  Inc(K); // 8
  Inc(K); // 9
  Inc(K); // 10
  Inc(K); // 11
  Inc(K); // 12
  Inc(K); // 13
  Inc(K); // 14
end; // procedure

end.

// LabelLongBlocks = false
procedure ShowLabelLongBlocks(var K: Integer);
begin
  Inc(K); // 1
  Inc(K); // 2
  Inc(K); // 3
  Inc(K); // 4
  Inc(K); // 5
  Inc(K); // 6
  Inc(K); // 7
  Inc(K); // 8
  Inc(K); // 9
  Inc(K); // 10
  Inc(K); // 11
  Inc(K); // 12
  Inc(K); // 13
  Inc(K); // 14
end;

end.
```

## Related

- [Label min lines](label-min-lines.md) - Minimum lines a block must span before LabelLongBlocks adds the marker.
- [Mark unclosed blocks](mark-unclosed.md) - When an opening begin/record/... has no matching end, add "// TODO -oYADF : 'begin' on line N has no matching 'end'".
