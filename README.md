# YADF -- Yet Another Delphi Formatter

A Pascal/Delphi source code formatter, written in Delphi 13. Reformats `.pas`
files according to a configurable rule set: line-length budgeting, structural
re-indentation, capitalization, and column alignment.

## Quick start

```cmd
yadf MyUnit.pas
```

Format a single `.pas` file in place — the source is overwritten with the
formatted output, no backup. This is the default; if you want a copy of the
original kept, opt in:

```cmd
yadf MyUnit.pas --b
```

In-place format with a sibling backup `MyUnit.pas.BCK1` (then `BCK2`, `BCK3`,
...) next to the source. To send backups to a central folder with timestamped
`.bak` names instead, give `--b` a folder argument:

```cmd
yadf MyUnit.pas --b D:\YADF-backups
```

To send the formatted output somewhere else and leave the source untouched:

```cmd
yadf MyUnit.pas --o D:\out\MyUnit.formatted.pas    :: write to this exact file
yadf C:\src\*.pas --of D:\formatted               :: every result into this folder
```

```cmd
yadf MyProject.dpr
```

Format the `.dpr` and every local `.pas` named in its `uses` clause. `*.pas`
wildcards (`yadf C:\src\*.pas`) and `.dproj` project files work the same way
— `.dproj` is parsed for its `<DCCReference Include="...pas"/>` entries.

```cmd
yadf -h
```

Shows the full option list, every CLI flag, and the current effective
values pulled from `yadf.ini`.

## Features

**Layout**
- Configurable max line length (default 180), indent step (default 2), tab
  width (default 4)
- Full reflow: drops user line breaks where structurally non-essential, joins
  lines that fit, breaks lines that overflow
- Block-aware breaking: `uses` clauses, parenthesized argument lists, bracket
  literals all break to one item per line when needed
- Operator-chain breaking: long arithmetic/logical expressions break with the
  operator leading each new line
- Hanging indent for parens-broken statements: items at `LineWS + 2*Indent`,
  closing paren at `LineWS`

**Indentation**
- Re-indents every line based on structural depth, ignoring source whitespace
- Tracks `type/var/const` sections, `class`/`record`/`object`/`interface`
  declarations, `begin`/`end` blocks, `case`/`try`/`asm`
- Visibility keyword bonus: members inside `private`/`public`/`protected`/
  `published` indent one level deeper
- `if`/`while`/`for` body bonus: single-statement bodies after `then`/`do`/
  `else` indent one level deeper, persisting across multi-line bodies
- Case-alternative bonus: bodies after `LABEL:` indent one level deeper
- `else` aligns with its `if`; `else if` chains stay on one line

**Capitalization**
- Lowercase reserved keywords (`begin`, `end`, `if`, `else`, `var`, ...)
- Uppercase hex digits in `$NN` numeric literals and exponent letter `E`
- Uppercase compiler-directive names (`{$IFDEF}`, `{$DEFINE}`, ...)
- First-occurrence identifier-case normalization (consistent casing throughout
  the file)

**Pass-2 alignment**
- Plain align of `:` in declarations and `=` in `const` blocks across
  consecutive lines
- Smart align of `:=` assignments: when adjacent lines share the same token
  shape (same sequence of operators/punctuation, identifier names may differ),
  every common anchor (`.`, `:=`, `(`, `,`, `)`, `;`) is padded to its max
  column

**Other**
- Always emits CRLF line endings
- Reads and writes file bytes in the encoding chosen by `Encoding=` in
  `yadf.ini` (default `ANSI`; `UTF-8-BOM` and `UTF-16-BOM` also supported).
  Existing BOM in input is auto-detected on load.
- Backups are opt-in: in-place formatting overwrites the source unless
  you set `Backup=true` in `yadf.ini` or pass `--b` on the command line.
  When backups are on, they go to a sibling `<source>.BCK<N>` (default)
  or to a folder you specify with `--b <folder>` (timestamped `.bak`).
- Trailing whitespace stripped on every line
- Consecutive blank lines collapsed to a configurable cap (default 1)
- Optional blank-line insertion before sections, methods, type sections
- Block-end labels: long `begin..end` blocks get `// while`, `// procedure`,
  etc. trailing comments
- Optional unclosed-block markers: when source has unmatched `begin`/`record`,
  emit `// TODO -oYADF : 'begin' on line N has no matching 'end'` so they show
  up in the IDE's To Do List

**Robustness**
- The format pipeline is idempotent: `format(format(x)) == format(x)`
- `--check <file>` verifies byte-faithful round-trip (token stream emits
  identical bytes back)
- Tolerates structurally-broken Pascal source (missing `end`s) without
  crashing

## Configuration

YADF looks for `yadf.ini` next to the executable. CLI flags override INI
values; INI values override compiled-in defaults. See `yadf.ini` for the
documented option list.

## Building

Requires Delphi 13 (RAD Studio 37.0). Depends on
[DelphiAST](https://github.com/RomanYankovsky/DelphiAST) for its lexer; the
project file expects DelphiAST checked out at `..\DelphiAST` relative to YADF.

```cmd
cmd /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" ^
        && msbuild /t:Build /p:Config=Debug /p:Platform=Win64 YADF.dproj"
```

## Acknowledgements

YADF is built on top of [DelphiAST](https://github.com/RomanYankovsky/DelphiAST)
by @RomanYankovsky and contributors. The lexer (`SimpleParser.Lexer`) handles
all token-level details including modern Delphi syntax (multi-line strings,
inline vars, generic constraints, etc.) and made this project possible.

To build YADF from source you'll need DelphiAST checked out alongside this
repo — clone it from @RomanYankovsky/DelphiAST.

DelphiAST is Copyright (c) 2014-2020 Roman Yankovsky (roman@yankovsky.me) et
al, released under the Mozilla Public License v2.0.

## License

YADF is released under the Mozilla Public License v2.0. See `LICENSE` for the
full text. This is the same license as DelphiAST.

```
Copyright (c) 2026 Alexander Liberov

This Source Code Form is subject to the terms of the Mozilla Public License,
v. 2.0. If a copy of the MPL was not distributed with this file, You can
obtain one at https://mozilla.org/MPL/2.0/.
```
