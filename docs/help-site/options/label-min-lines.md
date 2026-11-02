---
id: label-min-lines
title: Label min lines
summary: Minimum block length in lines before a long block gets an end label.
group: labels-markers
order: 20
default: "15"
ini: LabelMinLines
cli: --label-min-lines
since: "1.0.0.0"
status: "stable"
---

# Label min lines

Minimum block size, in output lines, before LabelLongBlocks adds
a trailing label.

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

// LabelMinLines = 15 (default)
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

// LabelMinLines = 30
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

- [Label the end of long blocks](label-long-blocks.md) - After a block longer than LabelMinLines, mark its end with the block keyword: "end; // while", "end; // procedure".
- [Mark unclosed blocks](mark-unclosed.md) - When an opening begin/record/... has no matching end, add "// TODO -oYADF : 'begin' on line N has no matching 'end'".
