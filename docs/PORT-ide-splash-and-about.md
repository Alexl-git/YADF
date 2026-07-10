# PORT: IDE splash screen + Help->About box with live self-info (for YADFOT)

> **STATUS: SPLASH CONFIRMED (2026-07-10); About-rendering + swap-refresh still
> unconfirmed.** drag-lint shipped this feature in **v1.0.0-alpha (Batch G)** and
> re-shipped the BPL under **v1.1.0-alpha**. The user has now confirmed the
> **splash paints on IDE startup** in a running RAD Studio 37. The **About-dialog
> entry** has NOT yet been visually confirmed -- the user initially looked for an
> "About menu" and (correctly) found none, because the entry lives INSIDE the
> IDE's own Help->About dialog (see the WHERE-THIS-APPEARS callout in section 0),
> not as a menu item. Until someone opens Help->About and sees the YADFOT/drag-lint
> plugin entry render (and its live/error self-info memo), treat the About entry
> and especially the "swap-refresh" behavior (section 4) as UNPROVEN; a
> menu-dialog fallback is documented. The splash port is safe to implement now;
> validate the About entry against the IDE About dialog once implemented.

This is the sibling of `PORT-tools-options-page.md`. It ports drag-lint's IDE
splash + About-box-with-live-engine-self-info to **YADFOT** (YADF's RAD Studio
design-time package). Reference implementation:
`C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.About.pas` +
`...\DragLint.Plugin.Wizard.pas` + the `info` verb in `...\src\cli\DRagLint.CLI.pas`.

Everything here is proven on RAD Studio 37 (Delphi 13). YADFOT's structure maps
1:1: `YADFOT.Wizard.pas` (the `Register` proc), `YADFOT.dpk`/`.res`, and YADF's
own `yadf.exe` (the CLI the About box will query).

---

## 0. What you get

- A **splash-screen entry** (your logo + `YADFOT (MIT) <version>`) painted by the
  IDE while it initializes -- registered in `Register`, zero startup cost.
- An entry in the **IDE's own "About" dialog** (logo + MIT + version + description)
  that, when viewed, shows **live self-info fetched from `yadf.exe`** on a background
  thread (never blocks startup), or a **structured diagnostic error block** if the
  exe call fails.
  > **WHERE THIS APPEARS (important -- avoids a "where is the About menu?" surprise):**
  > `IOTAAboutBoxServices.AddPluginInfo` does NOT add a standalone "About" menu item
  > or a `Help > About > YADFOT` submenu. It registers YADFOT as a plugin entry
  > INSIDE RAD Studio's existing About dialog. To see it: **Help -> About Embarcadero
  > RAD Studio**, then find/scroll to the **YADFOT** entry in that dialog's installed-
  > plugins list. (Confirmed in drag-lint: the splash paints on startup, and the
  > entry lives in the IDE About dialog -- there is intentionally no custom About menu.)
- A new **`yadf info --json`** verb (if yadf.exe doesn't already have one) that
  feeds the About box.

---

## 1. The load-bearing timing rule (read this first)

`Register` runs **during IDE initialization**. **NEVER call the exe there** -- it
would stall IDE startup. So:

| Surface | Registered | Exe call? | Version source |
|---|---|---|---|
| Splash | in `Register` (startup) | **NO** | static version const |
| About *entry* | in `Register` (startup) | **NO** | static version const |
| About *memo content* | background thread after startup | **YES**, backgrounded | live `yadf info --json` |

Measured cost of a one-shot self-info exe call: **~170-300ms** -- fine on a
background thread, unacceptable synchronously at startup.

---

## 2. The icon resource (`.rc` -> `.res` -> `{$R}`)

1. Put a 32x32 (or 24x24) `.ico` next to `YADFOT.Wizard.pas`, e.g. `YADFOT.ico`.
   (drag-lint reused the Micronite logo; use YADF's own.)
2. Create `YADFOTSplash.rc` (strict ASCII, CRLF):
   ```
   SPLASH_ICON_1 ICON "YADFOT.ico"
   ```
3. Compile it with the RAD Studio resource compiler (present in the Studio bin):
   ```
   "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\brcc32.exe" YADFOTSplash.rc
   ```
   -> produces `YADFOTSplash.RES` (brcc32 emits an UPPERCASE extension; the `{$R}`
   below resolves it case-insensitively on Windows).
4. In `YADFOT.Wizard.pas`, in the **implementation** section, add:
   ```pascal
   {$R 'YADFOTSplash.res'}
   ```
   (This is an ADDITIONAL named resource; it coexists with the package's
   auto-generated `{$R *.res}`.)
5. Load it at runtime via `LoadImage(HInstance, 'SPLASH_ICON_1', IMAGE_ICON, 0, 0, LR_DEFAULTSIZE)`.

**Verify** the resource actually linked: after the BPL build, grep the `.bpl` for
the wide-char string `S.P.L.A.S.H._.I.C.O.N._.1` (bytes) -- if present, `LoadImage`
will find it.

---

## 3. Splash registration (in `Register`)

```pascal
uses
  ToolsAPI, DesignIntf,          // DesignIntf: ForceDemandLoadState/dlDisable live HERE, not ToolsAPI!
  Winapi.Windows, Vcl.Graphics;

var
  GIconBmp: TBitmap = nil;       // retained: the splash + About need the handle to live

procedure RegisterYadfotAbout;   // call this from Register
var HIco: HICON; Icon: TIcon; ABS: IOTAAboutBoxServices;
begin
  // 1. build the bitmap once
  HIco := LoadImage(HInstance, 'SPLASH_ICON_1', IMAGE_ICON, 0, 0, LR_DEFAULTSIZE);
  if HIco <> 0 then
  begin
    Icon := TIcon.Create;
    try Icon.Handle := HIco; GIconBmp := TBitmap.Create; GIconBmp.Assign(Icon);
    finally Icon.Free; end;
  end;
  // 2. splash (guard each OTA step so a nil service never breaks Register)
  try
    if Assigned(SplashScreenServices) and Assigned(GIconBmp) then
      SplashScreenServices.AddPluginBitmap('YADFOT', GIconBmp.Handle, False, 'MIT', YADFOT_VERSION);
  except end;
  // 3. About entry (static; live info swapped in later)
  try
    if Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) and Assigned(GIconBmp) then
      GAboutIndex := ABS.AddPluginInfo('YADFOT', StaticDescription, GIconBmp.Handle, False, 'MIT', YADFOT_VERSION);
  except end;
  // 4. eager-load so Register runs at startup for the splash (from DesignIntf)
  try ForceDemandLoadState(dlDisable); except end;
  // 5. kick the background self-info fetch (section 4)
  StartBackgroundSelfInfoFetch;
end;
```

**`AddPluginBitmap(caption, bitmap, isUnregistered, licenseStatus, sku)`** and
**`AddPluginInfo(title, description, image, isUnregistered, licenseStatus, sku): Integer`**
-- put `'MIT'` in `licenseStatus` (shown in parens on the splash / as a label in
About) and the version in `sku`. Save the `AddPluginInfo` return in
`GAboutIndex: Integer` (init `-1`) for teardown.

**GOTCHA (cost us a build):** `ForceDemandLoadState` / `dlDisable` are in
**`DesignIntf`**, NOT `ToolsAPI`. Add `DesignIntf` to uses.

---

## 4. About memo: background live-fetch + swap + error block

The About memo is a fixed string set at `AddPluginInfo` time; the OTA does NOT
call back on selection. So fetch once in the background after startup and swap the
entry's text:

```pascal
procedure StartBackgroundSelfInfoFetch;
begin
  TThread.CreateAnonymousThread(
    procedure
    var Out: string; ExitCode: Integer; Block: string;
    begin
      // ALL work here is subprocess + strings -- NO OTA calls on this thread
      ExitCode := RunAndCaptureStdout('"' + YadfExe + '" info --json', Out, 8000);
      if (ExitCode = 0) and (Trim(Out) <> '') and ParsesAsJson(Out) then
        Block := FormatLiveBlock(Out)          // engine version/build/caps + log path
      else
        Block := FormatErrorBlock(YadfExe, ExitCode, Out);  // see below
      TThread.Queue(nil,                        // marshal the OTA swap to the MAIN thread
        procedure
        var ABS: IOTAAboutBoxServices;
        begin
          if Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) and (GAboutIndex >= 0) then
          begin
            ABS.RemovePluginInfo(GAboutIndex);
            GAboutIndex := ABS.AddPluginInfo('YADFOT', StaticDescWithout"querying" + sLineBreak + Block,
                                             GIconBmp.Handle, False, 'MIT', YADFOT_VERSION);
          end;
        end);
    end).Start;   // returns immediately -- startup is never blocked
end;
```

**Error block** (this is what makes About a self-diagnosing surface -- and lets you
delete any "Test Connection" debug item):
```
Engine self-info UNAVAILABLE -- diagnostic:
  resolved exe path: <YadfExe>
  <reason: "exe not found at resolved path" | "spawn/exit code <n>" |
           "empty response (timeout or no output)" | "unparseable response: <first 120 chars>">
Plugin log: <YADFOT log path>
```

> **UNVERIFIED (live-only):** whether `RemovePluginInfo` + re-`AddPluginInfo`
> AFTER startup actually refreshes the *visible* About entry in RAD 37 could not
> be confirmed headlessly. drag-lint implements the swap as above and gates it on
> a live smoke test. **Fallback if the swap does not refresh:** keep the About
> entry static (icon+MIT+version+description) and expose the live block + error
> block via a **Tools->YADFOT menu item "About / Engine info..."** that runs
> `yadf info --json` on click (backgrounded, ~200ms) and shows the result in a
> dialog. Either path delivers "live exe info + error surfacing, no startup
> block." Wait for drag-lint's smoke result before choosing.

**Thread-safety rules that matter:** the background thread does ONLY subprocess +
string work; ALL OTA calls happen on the main thread inside `TThread.Queue`;
resolve `IOTAAboutBoxServices` FRESH inside the queued block (never capture an OTA
interface across the thread boundary). `GIconBmp.Handle` is read on the main
thread only.

---

## 5. Teardown (idempotent)

```pascal
procedure UnregisterYadfotAbout;
var ABS: IOTAAboutBoxServices;
begin
  if Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) and (GAboutIndex >= 0) then
    try ABS.RemovePluginInfo(GAboutIndex); except end;
  GAboutIndex := -1;
  FreeAndNil(GIconBmp);
end;
```
Call it from the wizard's `Destroyed` (alongside your other `Unregister*` calls)
AND from the unit `finalization` as a backstop -- the `GAboutIndex >= 0` guard
makes the double-call safe. (Splash entries aren't removable -- that's fine,
they're startup-only.) This mirrors the teardown discipline from
`PORT-tools-options-page.md`.

---

## 6. The `yadf info --json` verb

If `yadf.exe` has no self-info verb, add one (drag-lint's `DoInfo` mirrors its
`schema` verb). Emit a stable schema:
```json
{ "schema": "info/1", "name": "yadf", "version": "...", "build_date": "...",
  "license": "MIT", "description": "...", "capabilities": {...},
  "exe_path": "...", "platform": "Win64" }
```

**build_date -- CRITICAL GOTCHA:** derive it from **`FileAge(ParamStr(0))`** (the
exe's own file timestamp), formatted `yyyy-mm-dd hh:nn:ss`.
**Do NOT use `{$I %DATE%}`** -- it does NOT compile in this toolchain (`dcc32`
reads it as an include directive: `F1026 File not found: '%DATE%.pas'`). This was
verified on Studio 37. The `FileAge` approach is the same idiom YADF/drag-lint
already use for their "BPL built <time>" tags.

Give the verb a `--json` form (what the About box calls) and a plain-text form
(human-friendly), and make it read-only (no side effects, no DB writes).

---

## 7. Wire-up checklist (YADFOT)

- [ ] Add `YADFOT.About.pas` (or fold into `YADFOT.Wizard.pas`) with
      `RegisterYadfotAbout` / `UnregisterYadfotAbout`.
- [ ] Add the unit to `YADFOT.dpk` **contains** AND `YADFOT.dproj` **DCCReference**
      (a unit in DCCReference but NOT in .dpk contains + unreferenced does NOT
      compile -- see `PORT-tools-options-page.md`'s lesson).
- [ ] Call `RegisterYadfotAbout` in `Register`; `UnregisterYadfotAbout` in
      `Destroyed` + `finalization`.
- [ ] Add the icon `.rc`, compile to `.res`, add `{$R 'YADFOTSplash.res'}`.
- [ ] Ensure ONE static version const (avoid the drift trap: drag-lint shipped a
      1.0.0 with a stale `v0.40.5` literal hiding in a second copy -- grep the
      whole plugin for version-string literals and unify them).
- [ ] Add `yadf info --json` if absent (FileAge build-date, not `%DATE%`).
- [ ] Build the BPL with **RAD Studio CLOSED** (it locks the BPL).
- [ ] Live smoke: splash on startup; Help->About shows icon+MIT+version+live
      engine block; rename yadf.exe -> the error block appears.

---

## 8. Reference commits (drag-lint Batch G, v1.0.0-alpha)

- `e646cf9` -- `info [--json]` verb (FileAge build-date; do-not-use-%DATE%).
- `e4a2ec3` -- icon `.rc`/`.res` + `{$R}` wiring.
- `76b3203` -- `DragLint.Plugin.About.pas` (splash + About + backgrounded live
  self-info + error block).
- `ca2a7e9` -- wizard Register/teardown wiring + version-const bump.
- `56333c6` -- removal of the now-redundant "Test Connection" debug item.
- `aedd0bf` -- the stale-version-literal fix (the drift-trap lesson above).

Full design/plan: drag-lint
`docs/superpowers/specs|plans/2026-07-09-batch-g-ide-splash-about-selfinfo*`.
