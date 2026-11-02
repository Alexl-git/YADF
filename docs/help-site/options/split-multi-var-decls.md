---
id: split-multi-var-decls
title: Split "A, B: T" into one per name
summary: Split "I, J: integer;" into one line per name so the type colons align. Off = kept as written.
group: declarations
order: 30
default: "true"
ini: SplitMultiVarDecls
since: "1.0.0.0"
status: "stable"
---

# Split "A, B: T" into one per name

On (default): a combined declaration such as `X, Y: Integer;` in a var, field or record block is split into one line per name, so the type colons can align. A declaration whose type is an anonymous structure (`A, B: array of Integer`) is kept whole.

Off: kept as written -- a combined declaration stays combined and separate ones are never merged. (Two declarations written on ONE line, `A: T; B: T;`, are always put on separate lines: see [Rules (always on)](rules-always-on.md).)

## Example

Real YADF output for the "SplitMultiVarDecls" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
type
  TSplitDemo = record
    X, Y: Integer;
  end;

// SplitMultiVarDecls = true (default)
type
  TSplitDemo = record
    X: Integer;
    Y: Integer;
  end;

// SplitMultiVarDecls = false
type
  TSplitDemo = record
    X, Y: Integer;
  end;
```

## Related

- [Align ; at the end of declarations](align-decl-semicolons.md) - After AlignTypeColon, align the trailing ; on consecutive declaration lines.
- [Break case labels one per line](break-case-labels.md) - Break a multi-label case arm ("a, b, c: Stmt;") into one label per line, duplicating the statement. Off by default -- multi-label case arms are kept on one line (only genuine variable/field declarations are split, per SplitMultiVarDecls).
- [Break parameters one per line](break-params-one-per-line.md) - Lay out a routine declaration with one parameter per line ("procedure Go(const A: string; B: Integer);" -> one parameter per line). Fires on named routine declarations with 2 or more parameters; a grouped declaration ("const A, B: string") is split into one name per line, repeating the modifier. Separator placement follows UsesCommaLast. A group carrying an attribute, an interior comment, or an "=" default value is kept whole. Call-site argument lists are never touched. Off by default.
