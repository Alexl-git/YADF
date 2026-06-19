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

procedure Register;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.IniFiles
  , System.UITypes
  , Vcl.Dialogs
  , Vcl.Menus
  , YADF.Options
  , YADF.Layout
  ;

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
  IniFileName     = 'yadf.ini';
  // v1.0.2: family-shared subdir so YADF.exe and YADFOT.bpl converge
  // on the same %APPDATA%\YADF\yadf.ini. Legacy %APPDATA%\YADFOT\ is
  // checked as a fallback so existing 1.0.1.x users don't lose their
  // config silently.
  AppDataSubDir   = 'YADF';
  LegacyAppDataSubDir = 'YADFOT';

// Indices returned by IOTAWizardServices.AddWizard and
// IOTAKeyboardServices.AddKeyboardBinding. Both are kept so finalization
// can hand them back; -1 means "not registered" (Register failed or was
// never called).
var
  GKeyboardBindingIndex: Integer = -1;
  GWizardIndex         : Integer = -1;

// --- Options loading ----------------------------------------------------

// TPath.GetHomePath on Windows resolves to %APPDATA% (Roaming), so the
// returned path is %APPDATA%\YADF\yadf.ini -- the family-shared per-user
// fallback when no project-local or source-local INI is found.
function AppDataIniPath: string;
var
  Dir: string;
begin
  Dir:= TPath.Combine(TPath.GetHomePath, AppDataSubDir);
  Result:= TPath.Combine(Dir, IniFileName);
end;

function LegacyAppDataIniPath: string;
var
  Dir: string;
begin
  Dir:= TPath.Combine(TPath.GetHomePath, LegacyAppDataSubDir);
  Result:= TPath.Combine(Dir, IniFileName);
end;

// Walk up from AStartDir looking for yadf.ini, stopping at the drive
// root or after 9 levels (whichever comes first). Returns '' if not
// found. The depth cap exists to keep the cost bounded on pathological
// inputs (e.g. UNC paths whose root is hard to detect); 9 levels is
// deep enough for any realistic project layout.
function FindIniFile(const AStartDir: string): string;
var
  Candidate: string;
  Dir      : string;
  i        : Integer;
  Parent   : string;
begin
  Dir:= AStartDir;
  for i:= 0 to 8 do
  begin
    if Dir = '' then Break;
    Candidate:= TPath.Combine(Dir, IniFileName);
    if TFile.Exists(Candidate) then Exit(Candidate);
    Parent:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or SameText(Parent, ExcludeTrailingPathDelimiter(Dir)) then Break;
    Dir:= IncludeTrailingPathDelimiter(Parent);
  end;
  Result:= '';
end;

// Delegates to the shared, table-driven loader in YADF.Options so the
// wizard reads EXACTLY the same [Format] keys as the CLI and YADFSetup.
// (This also picks up AlignMatchingShapes / AlignShapeMinAnchors /
// AlignCommentMaxShift, which the previous hand-maintained reader here had
// drifted and silently ignored.) The Encoding field is loaded but unused
// by the wizard -- it writes through the IDE editor buffer (UTF-8), not a
// file -- which is harmless.
procedure LoadIniDefaults(var AOpts: TYadfOptions; const AIniPath: string);
begin
  if (AIniPath = '') or (not FileExists(AIniPath)) then Exit;
  AOpts:= LoadOptionsFromIni(AIniPath);
end; // procedure

// Resolves the directory of the IDE's currently active project, or ''
// when no project is open. The IDE exposes projects via the loaded
// project group (IOTAProjectGroup), which lives among IOTAModuleServices.
// Modules; we look for the group first, then fall back to the first
// module that itself implements IOTAProject (covers the rare case where
// a lone project is loaded without a group wrapper).
function ActiveProjectDir: string;
var
  Project: IOTAProject;
  PG     : IOTAProjectGroup;
  MS     : IOTAModuleServices;
  i      : Integer;
  M      : IOTAModule;
begin
  Result:= '';
  MS:= BorlandIDEServices as IOTAModuleServices;
  if MS = nil then Exit;
  Project:= nil;
  for i:= 0 to MS.ModuleCount - 1 do
  begin
    M:= MS.Modules[i];
    if Supports(M, IOTAProjectGroup, PG) then
    begin
      Project:= PG.ActiveProject;
      Break;
    end;
  end;
  if (Project = nil) and (MS.ModuleCount > 0) then
    Supports(MS.Modules[0], IOTAProject, Project);
  if Project <> nil then
    Result:= ExtractFilePath(Project.FileName);
end;

// Four-tier INI lookup, first hit wins:
//   1. yadf.ini next to the source file (or any ancestor up to 9 deep)
//   2. yadf.ini next to the active .dproj/.dpr (or any ancestor)
//   3. legacy %APPDATA%\YADFOT\yadf.ini (1.0.1.x users; read-only)
//   4. shared %APPDATA%\YADF\yadf.ini (materialised from template if absent)
// If none exists, a commented template is created at tier 4.
function ResolveOptions(const ASourceFile: string): TYadfOptions;
var
  IniPath: string;
begin
  Result:= DefaultOptions;
  IniPath:= '';
  // 1. Walk up from the source file's folder.
  if ASourceFile <> '' then
    IniPath:= FindIniFile(ExtractFilePath(ASourceFile));
  // 2. Walk up from the active project's folder.
  if IniPath = '' then
    IniPath:= FindIniFile(ActiveProjectDir);
  // 3. Legacy %APPDATA%\YADFOT\yadf.ini (1.0.1.x users) -- read-only
  //    fallback so existing configs keep working without forcing a
  //    migration.
  if (IniPath = '') and TFile.Exists(LegacyAppDataIniPath) then
    IniPath:= LegacyAppDataIniPath;
  // 4. Shared per-user fallback %APPDATA%\YADF\yadf.ini. Family-wide
  //    location -- YADF.exe writes here on first run too. If nothing
  //    exists, materialise a fully-commented template.
  if IniPath = '' then
  begin
    IniPath:= AppDataIniPath;
    EnsureIniExists(IniPath);
  end;
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

// Detect a file's byte-order mark so the formatted text can be re-emitted in
// the SAME encoding. No BOM -> ANSI (the YADF / ORM3 default).
function DetectFileEncoding(const ABytes: TBytes): TEncoding;
begin
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Result:= TEncoding.UTF8
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    Result:= TEncoding.Unicode
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    Result:= TEncoding.BigEndianUnicode
  else
    Result:= TEncoding.ANSI;
end;

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
  Preamble : TBytes;
  Original : string;
  Formatted: string;
begin
  Bytes    := TFile.ReadAllBytes(AFileName);
  Enc      := DetectFileEncoding(Bytes);
  Preamble := Enc.GetPreamble;
  Original := Enc.GetString(Bytes, Length(Preamble), Length(Bytes) - Length(Preamble));
  Formatted:= FormatSource(Original, AOpts);
  Result   := Formatted <> Original;
  if Result then
  begin
    // Honour the INI Backup option (same as the CLI / --b): when on, copy the
    // original aside before overwriting. Set it once in YADFSetup and every
    // form format keeps a .BCK without passing anything per-call.
    if AOpts.Backup then
      BackupOriginalFile(AFileName, AOpts.BackupDir);
    TFile.WriteAllText(AFileName, Formatted, Enc);
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
procedure FormatFormUnitViaReload(const AEditor: IOTASourceEditor; const AFileName: string);
var
  M         : IOTAModule;
  Opts      : TYadfOptions;
  BackupNote: string;
begin
  M:= AEditor.Module;
  if M = nil then Exit;
  if not FileExists(AFileName) then
  begin
    MessageDlg('YADFOT: save the unit to disk first, then format it.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  Opts:= ResolveOptions(AFileName);
  if Opts.Backup then
    BackupNote:= 'A .BCK backup of the original is written first (Backup is on in the INI), ' +
      'so it stays recoverable.'
  else
    BackupNote:= 'NOTE: Backup is OFF in the INI, so no .BCK is written -- enable ' +
      '"Backup before overwrite" in YADFSetup to keep a safety copy.';
  if MessageDlg('YADFOT: "' + ExtractFileName(AFileName) + '" is a form / data-module unit.' +
       sLineBreak + sLineBreak +
       'It will be saved, formatted on disk, and reloaded so the Form Designer ' +
       'rebuilds cleanly (this format is not undoable). ' + BackupNote + sLineBreak + sLineBreak +
       'Continue?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if not M.Save(False, True) then
  begin
    MessageDlg('YADFOT: could not save the unit before formatting; aborted.',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  try
    if not FormatFileOnDisk(AFileName, Opts) then Exit; // no change -> leave designer alone
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
//   2. Refuse non-code buffers (form designer, project options, ...).
//   3. Resolve options from the nearest yadf.ini (or defaults).
//   4. Read editor text -> FormatSource -> write back, all within a
//      single try/except so any lexer/parser exception surfaces as a
//      dialog rather than an IDE crash.
//   5. Skip the write if formatting was a no-op, so we don't dirty the
//      buffer or add an empty entry to the IDE's undo stack.
procedure DoFormatCurrentBuffer(AProfileR: Boolean = False);
var
  Editor   : IOTASourceEditor;
  FileName : string;
  Opts     : TYadfOptions;
  Original : string;
  Formatted: string;
  RIni     : string;
begin
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

  // A form / data-module unit has a live Form Designer whose source-position
  // map a buffer swap would corrupt. Take the safe disk-reload handshake path
  // instead of the in-buffer write below.
  if ModuleHasFormDesigner(Editor) then
  begin
    FormatFormUnitViaReload(Editor, FileName);
    Exit;
  end;

  // Profile R uses the INI explicitly assigned in YADFSetup (no project walk);
  // profile F (default) walks for the nearest yadf.ini, exactly as before.
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
    Opts:= ResolveOptions(FileName);

  try
    Original := ReadEditorText(Editor);
    Formatted:= FormatSource(Original, Opts);
  except
    on E: Exception do
    begin
      MessageDlg('YADFOT: format failed.' + sLineBreak +
        E.ClassName + ': ' + E.Message,
        mtError, [mbOK], 0);
      Exit;
    end;
  end;

  if Formatted = Original then Exit;
  WriteEditorText(Editor, Formatted);
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

// --- Register ----------------------------------------------------------

// Register is the entry point the IDE invokes when the design-time
// package loads. It hands the IDE one IOTAWizard (the Tools-menu item)
// and one IOTAKeyboardBinding (the Ctrl+Shift+Alt+F shortcut). Both
// indices are stored so finalization can hand them back cleanly on
// package unload; IOTAKeyboardServices may be unavailable in some IDE
// configurations, so we tolerate its absence rather than failing the
// whole registration.
procedure Register;
var
  KS: IOTAKeyboardServices;
begin
  GWizardIndex:= (BorlandIDEServices as IOTAWizardServices).AddWizard(TYadfotMenuWizard.Create);
  KS:= BorlandIDEServices as IOTAKeyboardServices;
  if KS <> nil then
    GKeyboardBindingIndex:= KS.AddKeyboardBinding(TYadfotKeyboardBinding.Create);
end;

initialization

// Hand back the wizard slot and keyboard binding when the package
// unloads (e.g. user uninstalls via Component > Install Packages). This
// is essential -- if the slot is left dangling, the next package load
// can leave duplicate menu items behind.
finalization
  if GWizardIndex <> -1 then
    (BorlandIDEServices as IOTAWizardServices).RemoveWizard(GWizardIndex);
  if GKeyboardBindingIndex <> -1 then
    (BorlandIDEServices as IOTAKeyboardServices).RemoveKeyboardBinding(GKeyboardBindingIndex);

end.
