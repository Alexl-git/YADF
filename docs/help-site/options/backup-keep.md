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

## Which backups count

Only backups YADF names for that exact file are ever deleted:

- Next to the source: `<name>.BCK<N>` (N has no leading zero).
- In a backup folder (`--b <folder>`): `<name>.<hhhhhhhh>.<yyyymmdd-hhnnss>[-n].bak`. The eight hex digits identify the source folder, so `A\Unit1.pas` and `B\Unit1.pas` sharing one backup folder keep separate backups and never prune each other.
- Older backups in a folder without the hex digits (`Unit1.pas.<stamp>.bak`, written before this naming) have an ambiguous owner and are never deleted; remove them by hand.

## Related

- [Backup before overwrite](backup.md) - Create a backup of every file before overwriting it, and of an edited preview sample (Sample.pas.bak) before a newer YADF replaces it.
- [Backup directory](backup-dir.md) - Directory for backups (used when backup is on). Empty = next to the original file.
- [Result directory](result-dir.md) - Directory for formatted output. Empty = format in place.
