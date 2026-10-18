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

unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.IniFiles
  , System.Variants
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Options.pas), [YADF]YadfMain.EncName (YadfMain.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TYadfEncoding = (encANSI, encUTF8BOM, encUTF16BOM);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Layout.pas), [YADF]declaration (YADF.Options.pas), declaration (YADF.OptionsFrame.pas), [YADF]declaration (YadfMain.pas), [YADF]YADF.Layout.ApplyBlockEndLabels (YADF.Layout.pas), [YADF]YADF.Layout.ApplyCapitalization (YADF.Layout.pas), [YADF]YADF.Layout.BreakControlBodies (YADF.Layout.pas), [YADF]YADF.Layout.BreakRoutineParams (YADF.Layout.pas), [YADF]YADF.Layout.DowngradeInlineVars (YADF.Layout.pas), [YADF]YADF.Layout.EnforceBlankLines (YADF.Layout.pas), [YADF]YADF.Layout.JoinRoutineHeaders (YADF.Layout.pas), [YADF]YADF.Layout.NormalizeAssignSpacing (YADF.Layout.pas), [YADF]YADF.Layout.RenderUsesGroup (YADF.Layout.pas), [YADF]YADF.Options.DefaultValueStr (YADF.Options.pas), [YADF]YADF.Options.OptionTable (YADF.Options.pas), [YADF]YadfMain.BatchFormat (YadfMain.pas), [YADF]YadfMain.CheckDir (YadfMain.pas), [YADF]YadfMain.CheckFile (YadfMain.pas), [YADF]YadfMain.DebugTree (YadfMain.pas), [YADF]YadfMain.ExpandFileSpec (YadfMain.pas),
  /// [YADF]YadfMain.FormatToFile (YadfMain.pas), [YADF]YadfMain.FormatToStdout (YadfMain.pas), [YADF]YadfMain.LoadFile (YadfMain.pas), [YADF]YadfMain.LoadIniDefaults (YadfMain.pas), [YADF]YadfMain.LogStartup (YadfMain.pas), [YADF]YadfMain.ParseDprojUnits (YadfMain.pas), [YADF]YadfMain.ParseDprUnits (YadfMain.pas), [YADF]YadfMain.ParseFlags (YadfMain.pas), [YADF]YadfMain.ProcessFiles (YadfMain.pas), [YADF]YadfMain.RunYadf (YadfMain.pas), [YADF]YadfMain.ShowUsage (YadfMain.pas), YADFOT.Wizard.DoFormatCurrentBuffer (YADFOT.Wizard.pas)</para>
  /// <para>Used in units: [YADF]YADF.Layout, [YADF]YADF.Options, [YADF]YadfMain, YADFOT.Wizard</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>

  TYadfOptions = record
    MaxLen               : Integer      ;
    Indent               : Integer      ;
    TabWidth             : Integer      ;
    MarkUnclosed         : Boolean      ;
    LabelLongBlocks      : Boolean      ;
    LabelMinLines        : Integer      ;
    MaxBlankLines        : Integer      ;
    TrimTrailing         : Boolean      ;
    ReflowLines          : Boolean      ;
    LowercaseKeywords    : Boolean      ;
    UpperHexNumbers      : Boolean      ;
    UpperDirectives      : Boolean      ;
    FirstOccCasing       : Boolean      ;
    BlanksBeforeSection  : Integer      ;
    BlanksBeforeMethod   : Integer      ;
    BlanksBeforeType     : Integer      ;
    AssignNoSpaceBefore  : Boolean      ;
    AssignSpaceAfter     : Boolean      ;
    SpaceAroundOperators : Boolean      ;
    AlignConstEquals     : Boolean      ;
    AlignTypeColon       : Boolean      ;
    AlignSmartAssign     : Boolean      ;
    AlignMaxColumn       : Integer      ;
    AlignMatchingShapes  : Boolean      ;
    AlignShapeMinAnchors : Integer      ;
    AlignCommentMaxShift : Integer      ;
    UsesAlwaysBreak      : Boolean      ;
    UsesCommaLast        : Boolean      ;
    SplitMultiVarDecls   : Boolean      ;
    AlignDeclSemicolons  : Boolean      ;
    BreakCaseLabels      : Boolean      ;
    IndentComments       : Boolean      ;
    PackShortBodies      : Boolean      ;
    CollapseShortBlocks  : Boolean      ;
    BreakLoopBody        : Boolean      ;
    BreakWithBody        : Boolean      ;
    BreakIfBody          : Boolean      ;
    BreakParamsOnePerLine: Boolean      ;
    BreakLongExpressions : Boolean      ;
    Delphi10Compat       : Boolean      ;
    Backup               : Boolean      ;
    BackupDir            : string       ;
    ResultDir            : string       ;
    Encoding             : TYadfEncoding;
    Logging              : Boolean      ;
  end; // record

  // ---- Single descriptor table : the settings authority ----
  /// <summary><!-- drag-lint:auto sum -->---- Single descriptor table : the settings
  /// authority ----</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Options.pas), [YADF]YADF.Options.MakeOpt (YADF.Options.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOptKind = (okBool, okInt, okString, okEnum);

  /// <param name="O"><!-- drag-lint:auto type -->const TYadfOptions</param>
  /// <returns><!-- drag-lint:auto type -->Variant</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Options.pas), [YADF]YADF.Options.MakeOpt (YADF.Options.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOptGetter = reference to function(const O: TYadfOptions): Variant;
  /// <param name="O"><!-- drag-lint:auto type -->var TYadfOptions</param>
  /// <param name="V"><!-- drag-lint:auto type -->const Variant</param>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Options.pas), [YADF]YADF.Options.MakeOpt (YADF.Options.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOptSetter = reference to procedure(var O: TYadfOptions; const V: Variant);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Options.pas), [YADF]YADF.Options.DefaultValueStr (YADF.Options.pas), [YADF]YADF.Options.LoadOptionsFromIni (YADF.Options.pas), [YADF]YADF.Options.MakeOpt (YADF.Options.pas), [YADF]YADF.Options.OptionsHelpText (YADF.Options.pas), [YADF]YADF.Options.SaveOptionsToIni (YADF.Options.pas), [YADF]YADF.Options.WriteDefaultIniTemplate (YADF.Options.pas)</para>
  /// <para>Used in units: YADF.Options</para>
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

/// <returns><!-- drag-lint:auto type -->TYadfOptions</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.DefaultValueStr (YADF.Options.pas), YADF.Options.LoadOptionsFromIni (YADF.Options.pas), YadfMain.RunYadf (YadfMain.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DefaultOptions: TYadfOptions;

// The single authority for every TYadfOptions field. Built once on first call.
/// <summary><!-- drag-lint:auto sum -->The single authority for every TYadfOptions field.
/// Built once on first call.</summary>
/// <returns>Observed: O.MaxLen end,; O.Indent end,; O.TabWidth end,; O.ReflowLines end,; O.TrimTrailing end,; O.MaxBlankLines end,.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.LoadOptionsFromIni (YADF.Options.pas), YADF.Options.OptionsHelpText (YADF.Options.pas), YADF.Options.SaveOptionsToIni (YADF.Options.pas), YADF.Options.WriteDefaultIniTemplate (YADF.Options.pas)</para>
/// <para>Calls: VarToStr, YADF.Options.EncodingToStr, YADF.Options.MakeOpt, YADF.Options.ParseEncoding</para>
/// <para>Returns: GOptTable</para>
/// <seealso cref="YADF.Options.EncodingToStr"/>
/// <seealso cref="YADF.Options.MakeOpt"/>
/// <seealso cref="YADF.Options.ParseEncoding"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OptionTable: TArray<TOptInfo>;

// Encoding name <-> enum, shared by CLI, wizard, GUI, and the INI layer.
/// <summary><!-- drag-lint:auto sum -->Encoding name &lt;-&gt; enum, shared by CLI,
/// wizard, GUI, and the INI layer.</summary>
/// <param name="S"><!-- drag-lint:auto type -->const string</param>
/// <param name="ADefault"><!-- drag-lint:auto type -->const TYadfEncoding</param>
/// <returns>Observed: encUTF8BOM; encUTF16BOM; encANSI; ADefault.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.OptionTable (YADF.Options.pas), YadfMain.ParseFlags (YadfMain.pas)</para>
/// <para>Calls: Trim, UpperCase</para>
/// <para>Returns: encUTF8BOM; encUTF16BOM; encANSI; ADefault</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 13 lines (full implementation)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseEncoding(const S: string; const ADefault: TYadfEncoding): TYadfEncoding;
/// <param name="E"><!-- drag-lint:auto type -->const TYadfEncoding</param>
/// <returns>Observed: 'UTF-8'; 'UTF-16'; 'ANSI'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.OptionTable (YADF.Options.pas)</para>
/// <para>Returns: 'UTF-8'; 'UTF-16'; 'ANSI'</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EncodingToStr(const E: TYadfEncoding): string;

// TYadfEncoding -> the TEncoding used to WRITE it (ANSI / UTF-8 / UTF-16 LE).
/// <summary><!-- drag-lint:auto sum -->TYadfEncoding -&gt; the TEncoding used to WRITE it
/// (ANSI / UTF-8 / UTF-16 LE).</summary>
/// <param name="E"><!-- drag-lint:auto type -->const TYadfEncoding</param>
/// <returns>Observed: TEncoding.UTF8; TEncoding.Unicode; TEncoding.ANSI.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YadfMain.LoadFile (YadfMain.pas), YADFOT.Wizard.FormatFileOnDisk (YADFOT.Wizard.pas)</para>
/// <para>Returns: TEncoding.UTF8; TEncoding.Unicode; TEncoding.ANSI</para>
/// <!-- drag-lint:auto END -->
/// </remarks>

function EncodingOf(const E: TYadfEncoding): TEncoding;

// THE source-encoding detector, shared by the CLI and the wizard so both
// hosts decode and re-encode the same file identically: BOM first (UTF-8,
// UTF-16 LE, UTF-16 BE), then BOM-less content that validates as multi-byte
// UTF-8 (LooksLikeUtf8), else ANSI. APreambleLen is the BOM length to skip on
// read AND re-emit on write -- 0 for BOM-less files, so a detected BOM-less
// UTF-8 file stays BOM-less when preserved.
/// <summary><!-- drag-lint:auto sum -->THE source-encoding detector, shared by the CLI
/// and the wizard so both hosts decode and re-encode the same file identically: BOM first
/// (UTF-8, UTF-16 LE, UTF-16 BE), then BOM-less content that validates as multi-byte
/// UTF-8 (LooksLikeUtf8), else ANSI. APreambleLen is the BOM length to skip on read AND
/// re-emit on write -- 0 for BOM-less files, so a detected BOM-less UTF-8 file stays
/// BOM-less when preserved.</summary>
/// <param name="ABytes"><!-- drag-lint:auto type -->const TBytes</param>
/// <param name="AEnc"><!-- drag-lint:auto type -->out TEncoding</param>
/// <param name="APreambleLen"><!-- drag-lint:auto type -->out Integer</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YadfMain.LoadFile (YadfMain.pas), YADFOT.Wizard.FormatFileOnDisk (YADFOT.Wizard.pas)</para>
/// <para>Calls: YADF.Options.LooksLikeUtf8</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 25 lines (full implementation)</para>
/// <para>Mutates: AEnc (out), APreambleLen (out)</para>
/// <seealso cref="YADF.Options.LooksLikeUtf8"/>
/// <!-- drag-lint:auto END -->
/// </remarks>

procedure DetectSourceEncoding(const ABytes: TBytes; out AEnc: TEncoding; out APreambleLen: Integer);

// Reads a textual boolean (1/0, true/false, yes/no, on/off; case-insensitive);
// unrecognised values return ADefault. Delphi's TIniFile.ReadBool only honours
// numeric 0/1, but yadf.ini ships textual booleans.
/// <param name="AIni"><!-- drag-lint:auto type -->TIniFile</param>
/// <param name="ASection"><!-- drag-lint:auto type -->const string</param>
/// <param name="AIdent"><!-- drag-lint:auto type -->const string</param>
/// <param name="ADefault"><!-- drag-lint:auto type -->Boolean</param>
/// <returns>Observed: ADefault.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.LoadOptionsFromIni (YADF.Options.pas)</para>
/// <para>Calls: LowerCase, YADF.Options.StripIniComment</para>
/// <para>Returns: ADefault</para>
/// <seealso cref="YADF.Options.StripIniComment"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadBoolIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;

// Reads an integer leniently: trims, tolerates a trailing `;` / `//` comment
// after the value, accepts Delphi $-hex; anything unparsable returns ADefault
// (same contract as ReadBoolIni). TIniFile.ReadInteger silently returns the
// default for e.g. "MaxLen=120 ; note" -- the same silent-ignore class as the
// old textual-boolean defect.
/// <summary><!-- drag-lint:auto sum -->Reads an integer leniently: trims, tolerates a
/// trailing `;` / `//` comment after the value, accepts Delphi $-hex; anything unparsable
/// returns ADefault (same contract as ReadBoolIni). TIniFile.ReadInteger silently returns
/// the default for e.g. "MaxLen=120 ; note" -- the same silent-ignore class as the old
/// textual-boolean defect.</summary>
/// <param name="AIni"><!-- drag-lint:auto type -->TIniFile</param>
/// <param name="ASection"><!-- drag-lint:auto type -->const string</param>
/// <param name="AIdent"><!-- drag-lint:auto type -->const string</param>
/// <param name="ADefault"><!-- drag-lint:auto type -->Integer</param>
/// <returns>Observed: ADefault.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.LoadOptionsFromIni (YADF.Options.pas)</para>
/// <para>Calls: Pos, Trim, TryStrToInt</para>
/// <para>Returns: ADefault</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadIntIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Integer): Integer;

// Hint + the compiled-in default rendered live from DefaultOptions -- the ONE
// place the "Default: X" suffix is produced (table hints carry none, so the
// suffix can never drift from the real default). Used by the INI template,
// --help, and the options UIs.
/// <summary><!-- drag-lint:auto sum -->Hint + the compiled-in default rendered live from
/// DefaultOptions -- the ONE place the "Default: X" suffix is produced (table hints carry
/// none, so the suffix can never drift from the real default). Used by the INI template,
/// --help, and the options UIs.</summary>
/// <param name="AInfo"><!-- drag-lint:auto type -->const TOptInfo</param>
/// <returns>Observed: AInfo.Hint + ' Default: ' + D.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.OptionsHelpText (YADF.Options.pas), YADF.Options.WriteDefaultIniTemplate (YADF.Options.pas), YADF.OptionsFrame.TYadfOptionsFrame.BuildControls (YADF.OptionsFrame.pas)</para>
/// <para>Calls: YADF.Options.DefaultValueStr</para>
/// <para>Returns: AInfo.Hint + ' Default: ' + D</para>
/// <seealso cref="YADF.Options.DefaultValueStr"/>
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
/// <summary><!-- drag-lint:auto sum -->True when ABytes are valid UTF-8 AND contain at
/// least one multi-byte sequence. Used by the CLI and the wizard to promote BOM-less
/// files from the blind ANSI fallback to UTF-8 on load (a file that validates as
/// multi-byte UTF-8 is overwhelmingly likely UTF-8; reading it as ANSI mojibakes on
/// rewrite). Pure ASCII returns False -- ANSI and UTF-8 agree there, so the ANSI path
/// stays. Strict: overlong forms, UTF-16 surrogates, &gt;U+10FFFF and truncated sequences
/// all return False.</summary>
/// <param name="ABytes"><!-- drag-lint:auto type -->const TBytes</param>
/// <returns>Observed: False; HasMulti.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.DetectSourceEncoding (YADF.Options.pas)</para>
/// <para>Returns: False; HasMulti</para>
/// <para>Complexity: 22 (cyclomatic, outer body), 56 lines (full implementation)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LooksLikeUtf8(const ABytes: TBytes): Boolean;

// Load every [Format] key into a TYadfOptions, falling back to DefaultOptions
// per field. Returns DefaultOptions unchanged if the file is missing.
/// <summary><!-- drag-lint:auto sum -->Load every [Format] key into a TYadfOptions,
/// falling back to DefaultOptions per field. Returns DefaultOptions unchanged if the file
/// is missing.</summary>
/// <param name="APath"><!-- drag-lint:auto type -->const string</param>
/// <returns>Observed: DefaultOptions.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.OptionsFrame.TYadfOptionsFrame.Commit (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.LoadOptionsFromFile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas), YadfMain.LoadIniDefaults (YadfMain.pas), YADFOT.Wizard.LoadIniDefaults (YADFOT.Wizard.pas)</para>
/// <para>Calls: FileExists, YADF.Options.ClampOptions, YADF.Options.DefaultOptions, YADF.Options.OptionTable, YADF.Options.ReadBoolIni, YADF.Options.ReadIntIni, YADF.Options.StripIniComment</para>
/// <para>Returns: DefaultOptions</para>
/// <seealso cref="YADF.Options.ClampOptions"/>
/// <seealso cref="YADF.Options.DefaultOptions"/>
/// <seealso cref="YADF.Options.OptionTable"/>
/// <seealso cref="YADF.Options.ReadBoolIni"/>
/// <seealso cref="YADF.Options.ReadIntIni"/>
/// <!-- drag-lint:auto END -->
/// </remarks>

function LoadOptionsFromIni(const APath: string): TYadfOptions;

/// <summary>Pulls every integer option that is out of its valid range back to
/// the nearest valid value (negative counts -> 0, MaxLen -> at least 40,
/// TabWidth / LabelMinLines / AlignShapeMinAnchors -> at least 1, Indent ->
/// at most 16).</summary>
/// <param name="AOpts">Options to correct in place.</param>
/// <returns>'' when nothing changed, else a readable list such as
/// 'Indent -3 -> 0, MaxLen 0 -> 40' for a warning.</returns>
/// <remarks>
/// Applied by LoadOptionsFromIni (CLI, wizard, YADFSetup) and by the
/// CLI after its flags. Before 2026-10-14 nothing was checked: Indent=-3 with
/// MaxLen=0 produced zero-indented output with every operator on its own line.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.LoadOptionsFromIni (YADF.Options.pas), YadfMain.RunYadf (YadfMain.pas)</para>
/// <para>Calls: Format, StringReplace, YADF.Options.ClampOptions.Fix</para>
/// <para>Returns: StringReplace(Changes.DelimitedText, ',', ', ', [rfReplaceAll])</para>
/// <seealso cref="YADF.Options.ClampOptions.Fix"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ClampOptions(var AOpts: TYadfOptions): string;

// Persist current values over the commented template (so comments survive).
/// <summary><!-- drag-lint:auto sum -->Persist current values over the commented template
/// (so comments survive).</summary>
/// <param name="AOpts"><!-- drag-lint:auto type -->const TYadfOptions</param>
/// <param name="APath"><!-- drag-lint:auto type -->const string</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.OptionsFrame.TYadfOptionsFrame.Commit (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.NewProfileClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SaveOptionsToFile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas)</para>
/// <para>Calls: IfThen, VarToStr, YADF.Options.EnsureIniExists, YADF.Options.OptionTable</para>
/// <seealso cref="YADF.Options.EnsureIniExists"/>
/// <seealso cref="YADF.Options.OptionTable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);

// One "Ident - Hint" line per option, grouped -- for CLI --help / about text.
/// <summary><!-- drag-lint:auto sum -->One "Ident - Hint" line per option, grouped -- for
/// CLI --help / about text.</summary>
/// <returns>Observed: SB.ToString.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: Format, YADF.Options.OptionHint, YADF.Options.OptionTable</para>
/// <para>Returns: SB.ToString</para>
/// <seealso cref="YADF.Options.OptionHint"/>
/// <seealso cref="YADF.Options.OptionTable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OptionsHelpText: string;  // dl:ok unused-public-symbol@fb3f

// Shared per-user fallback path used by YADF.exe, YADFOT.bpl, and YADFSetup.exe
// when no project-local yadf.ini is found. Returns %APPDATA%\YADF\yadf.ini.
/// <summary><!-- drag-lint:auto sum -->Shared per-user fallback path used by YADF.exe,
/// YADFOT.bpl, and YADFSetup.exe when no project-local yadf.ini is found. Returns
/// %APPDATA%\YADF\yadf.ini.</summary>
/// <returns>Observed: TPath.Combine(.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.ProfilesDir (YADF.Options.pas), YadfMain.DefaultIniPath (YadfMain.pas)</para>
/// <para>Returns: TPath.Combine( TPath.Combine(TPath.GetHomePath, 'YADF'), 'yadf.ini')</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SharedAppDataIniPath: string;

// Write a fully-commented yadf.ini at APath (every option, default, one-line
// explanation), rendered from the descriptor table. Does NOT overwrite an
// existing file's values destructively beyond (re)creating when absent.
/// <summary><!-- drag-lint:auto sum -->Write a fully-commented yadf.ini at APath (every
/// option, default, one-line explanation), rendered from the descriptor table. Does NOT
/// overwrite an existing file's values destructively beyond (re)creating when absent.</summary>
/// <param name="APath"><!-- drag-lint:auto type -->const string</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.EnsureIniExists (YADF.Options.pas)</para>
/// <para>Calls: DirectoryExists, ExtractFilePath, ForceDirectories, YADF.Options.DefaultValueStr, YADF.Options.OptionHint, YADF.Options.OptionTable</para>
/// <seealso cref="YADF.Options.DefaultValueStr"/>
/// <seealso cref="YADF.Options.OptionHint"/>
/// <seealso cref="YADF.Options.OptionTable"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure WriteDefaultIniTemplate(const APath: string);

// If APath does not exist, write the template; otherwise no-op. Returns True
// when a new file was created.
/// <summary><!-- drag-lint:auto sum -->If APath does not exist, write the template;
/// otherwise no-op. Returns True when a new file was created.</summary>
/// <param name="APath"><!-- drag-lint:auto type -->const string</param>
/// <returns>Observed: False; True.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.SaveOptionsToIni (YADF.Options.pas), YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas), YadfMain.DefaultIniPath (YadfMain.pas), YadfMain.RunYadf (YadfMain.pas), YADFOT.Wizard.ResolveOptions (YADFOT.Wizard.pas)</para>
/// <para>Calls: FileExists, YADF.Options.WriteDefaultIniTemplate</para>
/// <para>Returns: False; True</para>
/// <para>Catches: Exception (swallowed)</para>
/// <seealso cref="YADF.Options.WriteDefaultIniTemplate"/>
/// <!-- drag-lint:auto END -->
/// </remarks>

function EnsureIniExists(const APath: string): Boolean;

// ---- IDE formatting profiles ------------------------------------------------
// Two named INI profiles bound to the YADFOT IDE shortcuts: F (Ctrl+Shift+Alt+F,
// also the EXE/CLI default) and R (Ctrl+Shift+Alt+R, YADFOT only). The mapping
// lives in profiles.ini next to the shared yadf.ini; each value is a *.ini file
// name resolved in that same folder. R may be empty (no second profile set).
type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (YADF.Options.pas), declaration (YADF.OptionsFrame.pas), YadfMain.DefaultIniPath (YadfMain.pas)</para>
  /// <para>Used in units: [YADF]YADF.Options, [YADF]YadfMain</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>

  TYadfProfiles = record
    F: string; // INI file name for Ctrl+Shift+Alt+F (defaults to 'yadf.ini')
    R: string; // INI file name for Ctrl+Shift+Alt+R ('' = unassigned)
  end;

  // Folder that holds the shared yadf.ini / profiles.ini (%APPDATA%\YADF).
/// <summary><!-- drag-lint:auto sum -->Folder that holds the shared yadf.ini /
/// profiles.ini (%APPDATA%\YADF).</summary>
/// <returns>Observed: ExtractFilePath(SharedAppDataIniPath).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.ProfilesIniPath (YADF.Options.pas), YADF.Options.ResolveProfileIniPath (YADF.Options.pas), YADF.Options.SaveProfiles (YADF.Options.pas), YadfMain.LogFilePath (YadfMain.pas)</para>
/// <para>Calls: ExtractFilePath, YADF.Options.SharedAppDataIniPath</para>
/// <para>Returns: ExtractFilePath(SharedAppDataIniPath)</para>
/// <seealso cref="YADF.Options.SharedAppDataIniPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProfilesDir: string;

// %APPDATA%\YADF\profiles.ini -- the F/R mapping file.
/// <summary><!-- drag-lint:auto sum -->%APPDATA%\YADF\profiles.ini -- the F/R mapping
/// file.</summary>
/// <returns>Observed: TPath.Combine(ProfilesDir, 'profiles.ini').</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.LoadProfiles (YADF.Options.pas), YADF.Options.SaveProfiles (YADF.Options.pas)</para>
/// <para>Calls: YADF.Options.ProfilesDir</para>
/// <para>Returns: TPath.Combine(ProfilesDir, 'profiles.ini')</para>
/// <para>Touches: file system</para>
/// <seealso cref="YADF.Options.ProfilesDir"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProfilesIniPath: string;

// Read the F/R mapping. Missing file or missing key falls back to F='yadf.ini',
// R='' so existing installs behave exactly as before.
/// <summary><!-- drag-lint:auto sum -->Read the F/R mapping. Missing file or missing key
/// falls back to F='yadf.ini', R='' so existing installs behave exactly as before.</summary>
/// <returns><!-- drag-lint:auto type -->TYadfProfiles</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YadfMain.DefaultIniPath (YadfMain.pas)</para>
/// <para>Calls: FileExists, Trim, YADF.Options.ProfilesIniPath</para>
/// <seealso cref="YADF.Options.ProfilesIniPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadProfiles: TYadfProfiles;

// Persist the F/R mapping (creates the folder/file as needed). Best-effort.
/// <summary><!-- drag-lint:auto sum -->Persist the F/R mapping (creates the folder/file
/// as needed). Best-effort.</summary>
/// <param name="AProfiles"><!-- drag-lint:auto type -->const TYadfProfiles</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.UnassignSelected (YADF.OptionsFrame.pas)</para>
/// <para>Calls: DirectoryExists, ForceDirectories, YADF.Options.ProfilesDir, YADF.Options.ProfilesIniPath</para>
/// <seealso cref="YADF.Options.ProfilesDir"/>
/// <seealso cref="YADF.Options.ProfilesIniPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>

procedure SaveProfiles(const AProfiles: TYadfProfiles);

// Resolve a profile's INI file name to a full path in ProfilesDir. Returns ''
// for an empty name; passes an already-rooted path through unchanged.
/// <summary><!-- drag-lint:auto sum -->Resolve a profile's INI file name to a full path
/// in ProfilesDir. Returns '' for an empty name; passes an already-rooted path through
/// unchanged.</summary>
/// <param name="AFileName"><!-- drag-lint:auto type -->const string</param>
/// <returns>Observed: AFileName; TPath.Combine(ProfilesDir, AFileName).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.MirrorFProfile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.NewProfileClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas), YadfMain.DefaultIniPath (YadfMain.pas), YADFOT.Wizard.DoFormatCurrentBuffer (YADFOT.Wizard.pas), YADFOT.Wizard.ResolveOptions (YADFOT.Wizard.pas)</para>
/// <para>Calls: Trim, YADF.Options.ProfilesDir</para>
/// <para>Returns: AFileName; TPath.Combine(ProfilesDir, AFileName)</para>
/// <para>Touches: file system</para>
/// <seealso cref="YADF.Options.ProfilesDir"/>
/// <!-- drag-lint:auto END -->
/// </remarks>

function ResolveProfileIniPath(const AFileName: string): string;

/// <summary>The exact bytes SaveFile writes for AContent: AEnc-encoded, with AEnc's preamble first only when AWithBOM.</summary>
/// <param name="AContent">Text to encode.</param>
/// <param name="AEnc">Target encoding; must not be nil.</param>
/// <param name="AWithBOM">Prepend AEnc.GetPreamble when True.</param>
/// <returns>Preamble (if any) followed by the encoded text.</returns>
/// <remarks>
/// Pure. Shared by SaveFile and the CLI's --stdout so both emit identical bytes.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Options.SaveFile (YADF.Options.pas), YadfMain.FormatToStdout (YadfMain.pas)</para>
/// <para>Calls: Move</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EncodeForSave(const AContent: string; AEnc: TEncoding; AWithBOM: Boolean): TBytes;

/// <summary>Writes AContent to AFileName as AEnc, crash-safely (temp file + flush + replace).</summary>
/// <param name="AFileName">Target path; an existing file is replaced in place, keeping its attributes, ACL and alternate data streams (ReplaceFileW). A missing file is created.</param>
/// <param name="AContent">Text to encode.</param>
/// <param name="AEnc">Encoding used to write the bytes.</param>
/// <param name="AWithBOM">Prepend AEnc's preamble only when True (pass the pair DetectSourceEncoding found to preserve the input).</param>
/// <exception cref="EOSError">Raised when the temp write or the replace fails; the temp file is removed.</exception>
/// <remarks>
/// Shared by the CLI and the wizard so both hosts write identical bytes. Not thread-safe per target file.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YadfMain.BatchFormat (YadfMain.pas), YadfMain.FormatToFile (YadfMain.pas), YadfMain.ProcessOneFile (YadfMain.pas)</para>
/// <para>Calls: CloseHandle, CreateFileW, DeleteFileW, FlushFileBuffers, GetSystemTimeAsFileTime, MoveFileExW, PWideChar, ReplaceFileW, SetFileTime, SHChangeNotify, YADF.Options.EncodeForSave, YADF.Options.SaveFile.BumpModifiedTime, YADF.Options.SaveFile.WriteAllBytesFlushed</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Touches: file system</para>
/// <seealso cref="YADF.Options.EncodeForSave"/>
/// <seealso cref="YADF.Options.SaveFile.BumpModifiedTime"/>
/// <seealso cref="YADF.Options.SaveFile.WriteAllBytesFlushed"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SaveFile(const AFileName, AContent: string; AEnc: TEncoding; AWithBOM: Boolean);

implementation

uses
  System.StrUtils
  , Winapi.Windows
  , Winapi.ShlObj
  ;

function DefaultOptions: TYadfOptions;
begin
  Result.MaxLen               := 180;
  Result.Indent               := 2;
  Result.TabWidth             := 4;
  Result.MarkUnclosed         := False;
  Result.LabelLongBlocks      := True;
  Result.LabelMinLines        := 15;
  Result.MaxBlankLines        := 1;
  Result.TrimTrailing         := True;
  Result.ReflowLines          := True;
  Result.LowercaseKeywords    := True;
  Result.UpperHexNumbers      := True;
  Result.UpperDirectives      := True;
  Result.FirstOccCasing       := True;
  Result.BlanksBeforeSection  := 0;
  Result.BlanksBeforeMethod   := 0;
  Result.BlanksBeforeType     := 0;
  Result.AssignNoSpaceBefore  := True;
  Result.AssignSpaceAfter     := True;
  Result.SpaceAroundOperators := True;
  Result.AlignConstEquals     := True;
  Result.AlignTypeColon       := True;
  Result.AlignSmartAssign     := True;
  Result.AlignMaxColumn       := 140;  // dl:ok large-magic-number@ee61
  Result.AlignMatchingShapes  := True;
  Result.AlignShapeMinAnchors := 3;
  Result.AlignCommentMaxShift := 7;
  Result.UsesAlwaysBreak      := True;
  Result.UsesCommaLast        := False;
  Result.SplitMultiVarDecls   := True;
  Result.AlignDeclSemicolons  := True;
  Result.BreakCaseLabels      := False;
  Result.IndentComments       := True;
  Result.PackShortBodies      := False;
  Result.CollapseShortBlocks  := False;
  Result.BreakLoopBody        := False;
  Result.BreakWithBody        := False;
  Result.BreakIfBody          := False;
  Result.BreakParamsOnePerLine:= False;
  Result.BreakLongExpressions := True;
  Result.Delphi10Compat       := False;
  Result.Backup               := False;
  Result.BackupDir            := '';
  Result.ResultDir            := '';
  Result.Encoding             := encANSI;
  Result.Logging              := False;
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

// Cuts a trailing inline comment -- `; ...` or `// ...` that starts the value
// or follows whitespace -- and trims. A `;` glued to text (`C:\bak;old`) is
// part of the value. TIniFile returns the raw text after `=`, so without this
// `Key=false ; note` was unparseable and silently fell back to the default.
function StripIniComment(const AValue: string): string;
var
  i          : Integer;
  OpensSlash : Boolean;
  OpensCmt   : Boolean;
  AfterBlank : Boolean;
begin
  Result:= AValue;
  for i:= 1 to Length(Result) do
  begin
    OpensSlash:= (Result[i] = '/') and (i < Length(Result)) and (Result[i + 1] = '/');
    OpensCmt  := (Result[i] = ';') or OpensSlash;
    AfterBlank:= (i = 1) or CharInSet(Result[i - 1], [' ', #9]);
    if OpensCmt and AfterBlank then
    begin
      SetLength(Result, i - 1);
      Break;
    end;
  end; // for
  Result:= Trim(Result);
end; // function

function ReadBoolIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;
var
  S: string;
begin
  S:= LowerCase(StripIniComment(AIni.ReadString(ASection, AIdent, '')));
  if (S = '1') or (S = 'true' ) or (S = 'yes') or (S = 'on' ) then Exit(True );
  if (S = '0') or (S = 'false') or (S = 'no' ) or (S = 'off') then Exit(False);
  Result:= ADefault;
end;

var
  GOptTable: TArray<TOptInfo>;

function MakeOpt(  // dl:ok too-many-parameters@d966
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
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then  // dl:ok magic-literal@b7a3
  begin
    AEnc:= TEncoding.UTF8;
    APreambleLen:= 3;  // dl:ok magic-literal@8373
  end
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then  // dl:ok magic-literal@ffe0
  begin
    AEnc:= TEncoding.Unicode;
    APreambleLen:= 2;
  end
  else if (Length(ABytes) >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then  // dl:ok magic-literal@2361
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
    if B < $80 then  // dl:ok magic-literal@07e1
    begin
      Inc(i);
      Continue;
    end;
    // Lead byte -> continuation count + minimum code point (overlong check).
    if (B >= $C2) and (B <= $DF) then  // dl:ok magic-literal@6617
    begin
      Need:= 1;
      Cp:= B and $1F;  // dl:ok magic-literal@b2fd
      MinCp:= $80;  // dl:ok magic-literal@651b
    end
    else if (B >= $E0) and (B <= $EF) then  // dl:ok magic-literal@af16
    begin
      Need:= 2;
      Cp:= B and $0F;  // dl:ok magic-literal@5946
      MinCp:= $800;  // dl:ok magic-literal@8ac7
    end
    else if (B >= $F0) and (B <= $F4) then  // dl:ok magic-literal@cde8
    begin
      Need:= 3;  // dl:ok magic-literal@090c
      Cp:= B and $07;  // dl:ok magic-literal@f882
      MinCp:= $10000;  // dl:ok magic-literal@a376
    end
    else
      Exit(False); // stray continuation, overlong C0/C1 lead, or F5..FF
    if i + Need >= Len then Exit(False); // truncated sequence at buffer end
    for n:= 1 to Need do
    begin
      B:= ABytes[i + n];
      if (B and $C0) <> $80 then Exit(False);  // dl:ok magic-literal@6d20
      Cp:= (Cp shl 6) or (B and $3F);  // dl:ok magic-literal@83e2
    end;
    if (Cp < MinCp) or (Cp > $10FFFF) or ((Cp >= $D800) and (Cp <= $DFFF)) then  // dl:ok magic-literal@0613
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
    MakeOpt('AlignConstEquals', 'Assignment & alignment', 'Align const =', 'Vertical-align = in const blocks.', okBool, True,  // dl:ok duplicate-code@6078
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
    MakeOpt('AlignShapeMinAnchors', 'Assignment & alignment', 'Shape min anchors', 'Minimum anchors required before shape-alignment kicks in.', okInt, True,  // dl:ok duplicate-code@e615
      function(const O: TYadfOptions): Variant begin Result:= O.AlignShapeMinAnchors end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignShapeMinAnchors:= V end),
    MakeOpt('AlignCommentMaxShift', 'Assignment & alignment', 'Comment max shift', 'Maximum columns a trailing comment may shift when aligning to a shape.', okInt, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignCommentMaxShift end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignCommentMaxShift:= V end),
    MakeOpt('SpaceAroundOperators', 'Spacing', 'Space around operators', 'Put one space around binary operators (A+B -> A + B): + - * / = <= >= <>. '
      + 'Unary +/- and generic brackets (<, >) are left intact.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.SpaceAroundOperators end, procedure(var O: TYadfOptions; const V: Variant) begin O.SpaceAroundOperators:= V end),  // dl:ok duplicate-code@b669
    MakeOpt('UsesAlwaysBreak', 'Uses clauses', 'Break uses one-per-line', 'Always break uses clauses one unit per line.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.UsesAlwaysBreak end, procedure(var O: TYadfOptions; const V: Variant) begin O.UsesAlwaysBreak:= V end),
    MakeOpt('UsesCommaLast', 'Uses clauses', 'Comma-last uses layout', 'Style of the broken (multi-line) uses clause. False (default) is comma-FIRST '
      + '(leading comma, semicolon on its own line) -- the diff-friendly layout. True is ' + 'comma-LAST (trailing comma per unit, semicolon on the last unit''s line: '
      + '"System.Classes;"). Only affects the multi-line form; the inline single-line '
      + 'form is unchanged.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.UsesCommaLast end, procedure(var O: TYadfOptions; const V: Variant) begin O.UsesCommaLast:= V end),
    MakeOpt('SplitMultiVarDecls', 'Declarations', 'Split multi-var decls', 'Split "I, J: integer;" into one line per name so the type colons align.', okBool, True,  // dl:ok duplicate-code@5bae
      function(const O: TYadfOptions): Variant begin Result:= O.SplitMultiVarDecls end, procedure(var O: TYadfOptions; const V: Variant) begin O.SplitMultiVarDecls:= V end),
    MakeOpt('AlignDeclSemicolons', 'Declarations', 'Align decl semicolons', 'After AlignTypeColon, align the trailing ; on consecutive declaration lines.', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.AlignDeclSemicolons end, procedure(var O: TYadfOptions; const V: Variant) begin O.AlignDeclSemicolons:= V end),
    MakeOpt('BreakCaseLabels', 'Declarations', 'Break case labels', 'Break a multi-label case arm ("a, b, c: Stmt;") into one label per line, '
      + 'duplicating the statement. Off by default -- multi-label case arms are kept ' + 'on one line (only genuine variable/field declarations are split, per '
      + 'SplitMultiVarDecls).', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakCaseLabels end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakCaseLabels:= V end),
    MakeOpt('BreakParamsOnePerLine', 'Declarations', 'Break parameters one per line', 'Lay out a routine declaration with one parameter per line ("procedure Go(const A: string; B: Integer);" -> one parameter per line). '
      + 'Fires on named routine declarations with 2 or more parameters; a grouped declaration ("const A, B: string") is split into one name per line, repeating the modifier. '
      + 'Separator placement follows UsesCommaLast. A group carrying an attribute, an interior comment, or an "=" default value is kept whole. '
      + 'Call-site argument lists are never touched. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakParamsOnePerLine end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakParamsOnePerLine:= V end),
    MakeOpt('IndentComments', 'Comments', 'Indent comments', 'Re-indent comment-only lines to the surrounding code depth. When off, every '
      + 'comment keeps the indentation the author gave it. A comment line that starts ' + 'with "//." always keeps its authored indentation even when this is on (an '
      + 'explicit "pin this comment" marker).', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.IndentComments end, procedure(var O: TYadfOptions; const V: Variant) begin O.IndentComments:= V end),  // dl:ok duplicate-code@f6a5
    MakeOpt('PackShortBodies', 'Reflow & whitespace', 'Pack short bodies & case arms', 'When reflowing, pull a SHORT body onto one line: a loop/if header keeps its '
      + 'simple statement ("for I := 0 to N do Inc(X);", "if X then DoIt;") and a case ' + 'arm collapses onto its label ("0: DoZero;"). Off by default -- every body/arm '
      + 'stays on its own line. A nested control header (if/case/begin...) is never '
      + 'half-merged onto a do/then/label either way.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.PackShortBodies end, procedure(var O: TYadfOptions; const V: Variant) begin O.PackShortBodies:= V end),
    MakeOpt('CollapseShortBlocks', 'Reflow & whitespace', 'Collapse short begin..end blocks', 'Fold a short control-statement begin..end body onto one line when it fits '
      + 'MaxLen: an if/for/while/with/else header whose block holds only simple ' + 'one-statement-per-line code becomes "if X then begin A := 1; B := 2; end;". '
      + 'Only pure simple-statement bodies fold -- a nested block, a multi-line ' + 'statement, or any comment leaves the block expanded; routine bodies are '
      + 'never folded. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.CollapseShortBlocks end, procedure(var O: TYadfOptions; const V: Variant) begin O.CollapseShortBlocks:= V end),  // dl:ok duplicate-code@884e
    MakeOpt('BreakLoopBody', 'Reflow & whitespace', 'Break loop body onto its own line', 'Force the body of a single-line for/while loop onto its own indented line '
      + '("while X do Dec(k);" -> "while X do" + newline + "  Dec(k);"). A begin block, '
      + 'a nested control header, or a body with a trailing comment is left alone. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakLoopBody end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakLoopBody:= V end),
    MakeOpt('BreakWithBody', 'Reflow & whitespace', 'Break with body onto its own line', 'Force the body of a single-line with..do statement onto its own indented line. '
      + 'Same guard rails as BreakLoopBody (begin/nested-header/comment bodies left alone). Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakWithBody end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakWithBody:= V end),
    MakeOpt('BreakIfBody', 'Reflow & whitespace', 'Break if/then/else body onto its own line', 'Force the then/else body of a single-line if statement onto its own indented line '  // dl:ok duplicate-code@0d05
      + '("if X then A else B;" -> "if X then" / "  A" / "else" / "  B;"). "else if" chains stay '
      + 'glued; a begin/nested-header/comment body is left alone. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakIfBody end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakIfBody:= V end),
    MakeOpt('BreakLongExpressions', 'Reflow & whitespace', 'Smart expression breakup', 'ON (default): when a line exceeds MaxLen, break it at every top-level operator -- one component per line, with the connecting operator LEADING each line ("and X" / "or Y"). '
      + 'A parenthesised group is one component and stays whole; a component that still does not fit is broken the same way, one indent step deeper. '
      + 'A trailing "then" or "do" moves to its own line at the column of the "if" / "while" that introduced it. '
      + 'Lines that already fit are never touched. OFF reverts to the greedy breaker, which packs as many components per line as fit.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakLongExpressions end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakLongExpressions:= V end),
    MakeOpt('Delphi10Compat', 'Delphi 10 compatibility', 'Downgrade inline vars',
      'Hoist inline var declarations into a top-of-routine var block so the code builds on Delphi 10.2.3. Explicit types and simple literals are converted; the rest get a // TODO -oYADF marker. Best-effort, unverified on a real Tokyo toolchain.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.Delphi10Compat end, procedure(var O: TYadfOptions; const V: Variant) begin O.Delphi10Compat:= V end),
    MakeOpt('LabelLongBlocks', 'Labels & markers', 'Label long blocks', 'After a block longer than LabelMinLines, mark its end with the block keyword: "end; // while", "end; // procedure".', okBool, True,
      function(const O: TYadfOptions): Variant begin Result:= O.LabelLongBlocks end, procedure(var O: TYadfOptions; const V: Variant) begin O.LabelLongBlocks:= V end),
    MakeOpt('LabelMinLines', 'Labels & markers', 'Label min lines', 'Minimum lines a block must span before LabelLongBlocks adds the marker.', okInt, True,  // dl:ok duplicate-code@2f84
      function(const O: TYadfOptions): Variant begin Result:= O.LabelMinLines end, procedure(var O: TYadfOptions; const V: Variant) begin O.LabelMinLines:= V end),
    MakeOpt('MarkUnclosed', 'Labels & markers', 'Mark unclosed blocks', 'When an opening begin/record/... has no matching end, add "// TODO -oYADF : ''begin'' on line N has no matching ''end''".', okBool, True,
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

function ClampOptions(var AOpts: TYadfOptions): string;
const
  MIN_MAX_LEN = 40;
  MAX_INDENT  = 16;
var
  Changes: TStringList;

  procedure Fix(const AName: string; var AValue: Integer; AMin, AMax: Integer);
  var
    Was: Integer;
  begin
    Was:= AValue;
    if AValue < AMin then
      AValue:= AMin
    else if AValue > AMax then
      AValue:= AMax;
    if AValue <> Was then
      Changes.Add(Format('%s %d -> %d', [AName, Was, AValue]));
  end;

begin
  Changes:= TStringList.Create;
  try
    Fix('MaxLen'              , AOpts.MaxLen              , MIN_MAX_LEN, MaxInt    );
    Fix('Indent'              , AOpts.Indent              , 0          , MAX_INDENT);
    Fix('TabWidth'            , AOpts.TabWidth            , 1          , MAX_INDENT);
    Fix('LabelMinLines'       , AOpts.LabelMinLines       , 1          , MaxInt    );
    Fix('MaxBlankLines'       , AOpts.MaxBlankLines       , 0          , MaxInt    );
    Fix('BlanksBeforeSection' , AOpts.BlanksBeforeSection , 0          , MaxInt    );
    Fix('BlanksBeforeMethod'  , AOpts.BlanksBeforeMethod  , 0          , MaxInt    );
    Fix('BlanksBeforeType'    , AOpts.BlanksBeforeType    , 0          , MaxInt    );
    Fix('AlignMaxColumn'      , AOpts.AlignMaxColumn      , 0          , MaxInt    );
    Fix('AlignShapeMinAnchors', AOpts.AlignShapeMinAnchors, 1          , MaxInt    );
    Fix('AlignCommentMaxShift', AOpts.AlignCommentMaxShift, 0          , MaxInt    );
    Changes.Delimiter      := ',';
    Changes.StrictDelimiter:= True;
    Result:= StringReplace(Changes.DelimitedText, ',', ', ', [rfReplaceAll]);
  finally
    Changes.Free;
  end;
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
        if Ini.ValueExists('Format', T[i].Ident) then
          T[i].SetVal(Result, StripIniComment(Ini.ReadString('Format', T[i].Ident, '')));
    end;
  finally
    Ini.Free;
  end; // try
  ClampOptions(Result); // an INI value out of range is corrected, not obeyed
end; // function

procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);
var
  Ini : TIniFile        ;
  T   : TArray<TOptInfo>;
  i   : Integer         ;
  IVal: Integer         ;
  BVal: Boolean         ;
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
        IVal:= T[i].GetVal(AOpts);
        Ini.WriteInteger('Format', T[i].Ident, IVal);
      end;
      okBool:
      begin
        BVal:= T[i].GetVal(AOpts);
        Ini.WriteString('Format', T[i].Ident, IfThen(BVal, 'true', 'false'));
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
  BVal: Boolean     ;
begin
  D:= DefaultOptions;
  case AInfo.Kind of  // dl:ok case-with-too-few-branches@6f14
    okBool:
    begin
      BVal:= AInfo.GetVal(D);
      Result:= IfThen(BVal, 'true', 'false');
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
  except  // dl:ok bare-except@79dc
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

function EncodeForSave(const AContent: string; AEnc: TEncoding; AWithBOM: Boolean): TBytes;
var
  Bytes   : TBytes;
  Preamble: TBytes;
begin
  if AWithBOM then
    Preamble:= AEnc.GetPreamble
  else
    Preamble:= nil;
  Bytes:= AEnc.GetBytes(AContent);
  SetLength(Result, Length(Preamble) + Length(Bytes));
  if Length(Preamble) > 0 then
    Move(Preamble[0], Result[0], Length(Preamble));
  if Length(Bytes) > 0 then
    Move(Bytes[0], Result[Length(Preamble)], Length(Bytes));
end;

procedure SaveFile(const AFileName, AContent: string; AEnc: TEncoding; AWithBOM: Boolean);

  procedure WriteAllBytesFlushed(const AFile: string; const ABytes: TBytes);
  var
    Stream: TFileStream;
  begin
    Stream:= TFileStream.Create(AFile, fmCreate or fmShareDenyWrite);
    try
      if Length(ABytes) > 0 then
        Stream.WriteBuffer(ABytes[0], Length(ABytes));
      FlushFileBuffers(Stream.Handle);
    finally
      Stream.Free;
    end;
  end;

  procedure BumpModifiedTime(const AFile: string);
  var
    H : THandle  ;
    Ft: TFileTime;
  begin
    H:= CreateFileW(PWideChar(AFile), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if H = INVALID_HANDLE_VALUE then
      Exit;
    try
      GetSystemTimeAsFileTime(Ft);
      SetFileTime(H, nil, nil, @Ft);
    finally
      CloseHandle(H);
    end;
  end;

var
  All: TBytes;
  Tmp: string;
begin
  All:= EncodeForSave(AContent, AEnc, AWithBOM);

  Tmp:= AFileName + '.yadf-tmp';
  try
    WriteAllBytesFlushed(Tmp, All);
    if TFile.Exists(AFileName) then
    begin
      // ReplaceFileW keeps the target's attributes, ACL and alternate data streams.
      if not ReplaceFileW(PWideChar(AFileName), PWideChar(Tmp), nil, 0, nil, nil) then
        RaiseLastOSError;
    end
    else if not MoveFileExW(PWideChar(Tmp), PWideChar(AFileName), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except  // dl:ok bare-except@98bb
    DeleteFileW(PWideChar(Tmp));
    raise;
  end;
  BumpModifiedTime(AFileName);
  SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, PWideChar(AFileName), nil);
end;

end.

