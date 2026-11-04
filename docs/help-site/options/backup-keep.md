---
id: backup-keep
title: Backups to keep
summary: How many backups of each file to keep (used when backup is on). After a run writes a backup, older YADF backups of that same file beyond the newest N are deleted. 0 = keep all.
group: file-cli-no-preview-effect
order: 30
default: "0"
ini: BackupKeep
cli: --backup-keep
since: "1.0.21.0"
status: "stable"
---

# Backups to keep

How many backups of each file to keep (used when backup is on). After a run writes a backup, older YADF backups of that same file beyond the newest N are deleted. 0 = keep all.

## Related

- [Backup before overwrite](backup.md) - Create a backup of every file before overwriting it, and of an edited preview sample (Sample.pas.bak) before a newer YADF replaces it.
- [Backup directory](backup-dir.md) - Directory for backups (used when backup is on). Empty = next to the original file.
- [Result directory](result-dir.md) - Directory for formatted output. Empty = format in place.
