{
  YADFOT -- YADF Open Tools
  Delphi IDE wizard that formats the current code buffer using YADF.

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Wraps YADF's FormatSource() entry point. The YADF source units
  (YADF.Tokens, YADF.Options, YADF.Groups, YADF.Layout) are compiled
  into this package as-is. No YADF source is modified.

  Encoding model
  --------------
  The IDE editor exposes buffer contents as UTF-8 bytes through
  IOTAEditReader/IOTAEditWriter, regardless of the file's on-disk
  encoding. YADFOT decodes that to a Delphi Unicode string, passes
  it through FormatSource, encodes the result back to UTF-8, and
  writes it via an undoable editor writer. The CLI's Encoding option
  (ANSI/UTF-8/UTF-16) only affects file I/O, so it is intentionally
  ignored by YADFOT.
}

unit YADFOT.Wizard;

interface

uses
  ToolsAPI;

/// <summary><!-- drag-lint:auto -->--- Register ----------------------------------------------------------</summary>
/// <remarks>
/// <!-- drag-lint:auto -->Register is the entry point the IDE invokes when the design-time package loads. It hands the IDE one IOTAWizard (the Tools-menu item) and one IOTAKeyboardBinding (the Ctrl+Shift+Alt+F shortcut). Both indices are stored so finalization can hand them back cleanly on package unload. Services are queried via Supports(): an interface `as` cast raises EIntfCastError when the service is unsupported (so the old `KS &lt;&gt; nil` check after `as` could never fire), and yields a nil interface when BorlandIDEServices itself is nil -- Supports handles both, tolerating an absent service instead of failing registration.
/// <!-- drag-lint:auto BEGIN -->
/// Calls: AddKeyboardBinding, AddWizard, Supports, YADFOT.Wizard.RegisterYadfotAbout
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Register;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.IniFiles
  , System.UITypes
  , Winapi.Windows        // LoadImage / HICON for the splash bitmap
  , Vcl.Dialogs
  , Vcl.Menus
  , Vcl.Graphics          // TIcon / TBitmap for the splash + About image
  , DesignIntf            // ForceDemandLoadState / dlDisable live HERE, not ToolsAPI
  , YADF.Options
  , YADF.Layout
  , YADFOT.Options
  ;

// Named icon resource for the IDE splash-screen + About-box entry (compiled from
// YADFOTSplash.rc -> YADFOTSplash.RES via brcc32). This is an ADDITIONAL resource
// alongside the package's auto-generated {$R *.res}; the case-insensitive Windows
// resolver matches the uppercase .RES brcc32 emits.
{$R 'YADFOTSplash.res'}

// Single source of truth for the plugin version string (shared with the CLI /
// YADFSetup). Avoids the drift trap: one const, no stray literals.
{$I YADF.Version.inc}

type
  // IOTAMenuWizard adds a single item ("YADFOT: Format Current Buffer")
  // to the IDE's Tools menu. Selecting it invokes Execute(), which calls
  // DoFormatCurrentBuffer.
  TYadfotMenuWizard = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  public
    // IOTAWizard
    function  GetIDString : string;
    function  GetName     : string;
    function  GetState    : TWizardState;
    procedure Execute;
    // IOTANotifier -- primary teardown hook. TNotifierObject.Destroyed is a
    // plain (non-virtual) method, so this re-declares it WITHOUT override;
    // the interface still binds to this class's own Destroyed.
    procedure Destroyed;
    // IOTAMenuWizard
    function  GetMenuText : string;
  end;

  // IOTAKeyboardBinding registers Ctrl+Shift+Alt+F as a global IDE
  // shortcut that invokes the same format action. btPartial means our
  // binding extends the active keymap rather than replacing it, so the
  // rest of the user's bindings stay intact.
  TYadfotKeyboardBinding = class(TNotifierObject, IOTAKeyboardBinding)
  public
    procedure FormatBufferAction(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
    procedure FormatBufferActionR(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
    function  GetBindingType: TBindingType;
    function  GetDisplayName: string;
    function  GetName       : string;
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
  end;

const
  WizardIDString  = 'YADFOT.FormatCurrentBuffer';
  WizardMenuText  = 'YADFOT: Format Current Buffer';
  WizardLongName  = 'YADFOT - YADF Open Tools';
  // Splash / About-box copy. The version comes from YADF.Version.inc so there is
  // exactly one source of truth across the CLI, YADFSetup, and this package.
  SplashCaption   = 'YADFOT';
  AboutLicense    = 'MPL-2.0';   // must match the repo LICENSE / unit headers
  AboutDescription =
    'YADFOT -- YADF Open Tools.' + sLineBreak +
    'Formats the current editor buffer with YADF (Yet Another Delphi Formatter).' +
    sLineBreak +
    'Tools menu: "YADFOT: Format Current Buffer"; shortcuts Ctrl+Shift+Alt+F (F profile) ' +
    'and Ctrl+Shift+Alt+R (R profile). Settings: Tools > Options > Third Party > YADF.';

// Indices returned by IOTAWizardServices.AddWizard and
// IOTAKeyboardServices.AddKeyboardBinding. Both are kept so finalization
// can hand them back; -1 means "not registered" (Register failed or was
// never called).
var
  GKeyboardBindingIndex: Integer = -1;
  GWizardIndex         : Integer = -1;
  // Splash / About-box state. GIconBmp is retained for the lifetime of the
  // package because both the splash and the About entry reference its handle.
  // GAboutIndex is the AddPluginInfo slot, handed back on teardown (-1 = none).
  GIconBmp   : TBitmap = nil;
  GAboutIndex: Integer = -1;

// Forward-declared so the wizard's Destroyed (defined above the body) can call
// the teardown; the full bodies live down by Register.
procedure RegisterYadfotAbout; forward;
procedure UnregisterYadfotAbout; forward;

// --- Options loading ----------------------------------------------------

// Delegates to the shared, table-driven loader in YADF.Options so the
// wizard reads EXACTLY the same [Format] keys as the CLI and YADFSetup.
// (This also picks up AlignMatchingShapes / AlignShapeMinAnchors /
// AlignCommentMaxShift, which the previous hand-maintained reader here had
// drifted and silently ignored.) The Encoding field applies only on the
// FormatFileOnDisk path (form units), where it follows the CLI's contract
// (ANSI = preserve detected, utf8/utf16 = convert); the editor-buffer path
// writes through the IDE (UTF-8) and ignores it, which is harmless.
procedure LoadIniDefaults(var AOpts: TYadfOptions; const AIniPath: string);
begin
  if (AIniPath = '') or (not FileExists(AIniPath)) then Exit;
  AOpts:= LoadOptionsFromIni(AIniPath);
end; // procedure

// Resolve the F-profile options for the default (Ctrl+Shift+Alt+F / Tools-menu)
// format action. The F profile is located EXACTLY as YADFSetup and the IDE
// Options page locate it: %APPDATA%\YADF\profiles.ini names the F file
// ([Profiles]F=<name>, default 'yadf.ini'); ResolveProfileIniPath turns that
// name into a full path under %APPDATA%\YADF (an absolute name passes through).
// No project-tree walk: the file the user edits and the file that formats are
// the same, so saved settings always take effect. If the resolved F file does
// not exist yet (fresh install), EnsureIniExists materialises the commented
// default template there before loading -- so first-run formatting uses the
// documented defaults, and the file is then editable from YADFSetup/the page.
function ResolveOptions: TYadfOptions;
var
  IniPath: string;
begin
  Result := DefaultOptions;
  IniPath:= ResolveProfileIniPath(LoadProfiles.F);
  if IniPath = '' then
    IniPath:= SharedAppDataIniPath;   // defensive: F is never '' (defaults to yadf.ini)
  EnsureIniExists(IniPath);
  LoadIniDefaults(Result, IniPath);
end;

// --- Buffer access ------------------------------------------------------

// Whitelist of extensions YADF can sensibly format. .inc is included
// because it commonly contains Pascal fragments included into a unit.
// Anything else (.dfm/.fmx form streams, .res, .txt scratch buffers,
// project options pages...) is refused upstream.
function IsCodeBufferExt(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext:= LowerCase(ExtractFileExt(AFileName));
  Result:= (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc');
end;

// Returns the IOTASourceEditor for the buffer that currently has focus,
// or nil if the active view is not a code editor (typically a form
// designer, project options page, welcome page, etc.). We deliberately
// do NOT walk the active module to find a sibling .pas behind a form
// designer -- "format what I'm looking at" should refuse rather than
// silently reach for an adjacent buffer.
function GetActiveSourceEditor(out AFileName: string): IOTASourceEditor;
var
  EditorServices: IOTAEditorServices;
  TopView       : IOTAEditView;
  Buffer        : IOTAEditBuffer;
begin
  Result   := nil;
  AFileName:= '';
  EditorServices:= BorlandIDEServices as IOTAEditorServices;
  if EditorServices = nil then Exit;
  TopView:= EditorServices.TopView;
  if TopView = nil then Exit;
  Buffer:= TopView.Buffer;
  if Buffer = nil then Exit;
  if not Supports(Buffer, IOTASourceEditor, Result) then Exit;
  AFileName:= Buffer.FileName;
end;

// Reads the entire editor buffer as a Unicode string. The IDE returns
// chunks of UTF-8-encoded bytes (cast as AnsiChar for the legacy
// IOTAEditReader.GetText signature), and we accumulate them into a TBytes
// before decoding. Reading in 4 KB chunks keeps memory churn bounded
// without forcing many round-trips through the interface; the loop
// terminates the first time the IDE returns fewer bytes than requested.
function ReadEditorText(const ASource: IOTASourceEditor): string;
const
  ChunkSize = 4096;
var
  Reader   : IOTAEditReader;
  Got      : Integer;
  Pos      : Integer;
  Chunk    : array[0..ChunkSize - 1] of AnsiChar;
  Utf8Bytes: TBytes;
  CurLen   : Integer;
begin
  Reader:= ASource.CreateReader;
  SetLength(Utf8Bytes, 0);
  CurLen:= 0;
  Pos   := 0;
  repeat
    Got:= Reader.GetText(Pos, @Chunk[0], ChunkSize);
    if Got > 0 then
    begin
      SetLength(Utf8Bytes, CurLen + Got);
      Move(Chunk[0], Utf8Bytes[CurLen], Got);
      Inc(CurLen, Got);
      Inc(Pos   , Got);
    end;
  until Got < ChunkSize;
  if CurLen = 0 then Exit('');
  Result:= TEncoding.UTF8.GetString(Utf8Bytes, 0, CurLen);
end;

// Replaces the entire editor buffer with AText. The cast
// `UTF8String(AText)` is an implicit Unicode->UTF-8 RTL conversion, so
// the resulting bytes are exactly what IOTAEditWriter.Insert expects.
// CreateUndoableWriter (vs. CreateWriter) places the edit on the IDE's
// undo stack, so Ctrl+Z reverts the format as a single step.
procedure WriteEditorText(const ASource: IOTASourceEditor; const AText: string);
var
  Writer: IOTAEditWriter;
  Utf8  : UTF8String;
begin
  Writer:= ASource.CreateUndoableWriter;
  Writer.DeleteTo(MaxInt);
  if AText = '' then Exit;
  Utf8:= UTF8String(AText);
  Writer.Insert(PAnsiChar(Utf8));
end;

// Encoding detection lives in YADF.Options.DetectSourceEncoding -- ONE
// detector shared with the CLI, so both hosts decode and re-encode the same
// file identically.

// Lowest unused `<file>.BCK<n>` sibling name (mirrors the YADF CLI --b scheme).
function NextSiblingBackupName(const AFile: string): string;
var
  Base: string;
  Dir : string;
  n   : Integer;
begin
  Dir := ExtractFilePath(AFile);
  Base:= ExtractFileName(AFile);
  n:= 1;
  repeat
    Result:= TPath.Combine(Dir, Base + '.BCK' + IntToStr(n));
    if not TFile.Exists(Result) then Exit;
    Inc(n);
  until False;
end;

// Copy AFile aside before it is overwritten -- same scheme as the CLI's --b:
// a timestamped `.bak` under ABackupDir when set, else a `<file>.BCK<n>`
// sibling. The form-reload path ALWAYS calls this, so a form unit can be
// restored from its `.BCK` if the reformat or the IDE reload goes wrong.
procedure BackupOriginalFile(const AFile: string; const ABackupDir: string);
var
  Stamp : string;
  Target: string;
begin
  if Trim(ABackupDir) = '' then
  begin
    TFile.Copy(AFile, NextSiblingBackupName(AFile), True);
    Exit;
  end;
  if not TDirectory.Exists(ABackupDir) then
    TDirectory.CreateDirectory(ABackupDir);
  Stamp:= FormatDateTime('yyyymmdd-hhnnss', Now);
  Target:= TPath.Combine(ABackupDir, ExtractFileName(AFile) + '.' + Stamp + '.bak');
  TFile.Copy(AFile, Target, True);
end;

// Format AFileName in place ON DISK (read -> FormatSource -> write), preserving
// the file's encoding. Returns True when the content changed (and was written).
// This is exactly what the YADF CLI does to a file: it deliberately does NOT go
// through the live editor buffer, so an open Form Designer is never desynced.
// A `.BCK` backup of the ORIGINAL is always written first (the file is about to
// be overwritten on disk; the in-buffer path keeps Ctrl+Z, this one cannot).
// Used only on the form-reload path below.
function FormatFileOnDisk(const AFileName: string; const AOpts: TYadfOptions): Boolean;
var
  Bytes    : TBytes;
  Enc      : TEncoding;
  WriteEnc : TEncoding;
  WriteBom : Boolean;
  PreLen   : Integer;
  OutBytes : TBytes;
  Original : string;
  Formatted: string;
begin
  Bytes    := TFile.ReadAllBytes(AFileName);
  DetectSourceEncoding(Bytes, Enc, PreLen);
  Original := Enc.GetString(Bytes, PreLen, Length(Bytes) - PreLen);
  Formatted:= FormatSource(Original, AOpts);
  Result   := Formatted <> Original;
  if Result then
  begin
    // Honour the INI Backup option (same as the CLI / --b): when on, copy the
    // original aside before overwriting. Set it once in YADFSetup and every
    // form format keeps a .BCK without passing anything per-call.
    if AOpts.Backup then
      BackupOriginalFile(AFileName, AOpts.BackupDir);
    // Same write contract as the CLI (LoadFile/SaveFile): Encoding=ANSI means
    // "preserve what was detected" -- re-emit in the detected encoding with
    // the original BOM-ness; an explicit utf8/utf16 option is a conversion
    // request (+BOM). Before this, the wizard always preserved while the CLI
    // converted, so identical settings produced different bytes per host.
    if AOpts.Encoding = encANSI then
    begin
      WriteEnc:= Enc;
      WriteBom:= PreLen > 0;
    end
    else
    begin
      WriteEnc:= EncodingOf(AOpts.Encoding);
      WriteBom:= True;
    end;
    OutBytes:= WriteEnc.GetBytes(Formatted);
    if WriteBom then
      OutBytes:= WriteEnc.GetPreamble + OutBytes;
    TFile.WriteAllBytes(AFileName, OutBytes);
  end;
end;

// True when the module that owns AEditor also exposes a Form Designer
// surface (an IOTAFormEditor among its module-file editors) -- i.e. the
// .pas is paired with a .dfm/.fmx (a VCL/FMX form or data module). The
// designer holds a live source-position map of the form class
// declaration; YADFOT replaces the whole buffer, which invalidates that
// map, and the IDE then access-violates inside
// VCLFormDesigner.TVCLRootDesigner.DoSave on the next File > Save All.
// The form editor is instantiated for any open form unit regardless of
// which tab is focused, so this is the precise dangerous condition.
function ModuleHasFormDesigner(const AEditor: IOTASourceEditor): Boolean;
var
  FE: IOTAFormEditor;
  i : Integer;
  M : IOTAModule;
begin
  Result:= False;
  if AEditor = nil then Exit;
  M:= AEditor.Module;
  if M = nil then Exit;
  for i:= 0 to M.GetModuleFileCount - 1 do
    if Supports(M.GetModuleFileEditor(i), IOTAFormEditor, FE) then Exit(True);
end;

// Form / data-module path. Replacing the live editor buffer would desync the
// open Form Designer's source-position map (-> AV in TVCLRootDesigner.DoSave on
// the next Save All), so instead we perform the IDE reload handshake AUTOMATICALLY:
//   1. Save the module (flush buffer + any pending designer edits to disk) --
//      safe, because we have NOT touched the buffer, so the designer is still
//      in sync at this point.
//   2. Format the file ON DISK (never the buffer), exactly like the CLI.
//   3. Module.Refresh(True) reloads from disk, so the editor AND the designer
//      rebuild from clean source -- no stale map, so Save All cannot AV.
// The trade-off vs. the in-buffer path: this format is not on the undo stack.
procedure FormatFormUnitViaReload(const AEditor: IOTASourceEditor; const AFileName: string;
  const AOpts: TYadfOptions);
var
  M: IOTAModule;
begin
  M:= AEditor.Module;
  if M = nil then Exit;
  if not FileExists(AFileName) then
  begin
    MessageDlg('YADFOT: save the unit to disk first, then format it.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  // A form / data-module unit formats seamlessly -- no confirm prompt. AOpts is
  // resolved by the caller (profile F or R), so R applies on forms too. We save
  // the unit, write a .BCK backup (when Backup=true), format the file on disk,
  // and reload the module so the Form Designer rebuilds from a clean
  // source-position map (the original is recoverable from the .BCK).
  if not M.Save(False, True) then
  begin
    MessageDlg('YADFOT: could not save the unit before formatting; aborted.',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  try
    if not FormatFileOnDisk(AFileName, AOpts) then Exit; // no change -> leave designer alone
  except
    on E: Exception do
    begin
      MessageDlg('YADFOT: format failed.' + sLineBreak + E.ClassName + ': ' + E.Message,
        mtError, [mbOK], 0);
      Exit;
    end;
  end;
  M.Refresh(True);
end;

// --- The action ---------------------------------------------------------

// Sole entry point for "format the current buffer". Both the Tools menu
// item and the keyboard binding call this. Flow:
//   1. Locate the source editor that owns the focused edit view.
//   2. Refuse non-code buffers (form designer, project options, ...) and
//      read-only buffers.
//   3. Resolve options from the nearest yadf.ini (or defaults).
//   4. Read editor text -> FormatSource -> write back.
//   5. Skip the write if formatting was a no-op, so we don't dirty the
//      buffer or add an empty entry to the IDE's undo stack.
// The ENTIRE flow runs inside one try/except: this procedure is invoked
// straight from the IDE's key-dispatch / menu-dispatch, and any exception
// escaping it (options I/O, OTA buffer write, module save/refresh -- not
// just the formatter itself) would unwind through the IDE's own stack and
// can destabilise it. Everything surfaces as a dialog instead.
procedure DoFormatCurrentBuffer(AProfileR: Boolean = False);
var
  Editor   : IOTASourceEditor;
  Buffer   : IOTAEditBuffer;
  FileName : string;
  Opts     : TYadfOptions;
  Original : string;
  Formatted: string;
  RIni     : string;
begin
  try
    Editor:= GetActiveSourceEditor(FileName);
    if Editor = nil then
    begin
      MessageDlg('YADFOT: no source editor is active.' + sLineBreak +
        'Open a .pas / .dpr / .dpk / .inc file and try again.',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    if not IsCodeBufferExt(FileName) then
    begin
      MessageDlg('YADFOT: active buffer is not a Pascal source file.' + sLineBreak +
        'File: ' + FileName + sLineBreak +
        'Supported extensions: .pas .dpr .dpk .inc',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    // Refuse read-only buffers politely. Without this, the failure happens
    // deep inside IOTAEditWriter.Insert (or as a silent no-op) instead of
    // telling the user why nothing was formatted.
    if Supports(Editor, IOTAEditBuffer, Buffer) and Buffer.IsReadOnly then
    begin
      MessageDlg('YADFOT: the active buffer is read-only.' + sLineBreak +
        'File: ' + FileName + sLineBreak +
        'Clear the read-only state and try again.',
        mtInformation, [mbOK], 0);
      Exit;
    end;

    // Resolve options (profile-aware) BEFORE choosing the form-reload vs in-buffer
    // path, so Ctrl+Shift+Alt+R uses the R profile INI on a form unit too. BOTH
    // shortcuts now resolve their INI the SAME way YADFSetup and the Options page
    // do -- via %APPDATA%\YADF\profiles.ini (no project-tree walk): F uses the
    // profiles.ini [Profiles]F entry, R uses the R entry. This makes "edit the
    // settings, then format" always agree on one file; a stray project-local
    // yadf.ini no longer silently shadows the user's saved F profile.
    if AProfileR then
    begin
      RIni:= ResolveProfileIniPath(LoadProfiles.R);
      if (RIni = '') or (not FileExists(RIni)) then
      begin
        MessageDlg('YADFOT: no second (R) profile is configured.' + sLineBreak +
          'Open YADFSetup, click an INI in the Profiles list and press R to assign ' +
          'it to Ctrl+Shift+Alt+R.',
          mtInformation, [mbOK], 0);
        Exit;
      end;
      Opts:= DefaultOptions;
      LoadIniDefaults(Opts, RIni);
    end
    else
      Opts:= ResolveOptions;   // F profile via profiles.ini (materialised if absent)

    // A form / data-module unit has a live Form Designer whose source-position map
    // a buffer swap would corrupt. Take the safe disk-reload handshake path (using
    // the options resolved above) instead of the in-buffer write below.
    if ModuleHasFormDesigner(Editor) then
    begin
      FormatFormUnitViaReload(Editor, FileName, Opts);
      Exit;
    end;

    Original := ReadEditorText(Editor);
    Formatted:= FormatSource(Original, Opts);
    if Formatted = Original then Exit;
    WriteEditorText(Editor, Formatted);
  except
    on E: Exception do
      MessageDlg('YADFOT: format failed.' + sLineBreak +
        E.ClassName + ': ' + E.Message,
        mtError, [mbOK], 0);
  end;
end;

// --- IOTAWizard / IOTAMenuWizard ---------------------------------------

function TYadfotMenuWizard.GetIDString: string;
begin
  Result:= WizardIDString;
end;

function TYadfotMenuWizard.GetName: string;
begin
  Result:= WizardLongName;
end;

function TYadfotMenuWizard.GetState: TWizardState;
begin
  Result:= [wsEnabled];
end;

function TYadfotMenuWizard.GetMenuText: string;
begin
  Result:= WizardMenuText;
end;

procedure TYadfotMenuWizard.Execute;
begin
  DoFormatCurrentBuffer;
end;

procedure TYadfotMenuWizard.Destroyed;
begin
  // Fires during IDE shutdown / package unload, BEFORE the BPL code segment is
  // dropped -- the primary hook that strips the options page so no IDE list
  // keeps a dangling interface into our vanishing vtable. Idempotent; safe
  // alongside the YADFOT.Options finalization (which runs later in shutdown).
  try UnregisterYADFOptions;  except end;
  // Strip the About-box entry + free the retained icon here too (primary hook,
  // before the code segment is dropped); the finalization below is a backstop.
  try UnregisterYadfotAbout;  except end;
end;

// --- IOTAKeyboardBinding (Ctrl+Shift+Alt+F) ----------------------------

procedure TYadfotKeyboardBinding.FormatBufferAction(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
begin
  DoFormatCurrentBuffer(False);
  BindingResult:= krHandled;
end;

procedure TYadfotKeyboardBinding.FormatBufferActionR(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
begin
  DoFormatCurrentBuffer(True);
  BindingResult:= krHandled;
end;

function TYadfotKeyboardBinding.GetBindingType: TBindingType;
begin
  Result:= btPartial;
end;

function TYadfotKeyboardBinding.GetDisplayName: string;
begin
  Result:= 'YADFOT';
end;

function TYadfotKeyboardBinding.GetName: string;
begin
  Result:= 'YADFOT.KeyboardBinding';
end;

procedure TYadfotKeyboardBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  BindingServices.AddKeyBinding(
    [Vcl.Menus.ShortCut(Ord('F'), [ssCtrl, ssShift, ssAlt])],
    FormatBufferAction,
    nil);
  // Second shortcut: Ctrl+Shift+Alt+R formats with the R profile assigned in
  // YADFSetup. If none is assigned the action shows a one-line hint.
  BindingServices.AddKeyBinding(
    [Vcl.Menus.ShortCut(Ord('R'), [ssCtrl, ssShift, ssAlt])],
    FormatBufferActionR,
    nil);
end;

// --- Splash + About-box entry ------------------------------------------

// Load the embedded SPLASH_ICON_1 into GIconBmp (once). Both the splash and the
// About entry take the bitmap's HBITMAP handle, so the TBitmap is retained for
// the package's lifetime and freed only in UnregisterYadfotAbout. No-op (leaves
// GIconBmp nil) if the resource is missing, so a bitmap-less IDE still loads.
procedure EnsureSplashBitmap;
var
  HIco: HICON;
  Icon: TIcon;
begin
  if GIconBmp <> nil then Exit;
  HIco:= LoadImage(HInstance, 'SPLASH_ICON_1', IMAGE_ICON, 0, 0, LR_DEFAULTSIZE);
  if HIco = 0 then Exit;
  Icon:= TIcon.Create;
  try
    Icon.Handle:= HIco;          // Icon owns HIco now; freed with Icon
    GIconBmp:= TBitmap.Create;
    GIconBmp.Assign(Icon);       // rasterise the icon into a bitmap
  finally
    Icon.Free;
  end;
end;

// Register the IDE splash-screen bitmap and the static About-box entry. Called
// from Register (i.e. during IDE startup), so it does NO work that could stall
// startup -- no exe calls, just OTA registration with a static version string.
// Each OTA step is guarded so a nil/absent service never aborts registration.
// ForceDemandLoadState(dlDisable) makes the IDE load this package eagerly at
// startup, which is required for the splash to paint (a demand-loaded package
// would register too late to appear on the splash).
procedure RegisterYadfotAbout;
var
  ABS: IOTAAboutBoxServices;
begin
  EnsureSplashBitmap;
  // Splash bitmap (startup-only; not removable, which is fine).
  try
    if Assigned(SplashScreenServices) and Assigned(GIconBmp) then
      SplashScreenServices.AddPluginBitmap(
        SplashCaption, GIconBmp.Handle, False, AboutLicense, YADF_VERSION);
  except
    // A splash failure must never break package load.
  end;
  // About-box entry (static text; no live self-info in this build).
  try
    if Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) and Assigned(GIconBmp) then
      GAboutIndex:= ABS.AddPluginInfo(
        SplashCaption, AboutDescription, GIconBmp.Handle, False, AboutLicense, YADF_VERSION);
  except
  end;
  // Eager-load so Register runs at startup (needed for the splash to paint).
  try ForceDemandLoadState(dlDisable); except end;
end;

// Hand back the About-box entry and free the retained bitmap. Idempotent: the
// GAboutIndex >= 0 guard makes a double call (Destroyed + finalization) safe.
// Splash entries are startup-only and not removable -- that is expected.
procedure UnregisterYadfotAbout;
var
  ABS: IOTAAboutBoxServices;
begin
  if Supports(BorlandIDEServices, IOTAAboutBoxServices, ABS) and (GAboutIndex >= 0) then
    try ABS.RemovePluginInfo(GAboutIndex); except end;
  GAboutIndex:= -1;
  FreeAndNil(GIconBmp);
end;

// --- Register ----------------------------------------------------------

// Register is the entry point the IDE invokes when the design-time
// package loads. It hands the IDE one IOTAWizard (the Tools-menu item)
// and one IOTAKeyboardBinding (the Ctrl+Shift+Alt+F shortcut). Both
// indices are stored so finalization can hand them back cleanly on
// package unload. Services are queried via Supports(): an interface `as`
// cast raises EIntfCastError when the service is unsupported (so the old
// `KS <> nil` check after `as` could never fire), and yields a nil
// interface when BorlandIDEServices itself is nil -- Supports handles
// both, tolerating an absent service instead of failing registration.
procedure Register;
var
  WS: IOTAWizardServices;
  KS: IOTAKeyboardServices;
begin
  if Supports(BorlandIDEServices, IOTAWizardServices, WS) then
    GWizardIndex:= WS.AddWizard(TYadfotMenuWizard.Create);
  if Supports(BorlandIDEServices, IOTAKeyboardServices, KS) then
    GKeyboardBindingIndex:= KS.AddKeyboardBinding(TYadfotKeyboardBinding.Create);
  // Add the Tools > Options > Third Party > YADF page. Tolerate failure so a
  // missing options service never aborts the whole registration.
  try RegisterYADFOptions; except end;
  // Add the IDE splash bitmap + the static About-box entry. Guarded so a
  // missing splash/about service never aborts the whole registration.
  try RegisterYadfotAbout; except end;
end;

// Hand back the wizard slot and keyboard binding. Called from finalization;
// a separate procedure so it can have locals and so the call site can be
// exception-guarded. Supports() instead of `as`: in late IDE shutdown
// BorlandIDEServices can already be nil, and `as` on a nil interface yields
// nil (-> AV on the call) while an unsupported service raises EIntfCastError
// -- either one inside package finalization crashes the IDE on exit.
procedure UnregisterYadfotWizard;
var
  WS: IOTAWizardServices;
  KS: IOTAKeyboardServices;
begin
  if (GWizardIndex <> -1) and Supports(BorlandIDEServices, IOTAWizardServices, WS) then
    WS.RemoveWizard(GWizardIndex);
  GWizardIndex:= -1;
  if (GKeyboardBindingIndex <> -1) and Supports(BorlandIDEServices, IOTAKeyboardServices, KS) then
    KS.RemoveKeyboardBinding(GKeyboardBindingIndex);
  GKeyboardBindingIndex:= -1;
end;

initialization

// Hand back the wizard slot and keyboard binding when the package
// unloads (e.g. user uninstalls via Component > Install Packages). This
// is essential -- if the slot is left dangling, the next package load
// can leave duplicate menu items behind.
finalization
  try UnregisterYadfotWizard; except end;
  // Backstop for the About-box entry + retained icon (primary hook is the
  // wizard's Destroyed above). Idempotent via the GAboutIndex >= 0 guard.
  try UnregisterYadfotAbout; except end;

end.
