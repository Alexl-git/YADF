{
  YADF -- Yet Another Delphi Formatter

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Uses lexer/parser code from DelphiAST:
  Copyright (c) 2014-2020 Roman Yankovsky (roman@yankovsky.me) et al
  https://github.com/RomanYankovsky/DelphiAST
}

unit YADF.Options;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.IniFiles
  , System.Variants
  ;

type
  /// <summary></summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: TYadfEncoding caller (YADF.Options.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TYadfEncoding = (encANSI, encUTF8BOM, encUTF16BOM);

  /// <summary></summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: TYadfOptions caller (YADF.Layout.pas), YadfMain.RunYadf (YadfMain.pas), TestFormatSourceStillFormats (GuardTest.dpr), TestRoundTrip (OptionsTest.dpr), TestCommentPreservation (OptionsTest.dpr) (+5 more)
  /// Used in units: GuardTest, OptionsTest, YADF.Layout, YADF.Options, YADF.OptionsFrame, YadfMain, YADFOT.Wizard
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TYadfOptions = record
    MaxLen              : Integer      ;
    Indent              : Integer      ;
    TabWidth            : Integer      ;
    MarkUnclosed        : Boolean      ;
    LabelLongBlocks     : Boolean      ;
    LabelMinLines       : Integer      ;
    MaxBlankLines       : Integer      ;
    TrimTrailing        : Boolean      ;
    ReflowLines         : Boolean      ;
    LowercaseKeywords   : Boolean      ;
    UpperHexNumbers     : Boolean      ;
    UpperDirectives     : Boolean      ;
    FirstOccCasing      : Boolean      ;
    BlanksBeforeSection : Integer      ;
    BlanksBeforeMethod  : Integer      ;
    BlanksBeforeType    : Integer      ;
    AssignNoSpaceBefore : Boolean      ;
    AssignSpaceAfter    : Boolean      ;
    SpaceAroundOperators: Boolean      ;
    AlignConstEquals    : Boolean      ;
    AlignTypeColon      : Boolean      ;
    AlignSmartAssign    : Boolean      ;
    AlignMaxColumn      : Integer      ;
    AlignMatchingShapes : Boolean      ;
    AlignShapeMinAnchors: Integer      ;
    AlignCommentMaxShift: Integer      ;
    UsesAlwaysBreak     : Boolean      ;
    UsesCommaLast       : Boolean      ;
    SplitMultiVarDecls  : Boolean      ;
    AlignDeclSemicolons : Boolean      ;
    BreakCaseLabels     : Boolean      ;
    IndentComments      : Boolean      ;
    PackShortBodies     : Boolean      ;
    CollapseShortBlocks : Boolean      ;
    BreakLoopBody       : Boolean      ;
    BreakWithBody       : Boolean      ;
    BreakIfBody         : Boolean      ;
    Delphi10Compat      : Boolean      ;
    Backup              : Boolean      ;
    BackupDir           : string       ;
    ResultDir           : string       ;
    Encoding            : TYadfEncoding;
    Logging             : Boolean      ;
  end; // record

  // ---- Single descriptor table : the settings authority ----
  /// <summary></summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: TOptKind caller (YADF.Options.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOptKind = (okBool, okInt, okString, okEnum);

  TOptGetter = reference to function(const O: TYadfOptions): Variant;
  TOptSetter = reference to procedure(var O: TYadfOptions; const V: Variant);

  /// <summary></summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: TOptInfo caller (YADF.Options.pas)
  /// Used in units: YADF.Options
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOptInfo = record
    Ident         : string        ; // INI key under [Format] AND the record field name
    Group         : string        ; // UI group + template section header
    Caption       : string        ; // GUI label
    Hint          : string        ; // one-line help: GUI tooltip, ';' comment, --help line
    Kind          : TOptKind      ;
    AffectsPreview: Boolean       ; // False for file/CLI-only options
    EnumValues    : TArray<string>; // okEnum only: the combo's value list (in order)
    GetVal        : TOptGetter    ;
    SetVal        : TOptSetter    ;
  end; // record

/// <summary></summary>
/// <returns></returns>
function DefaultOptions: TYadfOptions;

// The single authority for every TYadfOptions field. Built once on first call.
/// <summary></summary>
/// <returns>Observed: O.MaxLen end,; O.Indent end,; O.TabWidth end,; O.ReflowLines end,; O.TrimTrailing end,; O.MaxBlankLines end,.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: Exit, Length, VarToStr, YADF.Options.EncodingToStr, YADF.Options.MakeOpt, YADF.Options.ParseEncoding
/// Returns: GOptTable
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function OptionTable: TArray<TOptInfo>;

// Encoding name <-> enum, shared by CLI, wizard, GUI, and the INI layer.
/// <summary></summary>
/// <param name="S"></param>
/// <param name="ADefault"></param>
/// <returns>Observed: encUTF8BOM; encUTF16BOM; encANSI; ADefault.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.OptionTable (YADF.Options.pas), YadfMain.ParseFlags (YadfMain.pas) ?
/// Calls: Trim, UpperCase
/// Returns: encUTF8BOM; encUTF16BOM; encANSI; ADefault
/// Complexity: 11 (cyclomatic), 13 lines
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseEncoding(const S: string; const ADefault: TYadfEncoding): TYadfEncoding;
/// <summary></summary>
/// <param name="E"></param>
/// <returns>Observed: 'UTF-8'; 'UTF-16'; 'ANSI'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.OptionTable (YADF.Options.pas)
/// Returns: 'UTF-8'; 'UTF-16'; 'ANSI'
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function EncodingToStr(const E: TYadfEncoding): string;

// TYadfEncoding -> the TEncoding used to WRITE it (ANSI / UTF-8 / UTF-16 LE).
/// <summary></summary>
/// <param name="E"></param>
/// <returns>Observed: TEncoding.UTF8; TEncoding.Unicode; TEncoding.ANSI.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADFOT.Wizard.FormatFileOnDisk (YADFOT.Wizard.pas), YadfMain.LoadFile (YadfMain.pas)
/// Returns: TEncoding.UTF8; TEncoding.Unicode; TEncoding.ANSI
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function EncodingOf(const E: TYadfEncoding): TEncoding;

// THE source-encoding detector, shared by the CLI and the wizard so both
// hosts decode and re-encode the same file identically: BOM first (UTF-8,
// UTF-16 LE, UTF-16 BE), then BOM-less content that validates as multi-byte
// UTF-8 (LooksLikeUtf8), else ANSI. APreambleLen is the BOM length to skip on
// read AND re-emit on write -- 0 for BOM-less files, so a detected BOM-less
// UTF-8 file stays BOM-less when preserved.
/// <summary></summary>
/// <param name="ABytes"></param>
/// <param name="AEnc"></param>
/// <param name="APreambleLen"></param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADFOT.Wizard.FormatFileOnDisk (YADFOT.Wizard.pas), YadfMain.LoadFile (YadfMain.pas)
/// Calls: Length, YADF.Options.LooksLikeUtf8
/// Complexity: 12 (cyclomatic), 25 lines
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure DetectSourceEncoding(const ABytes: TBytes; out AEnc: TEncoding; out APreambleLen: Integer);

// Reads a textual boolean (1/0, true/false, yes/no, on/off; case-insensitive);
// unrecognised values return ADefault. Delphi's TIniFile.ReadBool only honours
// numeric 0/1, but yadf.ini ships textual booleans.
/// <summary></summary>
/// <param name="AIni"></param>
/// <param name="ASection"></param>
/// <param name="AIdent"></param>
/// <param name="ADefault"></param>
/// <returns>Observed: ADefault.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.LoadOptionsFromIni (YADF.Options.pas)
/// Calls: Exit, LowerCase, ReadString, Trim
/// Returns: ADefault
/// Covered by: TestRoundTrip
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadBoolIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;

// Reads an integer leniently: trims, tolerates a trailing `;` / `//` comment
// after the value, accepts Delphi $-hex; anything unparsable returns ADefault
// (same contract as ReadBoolIni). TIniFile.ReadInteger silently returns the
// default for e.g. "MaxLen=120 ; note" -- the same silent-ignore class as the
// old textual-boolean defect.
/// <summary></summary>
/// <param name="AIni"></param>
/// <param name="ASection"></param>
/// <param name="AIdent"></param>
/// <param name="ADefault"></param>
/// <returns>Observed: ADefault.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.LoadOptionsFromIni (YADF.Options.pas), TestLenientIntRead (OptionsTest.dpr) ?
/// Calls: Pos, ReadString, SetLength, Trim, TryStrToInt
/// Returns: ADefault
/// Covered by: TestLenientIntRead, TestRoundTrip
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadIntIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Integer): Integer;

// Hint + the compiled-in default rendered live from DefaultOptions -- the ONE
// place the "Default: X" suffix is produced (table hints carry none, so the
// suffix can never drift from the real default). Used by the INI template,
// --help, and the options UIs.
/// <summary></summary>
/// <param name="AInfo"></param>
/// <returns>Observed: AInfo.Hint + ' Default: ' + D.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.OptionsHelpText (YADF.Options.pas), YADF.Options.WriteDefaultIniTemplate (YADF.Options.pas), TestDescriptorCompleteness (OptionsTest.dpr) ?, YADF.OptionsFrame.TYadfOptionsFrame.BuildControls (YADF.OptionsFrame.pas) ?
/// Calls: YADF.Options.DefaultValueStr
/// Returns: AInfo.Hint + ' Default: ' + D
/// Covered by: TestDescriptorCompleteness, TestLenientIntRead, TestLooksLikeUtf8
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function OptionHint(const AInfo: TOptInfo): string;

// True when ABytes are valid UTF-8 AND contain at least one multi-byte
// sequence. Used by the CLI and the wizard to promote BOM-less files from the
// blind ANSI fallback to UTF-8 on load (a file that validates as multi-byte
// UTF-8 is overwhelmingly likely UTF-8; reading it as ANSI mojibakes on
// rewrite). Pure ASCII returns False -- ANSI and UTF-8 agree there, so the
// ANSI path stays. Strict: overlong forms, UTF-16 surrogates, >U+10FFFF and
// truncated sequences all return False.
/// <summary></summary>
/// <param name="ABytes"></param>
/// <returns>Observed: False; HasMulti.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.DetectSourceEncoding (YADF.Options.pas), TestLooksLikeUtf8 (OptionsTest.dpr) ?
/// Calls: Exit, Inc, Length
/// Returns: False; HasMulti
/// Complexity: 22 (cyclomatic), 41 lines
/// Covered by: TestLooksLikeUtf8
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function LooksLikeUtf8(const ABytes: TBytes): Boolean;

// Load every [Format] key into a TYadfOptions, falling back to DefaultOptions
// per field. Returns DefaultOptions unchanged if the file is missing.
/// <summary></summary>
/// <param name="APath"></param>
/// <returns>Observed: DefaultOptions.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: TestRoundTrip (OptionsTest.dpr), YADF.OptionsFrame.TYadfOptionsFrame.Commit (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.LoadOptionsFromFile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas) (+2 more)
/// Calls: Create, FileExists, GetVal, High, ReadString, SetVal, VarToStr, YADF.Options.ReadBoolIni, YADF.Options.ReadIntIni
/// Returns: DefaultOptions
/// Covered by: TestRoundTrip
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadOptionsFromIni(const APath: string): TYadfOptions;

// Persist current values over the commented template (so comments survive).
/// <summary></summary>
/// <param name="AOpts"></param>
/// <param name="APath"></param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: TestRoundTrip (OptionsTest.dpr), TestCommentPreservation (OptionsTest.dpr), YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.Commit (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SaveOptionsToFile (YADF.OptionsFrame.pas) (+2 more)
/// Calls: Create, GetVal, High, IfThen, VarToStr, WriteInteger, WriteString, YADF.Options.EnsureIniExists
/// Covered by: TestCommentPreservation, TestRoundTrip
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);

// One "Ident - Hint" line per option, grouped -- for CLI --help / about text.
/// <summary></summary>
/// <returns>Observed: SB.ToString.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: AppendLine, Format, High, YADF.Options.OptionHint
/// Returns: SB.ToString
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function OptionsHelpText: string;

// Shared per-user fallback path used by YADF.exe, YADFOT.bpl, and YADFSetup.exe
// when no project-local yadf.ini is found. Returns %APPDATA%\YADF\yadf.ini.
/// <summary></summary>
/// <returns>Observed: TPath.Combine(.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: Combine
/// Returns: TPath.Combine( TPath.Combine(TPath.GetHomePath, 'YADF'), 'yadf.ini')
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function SharedAppDataIniPath: string;

// Write a fully-commented yadf.ini at APath (every option, default, one-line
// explanation), rendered from the descriptor table. Does NOT overwrite an
// existing file's values destructively beyond (re)creating when absent.
/// <summary></summary>
/// <param name="APath"></param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.EnsureIniExists (YADF.Options.pas)
/// Calls: Add, DirectoryExists, ExtractFilePath, ForceDirectories, High, SaveToFile, YADF.Options.DefaultValueStr, YADF.Options.OptionHint
/// Covered by: TestCommentPreservation, TestRoundTrip
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure WriteDefaultIniTemplate(const APath: string);

// If APath does not exist, write the template; otherwise no-op. Returns True
// when a new file was created.
/// <summary></summary>
/// <param name="APath"></param>
/// <returns>Observed: False; True.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Options.SaveOptionsToIni (YADF.Options.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas) ?, YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas) ?, YADFOT.Wizard.ResolveOptions (YADFOT.Wizard.pas) ?, YadfMain.DefaultIniPath (YadfMain.pas) ? (+1 more)
/// Calls: FileExists, YADF.Options.WriteDefaultIniTemplate
/// Returns: False; True
/// Covered by: TestCommentPreservation, TestRoundTrip
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function EnsureIniExists(const APath: string): Boolean;

// ---- IDE formatting profiles ------------------------------------------------
// Two named INI profiles bound to the YADFOT IDE shortcuts: F (Ctrl+Shift+Alt+F,
// also the EXE/CLI default) and R (Ctrl+Shift+Alt+R, YADFOT only). The mapping
// lives in profiles.ini next to the shared yadf.ini; each value is a *.ini file
// name resolved in that same folder. R may be empty (no second profile set).
type
  /// <summary></summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: TYadfProfiles caller (YADF.Options.pas), TYadfProfiles caller (YADF.OptionsFrame.pas), YadfMain.DefaultIniPath (YadfMain.pas)
  /// Used in units: YADF.Options, YADF.OptionsFrame, YadfMain
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TYadfProfiles = record
    F: string; // INI file name for Ctrl+Shift+Alt+F (defaults to 'yadf.ini')
    R: string; // INI file name for Ctrl+Shift+Alt+R ('' = unassigned)
  end;

  // Folder that holds the shared yadf.ini / profiles.ini (%APPDATA%\YADF).
/// <summary></summary>
/// <returns>Observed: ExtractFilePath(SharedAppDataIniPath).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: ExtractFilePath
/// Returns: ExtractFilePath(SharedAppDataIniPath)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProfilesDir: string;

// %APPDATA%\YADF\profiles.ini -- the F/R mapping file.
/// <summary></summary>
/// <returns>Observed: TPath.Combine(ProfilesDir, 'profiles.ini').</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: Combine
/// Returns: TPath.Combine(ProfilesDir, 'profiles.ini')
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProfilesIniPath: string;

// Read the F/R mapping. Missing file or missing key falls back to F='yadf.ini',
// R='' so existing installs behave exactly as before.
/// <summary></summary>
/// <returns></returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: Create, FileExists, ReadString, Trim
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadProfiles: TYadfProfiles;

// Persist the F/R mapping (creates the folder/file as needed). Best-effort.
/// <summary></summary>
/// <param name="AProfiles"></param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.UnassignSelected (YADF.OptionsFrame.pas), YadfMain.DefaultIniPath (YadfMain.pas)
/// Calls: Create, DirectoryExists, ForceDirectories, WriteString
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SaveProfiles(const AProfiles: TYadfProfiles);

// Resolve a profile's INI file name to a full path in ProfilesDir. Returns ''
// for an empty name; passes an already-rooted path through unchanged.
/// <summary></summary>
/// <param name="AFileName"></param>
/// <returns>Observed: AFileName; TPath.Combine(ProfilesDir, AFileName).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.OptionsFrame.TYadfOptionsFrame.MirrorFProfile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.NewProfileClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADFOT.Wizard.ResolveOptions (YADFOT.Wizard.pas) (+2 more)
/// Calls: Combine, Exit, IsPathRooted, Trim
/// Returns: AFileName; TPath.Combine(ProfilesDir, AFileName)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveProfileIniPath(const AFileName: string): string;

implementation

uses
  System.StrUtils
  ;

function DefaultOptions: TYadfOptions;
begin
  Result.MaxLen              := 180;
  Result.Indent              := 2;
  Result.TabWidth            := 4;
  Result.MarkUnclosed        := False;
  Result.LabelLongBlocks     := True;
  Result.LabelMinLines       := 15;
  Result.MaxBlankLines       := 1;
  Result.TrimTrailing        := True;
  Result.ReflowLines         := True;
  Result.LowercaseKeywords   := True;
  Result.UpperHexNumbers     := True;
  Result.UpperDirectives     := True;
  Result.FirstOccCasing      := True;
  Result.BlanksBeforeSection := 0;
  Result.BlanksBeforeMethod  := 0;
  Result.BlanksBeforeType    := 0;
  Result.AssignNoSpaceBefore := True;
  Result.AssignSpaceAfter    := True;
  Result.SpaceAroundOperators:= True;
  Result.AlignConstEquals    := True;
  Result.AlignTypeColon      := True;
  Result.AlignSmartAssign    := True;
  Result.AlignMaxColumn      := 140;
  Result.AlignMatchingShapes := True;
  Result.AlignShapeMinAnchors:= 3;
  Result.AlignCommentMaxShift:= 7;
  Result.UsesAlwaysBreak     := True;
  Result.UsesCommaLast       := False;
  Result.SplitMultiVarDecls  := True;
  Result.AlignDeclSemicolons := True;
  Result.BreakCaseLabels     := False;
  Result.IndentComments      := True;
  Result.PackShortBodies     := False;
  Result.CollapseShortBlocks := False;
  Result.BreakLoopBody       := False;
  Result.BreakWithBody       := False;
  Result.BreakIfBody         := False;
  Result.Delphi10Compat      := False;
  Result.Backup              := False;
  Result.BackupDir           := '';
  Result.ResultDir           := '';
  Result.Encoding            := encANSI;
  Result.Logging             := False;
end; // function

function ParseEncoding(const S: string; const ADefault: TYadfEncoding): TYadfEncoding;
var
  L: string;
begin
  L:= UpperCase(Trim(S));
  if (L = 'UTF-8') or (L = 'UTF8') or (L = 'UTF-8-BOM') or (L = 'UTF8BOM') then
    Result:= encUTF8BOM
  else if (L = 'UTF-16') or (L = 'UTF16') or (L = 'UTF-16-BOM') or (L = 'UTF16BOM') or (L = 'UTF-16-LE') then
    Result:= encUTF16BOM
  else if (L = 'ANSI') then
    Result:= encANSI
  else
    Result:= ADefault;
end; // function

function EncodingToStr(const E: TYadfEncoding): string;
begin
  case E of
    encUTF8BOM : Result:= 'UTF-8';
    encUTF16BOM: Result:= 'UTF-16';
    else
      Result:= 'ANSI';
  end;
end;

function ReadBoolIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;
var
  S: string;
begin
  S:= LowerCase(Trim(AIni.ReadString(ASection, AIdent, '')));
  if (S = '1') or (S = 'true' ) or (S = 'yes') or (S = 'on' ) then Exit(True );
  if (S = '0') or (S = 'false') or (S = 'no' ) or (S = 'off') then Exit(False);
  Result:= ADefault;
end;

var
  GOptTable: TArray<TOptInfo>;

function MakeOpt(
  const AIdent, AGroup, ACaption, AHint: string; AKind: TOptKind; AAffects: Boolean; const AGet: TOptGetter; const ASet: TOptSetter; const AEnumValues: TArray<string> = nil
): TOptInfo;
begin
  Result.Ident         := AIdent;
  Result.Group         := AGroup;
  Result.Caption       := ACaption;
  Result.Hint          := AHint;
  Result.Kind          := AKind;
  Result.AffectsPreview:= AAffects;
  Result.EnumValues    := AEnumValues;
  Result.GetVal        := AGet;
  Result.SetVal        := ASet;
end; // function

function EncodingOf(const E: TYadfEncoding): TEncoding;
begin
  case E of
    encUTF8BOM : Result:= TEncoding.UTF8;
    encUTF16BOM: Result:= TEncoding.Unicode;
    else
      Result:= TEncoding.ANSI;
  end;
end;

procedure DetectSourceEncoding(const ABytes: TBytes; out AEnc: TEncoding; out APreambleLen: Integer);
begin
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
  begin
    AEnc:= TEncoding.UTF8;
    APreambleLen:= 3;
  end
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
  begin
    AEnc:= TEncoding.Unicode;
    APreambleLen:= 2;
  end
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
  begin
    AEnc:= TEncoding.BigEndianUnicode;
    APreambleLen:= 2;
  end
  else
  begin
    if LooksLikeUtf8(ABytes) then
      AEnc:= TEncoding.UTF8
    else
      AEnc:= TEncoding.ANSI;
    APreambleLen:= 0;
  end;
end; // procedure

function ReadIntIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Integer): Integer;
var
  S: string ;
  p: Integer;
begin
  S:= AIni.ReadString(ASection, AIdent, '');
  p:= Pos(';', S);
  if p > 0 then SetLength(S, p - 1);
  p:= Pos('//', S);
  if p > 0 then SetLength(S, p - 1);
  if not TryStrToInt(Trim(S), Result) then
    Result:= ADefault;
end;

function LooksLikeUtf8(const ABytes: TBytes): Boolean;
var
  i       : Integer ;
  n       : Integer ;
  Need    : Integer ;
  Len     : Integer ;
  B       : Byte    ;
  Cp      : Cardinal;
  MinCp   : Cardinal;
  HasMulti: Boolean ;
begin
  HasMulti:= False;
  Len:= Length(ABytes);
  i:= 0;
  while i < Len do
  begin
    B:= ABytes[i];
    if B < $80 then
    begin
      Inc(i);
      Continue;
    end;
    // Lead byte -> continuation count + minimum code point (overlong check).
    if (B >= $C2) and (B <= $DF) then begin Need:= 1; Cp:= B and $1F; MinCp:= $80 ; end
    else if (B >= $E0) and (B <= $EF) then begin Need:= 2; Cp:= B and $0F; MinCp:= $800  ; end
    else if (B >= $F0) and (B <= $F4) then begin Need:= 3; Cp:= B and $07; MinCp:= $10000; end
    else
      Exit(False); // stray continuation, overlong C0/C1 lead, or F5..FF
    if i + Need >= Len then Exit(False); // truncated sequence at buffer end
    for n:= 1 to Need do
    begin
      B:= ABytes[i + n];
      if (B and $C0) <> $80 then Exit(False);
      Cp:= (Cp shl 6) or (B and $3F);
    end;
    if (Cp < MinCp) or (Cp > $10FFFF) or ((Cp >= $D800) and (Cp <= $DFFF)) then
      Exit(False);
    HasMulti:= True;
    Inc(i, Need + 1);
  end; // while
  Result:= HasMulti;
end; // function

function OptionTable: TArray<TOptInfo>;
begin
  if Length(GOptTable) > 0 then Exit(GOptTable);
  GOptTable:= [
    MakeOpt('MaxLen', 'Line length & indentation', 'Max line length', 'Maximum line length in columns. Long lines are reflowed when ReflowLines is true.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.MaxLen end, procedure(var O: TYadfOptions; const V: Variant) begin O.MaxLen:= V end),
    MakeOpt('Indent', 'Line length & indentation', 'Indent step', 'Indentation step in spaces (each nesting level adds this many).', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.Indent end, procedure(var O: TYadfOptions; const V: Variant) begin O.Indent:= V end),
    MakeOpt('TabWidth', 'Line length & indentation', 'Tab width', 'Width assumed for an existing tab on input. YADF always emits spaces.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.TabWidth end, procedure(var O: TYadfOptions; const V: Variant) begin O.TabWidth:= V end),
    MakeOpt('ReflowLines', 'Reflow & whitespace', 'Reflow long lines', 'Reflow lines that exceed MaxLen. When false, long lines are left as-is.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.ReflowLines end, procedure(var O: TYadfOptions; const V: Variant) begin O.ReflowLines:= V end),
    MakeOpt('TrimTrailing', 'Reflow & whitespace', 'Trim trailing spaces', 'Trim trailing whitespace from every output line.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.TrimTrailing end, procedure(var O: TYadfOptions; const V: Variant) begin O.TrimTrailing:= V end),
    MakeOpt('MaxBlankLines', 'Reflow & whitespace', 'Max blank lines', 'Maximum consecutive blank lines kept in output. Excess blanks are collapsed.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.MaxBlankLines end, procedure(var O: TYadfOptions; const V: Variant) begin O.MaxBlankLines:= V end),
    MakeOpt('BlanksBeforeSection', 'Reflow & whitespace', 'Blanks before section', 'Blank lines forced before each interface section. 0 = no change.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.BlanksBeforeSection end, procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeSection:= V end),
    MakeOpt('BlanksBeforeMethod', 'Reflow & whitespace', 'Blanks before method', 'Blank lines forced before each method body.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.BlanksBeforeMethod end, procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeMethod:= V end),
    MakeOpt('BlanksBeforeType', 'Reflow & whitespace', 'Blanks before type', 'Blank lines forced before each top-level type declaration.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.BlanksBeforeType end, procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeType:= V end),
    MakeOpt('LowercaseKeywords', 'Casing', 'Lowercase keywords', 'Lowercase Pascal keywords (begin, end, if, then ...).', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.LowercaseKeywords end, procedure(var O: TYadfOptions; const V: Variant) begin O.LowercaseKeywords:= V end),
    MakeOpt('UpperHexNumbers', 'Casing', 'Uppercase hex', 'Uppercase hex digits in numeric literals ($AB not $ab).', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.UpperHexNumbers end, procedure(var O: TYadfOptions; const V: Variant) begin O.UpperHexNumbers:= V end),
    MakeOpt('UpperDirectives', 'Casing', 'Uppercase directives', 'Uppercase compiler-directive keywords ({$IFDEF}, {$R+} ...).', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.UpperDirectives end, procedure(var O: TYadfOptions; const V: Variant) begin O.UpperDirectives:= V end),
    MakeOpt('FirstOccCasing', 'Casing', 'First-occurrence casing', 'Cascade casing from the first occurrence of each identifier to all later uses.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.FirstOccCasing end, procedure(var O: TYadfOptions; const V: Variant) begin O.FirstOccCasing:= V end),
    MakeOpt('AssignNoSpaceBefore', 'Assignment & alignment', 'No space before :=', 'No space BEFORE := ("X:= 1" not "X := 1").', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AssignNoSpaceBefore end, procedure(var O: TYadfOptions; const V: Variant) begin O.AssignNoSpaceBefore:= V end),
    MakeOpt('AssignSpaceAfter', 'Assignment & alignment', 'Space after :=', 'Single space AFTER := ("X:= 1" not "X:=1").', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AssignSpaceAfter end, procedure(var O: TYadfOptions; const V: Variant) begin O.AssignSpaceAfter:= V end),
    MakeOpt('AlignConstEquals', 'Assignment & alignment', 'Align const =', 'Vertical-align = in const blocks.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignConstEquals end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignConstEquals:= V end),
    MakeOpt('AlignTypeColon', 'Assignment & alignment', 'Align type :', 'Vertical-align : in type / var / parameter blocks.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignTypeColon end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignTypeColon:= V end),
    MakeOpt('AlignSmartAssign', 'Assignment & alignment', 'Smart-align', 'Master switch for the shape-aware alignment pass: aligns := runs and '
      + '(when "Align matching shapes" is on) any matching structural shapes '
      + 'across consecutive lines.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.AlignSmartAssign end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignSmartAssign:= V end),
    MakeOpt('AlignMaxColumn', 'Assignment & alignment', 'Align max column', 'Maximum column an alignment may push to. Past this, alignment is skipped.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignMaxColumn end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignMaxColumn:= V end),
    MakeOpt('AlignMatchingShapes', 'Assignment & alignment', 'Align matching shapes', 'Align matching "shapes" (record-init lines, repeated field declarations).', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignMatchingShapes end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignMatchingShapes:= V end),
    MakeOpt('AlignShapeMinAnchors', 'Assignment & alignment', 'Shape min anchors', 'Minimum anchors required before shape-alignment kicks in.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignShapeMinAnchors end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignShapeMinAnchors:= V end),
    MakeOpt('AlignCommentMaxShift', 'Assignment & alignment', 'Comment max shift', 'Maximum columns a trailing comment may shift when aligning to a shape.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignCommentMaxShift end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignCommentMaxShift:= V end),
    MakeOpt('SpaceAroundOperators', 'Spacing', 'Space around operators', 'Put one space around binary operators (A+B -> A + B): + - * / = <= >= <>. '
      + 'Unary +/- and generic brackets (<, >) are left intact.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.SpaceAroundOperators end, procedure(var O: TYadfOptions; const V: Variant) begin O.SpaceAroundOperators:= V end),
    MakeOpt('UsesAlwaysBreak', 'Uses clauses', 'Break uses one-per-line', 'Always break uses clauses one unit per line.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.UsesAlwaysBreak end, procedure(var O: TYadfOptions; const V: Variant) begin O.UsesAlwaysBreak:= V end),
    MakeOpt('UsesCommaLast', 'Uses clauses', 'Comma-last uses layout', 'Style of the broken (multi-line) uses clause. False (default) is comma-FIRST '
      + '(leading comma, semicolon on its own line) -- the diff-friendly layout. True is ' + 'comma-LAST (trailing comma per unit, semicolon on the last unit''s line: '
      + '"System.Classes;"). Only affects the multi-line form; the inline single-line '
      + 'form is unchanged.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.UsesCommaLast end, procedure(var O: TYadfOptions; const V: Variant) begin O.UsesCommaLast:= V end),
    MakeOpt('SplitMultiVarDecls', 'Declarations', 'Split multi-var decls', 'Split "I, J: integer;" into one line per name so the type colons align.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.SplitMultiVarDecls end, procedure(var O: TYadfOptions; const V: Variant) begin O.SplitMultiVarDecls:= V end),
    MakeOpt('AlignDeclSemicolons', 'Declarations', 'Align decl semicolons', 'After AlignTypeColon, align the trailing ; on consecutive declaration lines.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignDeclSemicolons end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignDeclSemicolons:= V end),
    MakeOpt('BreakCaseLabels', 'Declarations', 'Break case labels', 'Break a multi-label case arm ("a, b, c: Stmt;") into one label per line, '
      + 'duplicating the statement. Off by default -- multi-label case arms are kept ' + 'on one line (only genuine variable/field declarations are split, per '
      + 'SplitMultiVarDecls).', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakCaseLabels end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakCaseLabels:= V end),
    MakeOpt('IndentComments', 'Comments', 'Indent comments', 'Re-indent comment-only lines to the surrounding code depth. When off, every '
      + 'comment keeps the indentation the author gave it. A comment line that starts ' + 'with "//." always keeps its authored indentation even when this is on (an '
      + 'explicit "pin this comment" marker).', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.IndentComments end, procedure(var O: TYadfOptions; const V: Variant) begin O.IndentComments:= V end),
    MakeOpt('PackShortBodies', 'Reflow & whitespace', 'Pack short bodies & case arms', 'When reflowing, pull a SHORT body onto one line: a loop/if header keeps its '
      + 'simple statement ("for I := 0 to N do Inc(X);", "if X then DoIt;") and a case ' + 'arm collapses onto its label ("0: DoZero;"). Off by default -- every body/arm '
      + 'stays on its own line. A nested control header (if/case/begin...) is never '
      + 'half-merged onto a do/then/label either way.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.PackShortBodies end, procedure(var O: TYadfOptions; const V: Variant) begin O.PackShortBodies:= V end),
    MakeOpt('CollapseShortBlocks', 'Reflow & whitespace', 'Collapse short begin..end blocks', 'Fold a short control-statement begin..end body onto one line when it fits '
      + 'MaxLen: an if/for/while/with/else header whose block holds only simple ' + 'one-statement-per-line code becomes "if X then begin A := 1; B := 2; end;". '
      + 'Only pure simple-statement bodies fold -- a nested block, a multi-line ' + 'statement, or any comment leaves the block expanded; routine bodies are '
      + 'never folded. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.CollapseShortBlocks end, procedure(var O: TYadfOptions; const V: Variant) begin O.CollapseShortBlocks:= V end),
    MakeOpt('BreakLoopBody', 'Reflow & whitespace', 'Break loop body onto its own line', 'Force the body of a single-line for/while loop onto its own indented line '
      + '("while X do Dec(k);" -> "while X do" + newline + "  Dec(k);"). A begin block, '
      + 'a nested control header, or a body with a trailing comment is left alone. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakLoopBody end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakLoopBody:= V end),
    MakeOpt('BreakWithBody', 'Reflow & whitespace', 'Break with body onto its own line', 'Force the body of a single-line with..do statement onto its own indented line. '
      + 'Same guard rails as BreakLoopBody (begin/nested-header/comment bodies left alone). Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakWithBody end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakWithBody:= V end),
    MakeOpt('BreakIfBody', 'Reflow & whitespace', 'Break if/then/else body onto its own line', 'Force the then/else body of a single-line if statement onto its own indented line '
      + '("if X then A else B;" -> "if X then" / "  A" / "else" / "  B;"). "else if" chains stay '
      + 'glued; a begin/nested-header/comment body is left alone. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakIfBody end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakIfBody:= V end),
    MakeOpt('Delphi10Compat', 'Delphi 10 compatibility', 'Downgrade inline vars',
      'Hoist inline var declarations into a top-of-routine var block so the code builds on Delphi 10.2.3. Explicit types and simple literals are converted; the rest get a // TODO -oYADF marker. Best-effort, unverified on a real Tokyo toolchain.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.Delphi10Compat end, procedure(var O: TYadfOptions; const V: Variant) begin O.Delphi10Compat:= V end),
    MakeOpt('LabelLongBlocks', 'Labels & markers', 'Label long blocks', 'Insert "// end of <Name>" markers after long blocks.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.LabelLongBlocks end, procedure(var O: TYadfOptions; const V: Variant) begin O.LabelLongBlocks:= V end),
    MakeOpt('LabelMinLines', 'Labels & markers', 'Label min lines', 'Minimum lines a block must span before LabelLongBlocks adds the marker.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.LabelMinLines end, procedure(var O: TYadfOptions; const V: Variant) begin O.LabelMinLines:= V end),
    MakeOpt('MarkUnclosed', 'Labels & markers', 'Mark unclosed blocks', 'Add a "// UNCLOSED" marker when an opening keyword has no matching close.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.MarkUnclosed end, procedure(var O: TYadfOptions; const V: Variant) begin O.MarkUnclosed:= V end),
    MakeOpt('Backup', 'File & CLI (no preview effect)', 'Backup before overwrite', 'Create a backup of every file before overwriting it.', okBool, False,
      function(const O: TYadfOptions): Variant begin Result:= O.Backup end, procedure(var O: TYadfOptions; const V: Variant) begin O.Backup:= V end),
    MakeOpt('BackupDir', 'File & CLI (no preview effect)', 'Backup directory', 'Directory for backups (used when Backup=true). Empty = next to original file.', okString, False,
      function(const O: TYadfOptions): Variant begin Result:= O.BackupDir end, procedure(var O: TYadfOptions; const V: Variant) begin O.BackupDir:= VarToStr(V) end),
    MakeOpt('ResultDir', 'File & CLI (no preview effect)', 'Result directory', 'Directory for formatted output. Empty = format in place.', okString, False,
      function(const O: TYadfOptions): Variant begin Result:= O.ResultDir end, procedure(var O: TYadfOptions; const V: Variant) begin O.ResultDir:= VarToStr(V) end),
    MakeOpt('Encoding', 'File & CLI (no preview effect)', 'Output encoding',
      'ANSI keeps each file''s own encoding (BOM or detected UTF-8 preserved); UTF-8/UTF-16 convert the output (with BOM).', okEnum, False, function(const O: TYadfOptions): Variant begin Result:= EncodingToStr(O.Encoding) end, procedure(var O: TYadfOptions; const V: Variant) begin O.Encoding:= ParseEncoding(VarToStr(V),
          encANSI) end, ['ANSI', 'UTF-8', 'UTF-16']),
    MakeOpt('Logging', 'File & CLI (no preview effect)', 'Logging', 'Write a log file with details of every option resolved and file processed.', okBool, False,
      function(const O: TYadfOptions): Variant begin Result:= O.Logging end, procedure(var O: TYadfOptions; const V: Variant) begin O.Logging:= V end)];
  Result:= GOptTable;
end; // function

function LoadOptionsFromIni(const APath: string): TYadfOptions;
var
  Ini: TIniFile        ;
  T  : TArray<TOptInfo>;
  i  : Integer         ;
begin
  Result:= DefaultOptions;
  if (APath = '') or (not FileExists(APath)) then Exit;
  T:= OptionTable;
  Ini:= TIniFile.Create(APath);
  try
    for i:= 0 to High(T) do
    case T[i].Kind of
      okInt:
        T[i].SetVal(Result, ReadIntIni(Ini, 'Format', T[i].Ident, T[i].GetVal(Result)));
      okBool:
        T[i].SetVal(Result, ReadBoolIni(Ini, 'Format', T[i].Ident, T[i].GetVal(Result)));
      okString, okEnum:
        T[i].SetVal(Result, Ini.ReadString('Format', T[i].Ident, VarToStr(T[i].GetVal(Result))));
    end;
  finally
    Ini.Free;
  end; // try
end; // function

procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);
var
  Ini : TIniFile        ;
  T   : TArray<TOptInfo>;
  i   : Integer         ;
  iVal: Integer         ;
  bVal: Boolean         ;
begin
  // Ensure the commented template exists first so WinAPI INI writes update
  // values in place and leave the ';' comment lines intact.
  EnsureIniExists(APath);
  T:= OptionTable;
  Ini:= TIniFile.Create(APath);
  try
    for i:= 0 to High(T) do
    case T[i].Kind of
      okInt :
      begin
        iVal:= T[i].GetVal(AOpts);
        Ini.WriteInteger('Format', T[i].Ident, iVal);
      end;
      okBool:
      begin
        bVal:= T[i].GetVal(AOpts);
        Ini.WriteString('Format', T[i].Ident, IfThen(bVal, 'true', 'false'));
      end;
      okString, okEnum:
        Ini.WriteString('Format', T[i].Ident, VarToStr(T[i].GetVal(AOpts)));
    end; // case
    Ini.UpdateFile;
  finally
    Ini.Free;
  end; // try
end; // procedure

function SharedAppDataIniPath: string;
begin
  // TPath.GetHomePath on Windows = %APPDATA% (Roaming). Subdirectory
  // is `YADF` (family name) -- YADF.exe, YADFOT.bpl and YADFSetup.exe all
  // write/read here so they always converge on the same file.
  Result:= TPath.Combine( TPath.Combine(TPath.GetHomePath, 'YADF'), 'yadf.ini');
end;

function DefaultValueStr(const AInfo: TOptInfo): string;
var
  D   : TYadfOptions;
  bVal: Boolean     ;
begin
  D:= DefaultOptions;
  case AInfo.Kind of
    okBool:
    begin
      bVal:= AInfo.GetVal(D);
      Result:= IfThen(bVal, 'true', 'false');
    end;
    else
      Result:= VarToStr(AInfo.GetVal(D));
  end;
end; // function

function OptionHint(const AInfo: TOptInfo): string;
var
  D: string;
begin
  D:= DefaultValueStr(AInfo);
  if D = '' then D:= 'empty';
  Result:= AInfo.Hint + ' Default: ' + D;
end;

procedure WriteDefaultIniTemplate(const APath: string);
var
  L      : TStringList     ;
  DirName: string          ;
  T      : TArray<TOptInfo>;
  i      : Integer         ;
  CurGrp : string          ;
begin
  DirName:= ExtractFilePath(APath);
  if (DirName <> '') and (not DirectoryExists(DirName)) then
    ForceDirectories(DirName);
  T:= OptionTable;
  L:= TStringList.Create;
  try
    L.Add('; YADF -- Yet Another Delphi Formatter'                             );
    L.Add('; Default configuration. Edit values and re-run.'                   );
    L.Add('; Lines starting with `;` are comments.'                            );
    L.Add('; CLI flags override these values; --ini <path> overrides location.');
    L.Add(''                                                                   );
    L.Add('[Format]'                                                           );
    CurGrp:= '';
    for i:= 0 to High(T) do
    begin
      if T[i].Group <> CurGrp then
      begin
        CurGrp:= T[i].Group;
        L.Add('');
        L.Add('; ---- ' + CurGrp + ' ----');
      end;
      L.Add('');
      L.Add('; ' + OptionHint(T[i]));
      L.Add(T[i].Ident + ' = ' + DefaultValueStr(T[i]));
    end; // for
    L.SaveToFile(APath, TEncoding.ANSI);
  finally
    L.Free;
  end; // try
end; // procedure

function OptionsHelpText: string;
var
  T     : TArray<TOptInfo>;
  i     : Integer         ;
  CurGrp: string          ;
  SB    : TStringBuilder  ;
begin
  T:= OptionTable;
  SB:= TStringBuilder.Create;
  try
    CurGrp:= '';
    for i:= 0 to High(T) do
    begin
      if T[i].Group <> CurGrp then
      begin
        CurGrp:= T[i].Group;
        SB.AppendLine;
        SB.AppendLine('  [' + CurGrp + ']');
      end;
      SB.AppendLine(Format('    %-22s %s', [T[i].Ident, OptionHint(T[i])]));
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function EnsureIniExists(const APath: string): Boolean;
begin
  Result:= False;
  if APath = '' then Exit;
  if FileExists(APath) then Exit;
  try
    WriteDefaultIniTemplate(APath);
    Result:= True;
  except
    // Best-effort: a read-only location is non-fatal -- the run still
    // proceeds with the compiled defaults. Callers can detect by checking
    // FileExists(APath) post-call.
    Result:= False;
  end;
end; // function

function ProfilesDir: string;
begin
  Result:= ExtractFilePath(SharedAppDataIniPath);
end;

function ProfilesIniPath: string;
begin
  Result:= TPath.Combine(ProfilesDir, 'profiles.ini');
end;

function LoadProfiles: TYadfProfiles;
var
  Ini: TIniFile;
begin
  Result.F:= 'yadf.ini';
  Result.R:= '';
  if not FileExists(ProfilesIniPath) then Exit;
  Ini:= TIniFile.Create(ProfilesIniPath);
  try
    Result.F:= Trim(Ini.ReadString('Profiles', 'F', Result.F));
    Result.R:= Trim(Ini.ReadString('Profiles', 'R', Result.R));
    if Result.F = '' then Result.F:= 'yadf.ini';
  finally
    Ini.Free;
  end;
end; // function

procedure SaveProfiles(const AProfiles: TYadfProfiles);
var
  Ini    : TIniFile;
  DirName: string  ;
begin
  DirName:= ProfilesDir;
  if (DirName <> '') and (not DirectoryExists(DirName)) then
    ForceDirectories(DirName);
  Ini:= TIniFile.Create(ProfilesIniPath);
  try
    Ini.WriteString('Profiles', 'F', AProfiles.F);
    Ini.WriteString('Profiles', 'R', AProfiles.R);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end; // procedure

function ResolveProfileIniPath(const AFileName: string): string;
begin
  if Trim(AFileName) = '' then Exit('');
  if TPath.IsPathRooted(AFileName) then
    Result:= AFileName
  else
    Result:= TPath.Combine(ProfilesDir, AFileName);
end;

end.

