# Manual IDE checklist: YADF as the Delphi 13.2 code formatter

Not automatable (needs a live IDE). Run once per YADFOT build that touches
`YADFOT.CodeFormatter.pas`, on **Delphi 13.2 or later**. Older IDEs: only step 0.

Design recap: the classic Tools-menu item and Ctrl+Shift+Alt+F / R still write
the editor buffer themselves. The new path is **opt-in** (`profiles.ini`
`[IDE] NativeFormatter=1`, default off): the IDE's own Format Source asks YADF
for the formatted text and applies it itself. Only the **F profile** is used.

Prerequisites: close the IDE, rebuild YADFOT **Debug** (Win32, and Win64 for the
64-bit IDE) so no stale BPL loads, install, start the IDE.

## 0. Older IDE (Delphi 13.0/13.1 or earlier) -- no regression
- [ ] YADFOT loads; Tools > Options > Third Party > YADF shows **no** "Use YADF as the IDE code formatter" check box.
- [ ] Tools > "YADFOT: Format Current Buffer" and the shortcuts behave exactly as before.

## 1. Options switch (13.2+)
- [ ] The check box is visible below the Profiles buttons, **unchecked** by default.
- [ ] Check it, OK. `%APPDATA%\YADF\profiles.ini` now has `[IDE]` / `NativeFormatter=1`; `[Profiles]` keys unchanged.
- [ ] Restart the IDE (the switch applies at package load).

## 2. Format Source on a file
- [ ] Open a messy `.pas` (no form). Use the IDE's own Format Source command (Edit/Format menu or its shortcut).
- [ ] The text is YADF-formatted (compare with the YADF CLI output using the same F profile).
- [ ] Non-ASCII content (Cyrillic, accented, emoji in a string literal) survives intact; no BOM appears; line endings CRLF.
- [ ] Formatting an already-formatted file leaves it unchanged (idempotent).

## 3. Selection
- [ ] Select a few lines, Format Source: a dialog says YADF formats whole units only, text unchanged.
- [ ] Select All, Format Source: whole unit is formatted.
- [ ] Verify the offset assumption: with Select All the format is applied (if the IDE passes 1-based offsets the whole-file detection fails and the partial-selection dialog appears -- report that as a bug).

## 4. Undo
- [ ] After step 2, one Ctrl+Z restores the whole original text (single undo step).

## 5. Caret
- [ ] Put the caret mid-file on a code line, format: caret stays on the same line index (clamped if lines were removed), not jumped to line 1.

## 6. Decline path
- [ ] Make YADF decline (e.g. a unit with an unclosed `{` comment, or temporarily a fixture the guard rejects). A "buffer left unchanged -- the content guard declined" dialog appears and the buffer is byte-identical.

## 7. Form units
- [ ] Open a unit with a .dfm, format with the IDE command: designer stays in sync, File > Save All does not raise an access violation.

## 8. Format on save
- [ ] YADF reports `CanFormatOnSave = False`: confirm the IDE does not offer or run YADF on save (record what the IDE does if its own format-on-save option is enabled).

## 9. Coexistence with the classic command
- [ ] With the switch ON, Ctrl+Shift+Alt+F and the Tools-menu item still work and give the same text as step 2.
- [ ] Ctrl+Shift+Alt+R (R profile) still works; the IDE command always uses F.

## 10. Switch off / unload
- [ ] Uncheck the switch, OK, restart: IDE's own formatter is back (its native output).
- [ ] With the switch ON: Component > Install Packages, untick/remove YADFOT, then Format Source: no crash, no dangling formatter, IDE falls back to its own.
- [ ] Close the IDE with the switch ON: clean exit, no exception dialog.

## Record
IDE build, YADFOT version, date, and any deviations (especially: threading, undo
grouping, behaviour with two formatters registered -- all undocumented by the API).
