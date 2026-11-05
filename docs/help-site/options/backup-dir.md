---
id: backup-dir
title: Backup directory
summary: Directory for backups (used when backup is on). Empty = next to the original file.
group: file-cli-no-preview-effect
order: 20
default: ""
ini: BackupDir
cli: --b
since: "1.0.0.0"
status: "stable"
---

# Backup directory

Used only when Backup=true and ResultDir is empty.
  - Non-empty: write a timestamped <name>.<hhhhhhhh>.<YYYYMMDD-hhmmss>.bak
    under this folder before overwriting the source. The hex digits
    identify the source folder, so same-named files from different
    folders never share (or prune) each other's backups.
  - Empty (default): write <source>.BCK<N> next to the source,
    where N is one above the highest existing number (a freed lower
    number is never reused, so the numbers stay in age order).
CLI equivalent: --b <folder> (with arg) or --b (no arg, sibling).

## Example

No effect on the formatted code. In yadf.ini, or on the command line:

```
Backup    = true
BackupDir = C:\Backups\Yadf
yadf --b C:\Backups\Yadf MyUnit.pas   (writes MyUnit.pas.<hhhhhhhh>.<YYYYMMDD-hhmmss>.bak there)
```

## Related

- [Backup before overwrite](backup.md) - Create a backup of every file before overwriting it.
- [Result directory](result-dir.md) - Directory for formatted output. Empty = format in place.
- [Output encoding](encoding.md) - ANSI keeps each file's own encoding (BOM or detected UTF-8 preserved); UTF-8/UTF-16 convert the output (with BOM).
