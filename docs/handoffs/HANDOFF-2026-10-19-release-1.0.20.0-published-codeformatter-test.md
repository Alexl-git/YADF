# Handoff 2026-10-19 -- 1.0.20.0 PUBLISHED; 13.2 code-formatter needs live-IDE test, then final Fable review

## Status
- **1.0.20.0 is released and public.** Tag `1.0.20.0` on `b6ac0fe`; GitHub release has one asset
  `YADF-1.0.20.0.zip` (2,951,943 bytes, 7 entries; SHA-256 e04fc5eb...f6fe verified equal to the local zip).
- `main` == `origin/main` at `a37773a` (3 commits AFTER the tag, not in the release). Git clean except
  untracked `Test/FormatBridgeTest.res` (build artifact; add to .gitignore).
- Suite 38/38 at the tag; 39/39 after the formatter work (one late comment-only lint-marker edit was not
  followed by a full-suite rerun -- only FormatBridgeTest + YADFOT builds were rerun).
- This session: Fable re-review of f410f22..HEAD found 2 semantic bugs (attribute list lost on
  `A, B: T;` split at DEFAULT settings -- also in 1.0.19; `--d10` loop-body managed inline var hoisted
  without re-init) plus cosmetics. Fixed test-first: 56577d9, 963feff, 7ce42a2 (`--o` read-only exit 1),
  00d49bd (asm `end` same line), ee8e820 (align: equal indent / skip `[Attr]` lines), 6912c9b (bare CR),
  5626f4e (IsLoopBegin through then/else/do), b6ac0fe (CHANGELOG). Skipped: `{$IFDEF X} if..then begin
  {$ELSE} ... {$ENDIF}` re-indent (needs ~6 parallel stacks snapshotted in ReindentByDepth; documented as
  a Known limitation).

## NEW, unreleased (8e0545b, d47cd09, a37773a): Delphi 13.2 IOTACodeFormatter integration
- ToolsAPI.pas (37.0, dated 2026-09-09) declares `IOTACodeFormatter` (~10858) and
  `IOTACodeFormatterServices` (~10926). Formatter RETURNS text, IDE applies it. No Embarcadero docs found.
- Gate: `{$IF DECLARED(IOTACodeFormatter) and not DEFINED(YADF_NO_CODEFORMATTER)}` in
  `YADFOT.CodeFormatter.inc` (include AFTER `uses ToolsAPI`). Elsewhere the unit is 3 no-ops, check box
  hidden. Both gate-on (Win32+Win64 Debug) and forced-off (Win32) builds compile.
- Files: `YADF.FormatBridge.pas`, `YADFOT.CodeFormatter.pas/.inc`, Options `LoadNativeFormatterFlag`/
  `SaveNativeFormatterFlag`, check box on the YADF options page, `Test\FormatBridgeTest`.
- Default OFF: `profiles.ini [IDE] NativeFormatter` (restart IDE). ON = IDE Format Source uses YADF.
  Ctrl+Shift+Alt+F/R and menu path untouched. Guard decline/engine error -> original text returned +
  dialog. FormatSelected: only Select All formats; partial selection declined (fragment dedent corrupts).
  CanFormatLine/FormatLine/SupportsOffsetRemapping/CanFormatOnSave all False.

## Resume point (owner is testing today)
1. Owner runs `Test\MANUAL-IDE-CODEFORMATTER.md` in the live 13.2 IDE (Debug BPLs were rebuilt, IDE was
   closed). Key unknowns: 0- vs 1-based `CursorOffset`/`SelOffset` (1-based would make Select All get
   declined, checklist step 3), undo grouping (one step?), calling thread, a second registered formatter.
2. Then the FINAL Fable review of `b6ac0fe^..HEAD` (never reviewed: the cosmetic batch 00d49bd..b6ac0fe,
   esp. IsLoopBegin and SmartAlignAssignments; and the whole formatter integration). Use Agent with
   model `fable`, read-only, brief it with REVIEW-2026-10-14.md / this handoff so it skips fixed items.
3. Fix findings test-first, then release 1.0.21.0 (formatter included if the checklist passes). Recipe:
   memory project_yadf_micronite_dogfood_bugs.md + feedback_yadf_release_platform_matrix.md
   (YADF.exe + YADFSetup.exe Win64 ONLY; YADFOT Win32+Win64 bpls; 7-entry zip; bump YADF.Version.inc +
   build_all.bat YADF_RELEASE; owner runs push/tag/gh; verify download hash). Release builds do not update
   the IDE: rebuild Debug BPLs with the IDE closed.

## Not done yet
- Notify CHARTS/installer session and drag-lint: exit codes 0 ok / 1 failure / 2 usage / 3 guard declined
  (file unchanged); see Delphi-RAG-lint\docs\INBOX-yadf-decline-exit-code-3.md.
- Delete the 9 merged `worktree-agent-*` branches (owner: `git --no-pager branch --list 'worktree-agent-*'
  --format='%(refname:short)' | ForEach-Object { git branch -d $_ }`).
- Add `Test/FormatBridgeTest.res` to .gitignore. YADF.res/YADFSetup.res/YADFOT.res are dirtied by every
  build; never commit.
- Remaining cosmetics: `--break-if` remainder alignment in edge cases, `FormatSelected` for real partial
  selections (needs a statement-boundary-aware fragment formatter), offset remapping (~1 week), per-line
  formatting, format-on-save (all unimplemented in the code formatter).
- Low-priority drag-lint gap: routine-local enum values not indexed
  (Delphi-RAG-lint\docs\INBOX-routine-local-enum-values-not-indexed.md).

## Gotchas
- Tag was cut at b6ac0fe, not HEAD; main carries 3 unreleased commits.
- `run_tests.ps1` fails on stale GuardTest/OptionsTest/exe: rebuild Debug first.
- Subagents' worktree branches start stale; `git merge main` first.
- `lint-all --fix` preview leaves `.bak` files next to sources.
- dl:ok marker hashes go stale on ANY edit of a routine (refresh after edits).
- Goldens bless behaviour; prefer compile-checked fixtures.
