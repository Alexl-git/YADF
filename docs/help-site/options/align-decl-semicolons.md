---
id: align-decl-semicolons
title: Align ; at the end of declarations
summary: Align the trailing ; of consecutive declaration lines (after "Align : in declarations").
group: alignment
order: 40
default: "true"
ini: AlignDeclSemicolons
since: "1.0.0.0"
status: "stable"
---

# Align ; at the end of declarations

After AlignTypeColon, align the trailing `;` on adjacent declaration
lines so the semicolons line up in a column too. Set this AND
AlignTypeColon to false for plain `Name: Type;` declarations.

## Example

Real YADF output for the "AlignDeclSemicolons" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
type
  TSemiDemo = record
    Alpha: Integer;
    Gamma: string;
  end;

// AlignDeclSemicolons = true (default)
type
  TSemiDemo = record
    Alpha: Integer;
    Gamma: string ;
  end;

// AlignDeclSemicolons = false
type
  TSemiDemo = record
    Alpha: Integer;
    Gamma: string;
  end;
```

## Related

- [Split "A, B: T" into one per name](split-multi-var-decls.md) - Split "I, J: integer;" into one line per name so the type colons align.
- [Break case labels one per line](break-case-labels.md) - Break a multi-label case arm ("a, b, c: Stmt;") into one label per line, duplicating the statement. Off by default -- multi-label case arms are kept on one line (only genuine variable/field declarations are split, per SplitMultiVarDecls).
- [Break parameters one per line](break-params-one-per-line.md) - Lay out a routine declaration with one parameter per line ("procedure Go(const A: string; B: Integer);" -> one parameter per line). Fires on named routine declarations with 2 or more parameters; a grouped declaration ("const A, B: string") is split into one name per line, repeating the modifier. Separator placement follows UsesCommaLast. A group carrying an attribute, an interior comment, or an "=" default value is kept whole. Call-site argument lists are never touched. Off by default.
