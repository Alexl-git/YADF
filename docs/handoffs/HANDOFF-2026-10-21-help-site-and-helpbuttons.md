# Handoff 2026-10-21 -- online help, hints, help ids, "?" buttons

## Status
- Online help LIVE (published by WWW team 2026-10-21): https://www.delphi-rag-lint.com/help/yadf/
  and leaves /help/yadf/options/<id>/ (47, all 200). Source of truth = docs/help-site/ (commit 265a9ef
  was the published tree). WWW copies it into C:\Projects\Delphi-RAG-lint\WWW\help\yadf\ and republishes
  only with the website owner's go (tell www-51 when bodies change).
- Feature registry: OptionTable (YADF.Options.pas) = ident/group/caption/short hint. Test\gen_help_site.ps1
  generates leaf front matter + index.json (keeps existing bodies; leaves with `manual: true` untouched);
  Test\test_help_site.ps1 guards index<->files, relative links, regeneration no-op. Suite 40/40.
- Short hints applied to YADFSetup + IDE page (shared YADF.OptionsFrame); long text lives in the leaves.
- Help ids: OptionHelpId (kebab of INI key) -> HelpKeyword; OptionHelpUrl + var YadfHelpBaseUrl.
- "?" buttons (TYadfHelpButton in YADF.OptionsFrame.pas, commit 039279f) next to every option row,
  Profiles label, IDE formatter check box; click = ShellExecute of the leaf URL (click NOT yet tested).
- Bug fixed: '&' in group captions ("Line length & indentation") -- commit 2e2cd99.
- Commits since 13f6fc1 (4, NOT pushed): 53dd102, 265a9ef, 2e2cd99, 039279f.
- YADFOT Debug Win32 AND Win64 rebuilt 2026-10-21 (IDE closed): owner can test in the IDE now.

## Resume point (first things to do)
1. Owner opens IDE: Tools > Options > Third Party > YADF; check "?" buttons (both 32/64-bit IDE if
   possible), click one -> browser opens the leaf. Owner may take a screenshot (<=1600 px, check for the
   user name) -> check it, give path to www-51. Existing website shot: docs\screenshots\yadfsetup-main.png
   (pre-buttons; a new one from the stamped Release build is promised to www-51).
2. Owner's live-IDE checklist for the Delphi 13.2 code formatter: Test\MANUAL-IDE-CODEFORMATTER.md
   (from the 2026-10-19 handoff, still open), then final Fable review of b6ac0fe^..HEAD, then 1.0.21.0
   (build_all.bat, version bump, zip with 4 binaries per feedback_yadf_release_platform_matrix).
3. Owner must push (git push needs approval; or .private\GITPush.bat).

## Not done yet
- Leaf "Since:" is a placeholder "1.0.0.0" everywhere; correct per option from CHANGELOG.md.
- Leaf bodies are first drafts (from yadf.ini comments); polish later, then tell www-51 to republish.
- Release notes/CHANGELOG for 1.0.21.0 should mention hints, help site, "?" buttons, & caption fix.
- Peer www-51 (WWW team session) waits for: IDE screenshot, refreshed YADFSetup shot with buttons.
- Offline help (file://): set YadfHelpBaseUrl; WWW promised a relative-asset offline build later.

## Gotchas
- Delphi sources: when scripting edits use ReadAllText(1252)+normalize to CRLF; heredocs eat doubled
  backslashes; `python -` hangs in this shell (do not use).
- run_tests needs Debug Win64 binaries rebuilt after source edits (YADF, YADFSetup, OptionsTest,
  GuardTest, FormatBridgeTest) -- batch files were in the session scratchpad (rsvars+msbuild recipe).
- ConvertTo-Json differs between PS5/7 -- index.json is hand-rendered by the generator on purpose.
- Option-row layout: spin/enum/edit controls moved to Left 200/130, "?" column at HelpButtonColumn=288.
- Screenshot tool: PrintWindow script (scratchpad shot.ps1) + username painted out by hand.
