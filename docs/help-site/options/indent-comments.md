---
id: indent-comments
title: Re-indent comment lines with the code
summary: Re-indent comment-only lines to the surrounding code depth. A "//." comment keeps its indentation.
group: comments
order: 10
default: "true"
ini: IndentComments
cli: --indent-comments
since: "1.0.0.0"
status: "stable"
---

# Re-indent comment lines with the code

Re-indent comment-only lines to the surrounding code depth. When off, every comment keeps the indentation the author gave it. A comment line that starts with "//." always keeps its authored indentation even when this is on (an explicit "pin this comment" marker).

## Example

Real YADF output for the "IndentComments" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowIndentComments(var K: Integer);
begin
// re-indented when ON
  Inc(K);
end;

// IndentComments = true (default)
procedure ShowIndentComments(var K: Integer);
begin
  // re-indented when ON
  Inc(K);
end;

// IndentComments = false
procedure ShowIndentComments(var K: Integer);
begin
// re-indented when ON
  Inc(K);
end;
```
