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
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.IniFiles,
  System.Variants;

type
  TYadfEncoding = (encANSI, encUTF8BOM, encUTF16BOM);

  TYadfOptions = record
    MaxLen             : Integer;
    Indent             : Integer;
    TabWidth           : Integer;
    MarkUnclosed       : Boolean;
    LabelLongBlocks    : Boolean;
    LabelMinLines      : Integer;
    MaxBlankLines      : Integer;
    TrimTrailing       : Boolean;
    ReflowLines        : Boolean;
    LowercaseKeywords  : Boolean;
    UpperHexNumbers    : Boolean;
    UpperDirectives    : Boolean;
    FirstOccCasing     : Boolean;
    BlanksBeforeSection: Integer;
    BlanksBeforeMethod : Integer;
    BlanksBeforeType   : Integer;
    AssignNoSpaceBefore: Boolean;
    AssignSpaceAfter   : Boolean;
    SpaceAroundOperators: Boolean;
    AlignConstEquals   : Boolean;
    AlignTypeColon     : Boolean;
    AlignSmartAssign   : Boolean;
    AlignMaxColumn     : Integer;
    AlignMatchingShapes: Boolean;
    AlignShapeMinAnchors: Integer;
    AlignCommentMaxShift: Integer;
    UsesAlwaysBreak    : Boolean;
    SplitMultiVarDecls : Boolean;
    AlignDeclSemicolons: Boolean;
    Backup             : Boolean;
    BackupDir          : string;
    ResultDir          : string;
    Encoding           : TYadfEncoding;
    Logging            : Boolean;
  end; // record

  // ---- Single descriptor table : the settings authority ----
  TOptKind = (okBool, okInt, okString, okEnum);

  TOptGetter = reference to function(const O: TYadfOptions): Variant;
  TOptSetter = reference to procedure(var O: TYadfOptions; const V: Variant);

  TOptInfo = record
    Ident         : string;      // INI key under [Format] AND the record field name
    Group         : string;      // UI group + template section header
    Caption       : string;      // GUI label
    Hint          : string;      // one-line help: GUI tooltip, ';' comment, --help line
    Kind          : TOptKind;
    AffectsPreview: Boolean;     // False for file/CLI-only options
    GetVal        : TOptGetter;
    SetVal        : TOptSetter;
  end;

function DefaultOptions: TYadfOptions;

// The single authority for every TYadfOptions field. Built once on first call.
function OptionTable: TArray<TOptInfo>;

// Encoding name <-> enum, shared by CLI, wizard, GUI, and the INI layer.
function ParseEncoding(const S: string; const ADefault: TYadfEncoding): TYadfEncoding;
function EncodingToStr(const E: TYadfEncoding): string;

// Reads a textual boolean (1/0, true/false, yes/no, on/off; case-insensitive);
// unrecognised values return ADefault. Delphi's TIniFile.ReadBool only honours
// numeric 0/1, but yadf.ini ships textual booleans.
function ReadBoolIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;

// Load every [Format] key into a TYadfOptions, falling back to DefaultOptions
// per field. Returns DefaultOptions unchanged if the file is missing.
function LoadOptionsFromIni(const APath: string): TYadfOptions;

// Persist current values over the commented template (so comments survive).
procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);

// One "Ident - Hint" line per option, grouped -- for CLI --help / about text.
function OptionsHelpText: string;

// Shared per-user fallback path used by YADF.exe, YADFOT.bpl, and YADFSetup.exe
// when no project-local yadf.ini is found. Returns %APPDATA%\YADF\yadf.ini.
function SharedAppDataIniPath: string;

// Write a fully-commented yadf.ini at APath (every option, default, one-line
// explanation), rendered from the descriptor table. Does NOT overwrite an
// existing file's values destructively beyond (re)creating when absent.
procedure WriteDefaultIniTemplate(const APath: string);

// If APath does not exist, write the template; otherwise no-op. Returns True
// when a new file was created.
function EnsureIniExists(const APath: string): Boolean;

implementation

uses
  System.StrUtils;

function DefaultOptions: TYadfOptions;
begin
  Result.MaxLen             := 180    ;
  Result.Indent             := 2      ;
  Result.TabWidth           := 4      ;
  Result.MarkUnclosed       := False  ;
  Result.LabelLongBlocks    := True   ;
  Result.LabelMinLines      := 15     ;
  Result.MaxBlankLines      := 1      ;
  Result.TrimTrailing       := True   ;
  Result.ReflowLines        := True   ;
  Result.LowercaseKeywords  := True   ;
  Result.UpperHexNumbers    := True   ;
  Result.UpperDirectives    := True   ;
  Result.FirstOccCasing     := True   ;
  Result.BlanksBeforeSection:= 0      ;
  Result.BlanksBeforeMethod := 0      ;
  Result.BlanksBeforeType   := 0      ;
  Result.AssignNoSpaceBefore:= True   ;
  Result.AssignSpaceAfter   := True   ;
  Result.SpaceAroundOperators := True ;
  Result.AlignConstEquals   := True   ;
  Result.AlignTypeColon     := True   ;
  Result.AlignSmartAssign   := True   ;
  Result.AlignMaxColumn     := 140    ;
  Result.AlignMatchingShapes := True  ;
  Result.AlignShapeMinAnchors := 3    ;
  Result.AlignCommentMaxShift := 7    ;
  Result.UsesAlwaysBreak    := True   ;
  Result.SplitMultiVarDecls := True   ;
  Result.AlignDeclSemicolons:= True   ;
  Result.Backup             := False  ;
  Result.BackupDir          := ''     ;
  Result.ResultDir          := ''     ;
  Result.Encoding           := encANSI;
  Result.Logging            := False  ;
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
end;

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

function MakeOpt(const AIdent, AGroup, ACaption, AHint: string; AKind: TOptKind;
  AAffects: Boolean; const AGet: TOptGetter; const ASet: TOptSetter): TOptInfo;
begin
  Result.Ident := AIdent;
  Result.Group := AGroup;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Kind := AKind;
  Result.AffectsPreview := AAffects;
  Result.GetVal := AGet;
  Result.SetVal := ASet;
end;

function OptionTable: TArray<TOptInfo>;
begin
  if Length(GOptTable) > 0 then Exit(GOptTable);
  GOptTable := [
    MakeOpt('MaxLen', 'Line length & indentation', 'Max line length',
      'Maximum line length in columns. Long lines are reflowed when ReflowLines is true. Default: 180',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.MaxLen end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.MaxLen := V end),
    MakeOpt('Indent', 'Line length & indentation', 'Indent step',
      'Indentation step in spaces (each nesting level adds this many). Default: 2',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.Indent end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Indent := V end),
    MakeOpt('TabWidth', 'Line length & indentation', 'Tab width',
      'Width assumed for an existing tab on input. YADF always emits spaces. Default: 4',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.TabWidth end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.TabWidth := V end),
    MakeOpt('ReflowLines', 'Reflow & whitespace', 'Reflow long lines',
      'Reflow lines that exceed MaxLen. When false, long lines are left as-is. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.ReflowLines end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.ReflowLines := V end),
    MakeOpt('TrimTrailing', 'Reflow & whitespace', 'Trim trailing spaces',
      'Trim trailing whitespace from every output line. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.TrimTrailing end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.TrimTrailing := V end),
    MakeOpt('MaxBlankLines', 'Reflow & whitespace', 'Max blank lines',
      'Maximum consecutive blank lines kept in output. Excess blanks are collapsed. Default: 1',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.MaxBlankLines end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.MaxBlankLines := V end),
    MakeOpt('BlanksBeforeSection', 'Reflow & whitespace', 'Blanks before section',
      'Blank lines forced before each interface section. 0 = no change. Default: 0',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.BlanksBeforeSection end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeSection := V end),
    MakeOpt('BlanksBeforeMethod', 'Reflow & whitespace', 'Blanks before method',
      'Blank lines forced before each method body. Default: 0',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.BlanksBeforeMethod end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeMethod := V end),
    MakeOpt('BlanksBeforeType', 'Reflow & whitespace', 'Blanks before type',
      'Blank lines forced before each top-level type declaration. Default: 0',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.BlanksBeforeType end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeType := V end),
    MakeOpt('LowercaseKeywords', 'Casing', 'Lowercase keywords',
      'Lowercase Pascal keywords (begin, end, if, then ...). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.LowercaseKeywords end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.LowercaseKeywords := V end),
    MakeOpt('UpperHexNumbers', 'Casing', 'Uppercase hex',
      'Uppercase hex digits in numeric literals ($AB not $ab). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.UpperHexNumbers end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.UpperHexNumbers := V end),
    MakeOpt('UpperDirectives', 'Casing', 'Uppercase directives',
      'Uppercase compiler-directive keywords ({$IFDEF}, {$R+} ...). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.UpperDirectives end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.UpperDirectives := V end),
    MakeOpt('FirstOccCasing', 'Casing', 'First-occurrence casing',
      'Cascade casing from the first occurrence of each identifier to all later uses. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.FirstOccCasing end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.FirstOccCasing := V end),
    MakeOpt('AssignNoSpaceBefore', 'Assignment & alignment', 'No space before :=',
      'No space BEFORE := ("X:= 1" not "X := 1"). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AssignNoSpaceBefore end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AssignNoSpaceBefore := V end),
    MakeOpt('AssignSpaceAfter', 'Assignment & alignment', 'Space after :=',
      'Single space AFTER := ("X:= 1" not "X:=1"). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AssignSpaceAfter end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AssignSpaceAfter := V end),
    MakeOpt('AlignConstEquals', 'Assignment & alignment', 'Align const =',
      'Vertical-align = in const blocks. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignConstEquals end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignConstEquals := V end),
    MakeOpt('AlignTypeColon', 'Assignment & alignment', 'Align type :',
      'Vertical-align : in type / var / parameter blocks. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignTypeColon end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignTypeColon := V end),
    MakeOpt('AlignSmartAssign', 'Assignment & alignment', 'Smart-align',
      'Master switch for the shape-aware alignment pass: aligns := runs and ' +
      '(when "Align matching shapes" is on) any matching structural shapes ' +
      'across consecutive lines. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignSmartAssign end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignSmartAssign := V end),
    MakeOpt('AlignMaxColumn', 'Assignment & alignment', 'Align max column',
      'Maximum column an alignment may push to. Past this, alignment is skipped. Default: 140',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignMaxColumn end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignMaxColumn := V end),
    MakeOpt('AlignMatchingShapes', 'Assignment & alignment', 'Align matching shapes',
      'Align matching "shapes" (record-init lines, repeated field declarations). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignMatchingShapes end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignMatchingShapes := V end),
    MakeOpt('AlignShapeMinAnchors', 'Assignment & alignment', 'Shape min anchors',
      'Minimum anchors required before shape-alignment kicks in. Default: 3',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignShapeMinAnchors end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignShapeMinAnchors := V end),
    MakeOpt('AlignCommentMaxShift', 'Assignment & alignment', 'Comment max shift',
      'Maximum columns a trailing comment may shift when aligning to a shape. Default: 7',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignCommentMaxShift end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignCommentMaxShift := V end),
    MakeOpt('SpaceAroundOperators', 'Spacing', 'Space around operators',
      'Put one space around binary operators (A+B -> A + B): + - * / = <= >= <>. ' +
      'Unary +/- and generic brackets (<, >) are left intact. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.SpaceAroundOperators end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.SpaceAroundOperators := V end),
    MakeOpt('UsesAlwaysBreak', 'Uses clauses', 'Break uses one-per-line',
      'Always break uses clauses one unit per line. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.UsesAlwaysBreak end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.UsesAlwaysBreak := V end),
    MakeOpt('SplitMultiVarDecls', 'Declarations', 'Split multi-var decls',
      'Split "I, J: integer;" into one line per name so the type colons align. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.SplitMultiVarDecls end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.SplitMultiVarDecls := V end),
    MakeOpt('AlignDeclSemicolons', 'Declarations', 'Align decl semicolons',
      'After AlignTypeColon, align the trailing ; on consecutive declaration lines. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignDeclSemicolons end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignDeclSemicolons := V end),
    MakeOpt('LabelLongBlocks', 'Labels & markers', 'Label long blocks',
      'Insert "// end of <Name>" markers after long blocks. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.LabelLongBlocks end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.LabelLongBlocks := V end),
    MakeOpt('LabelMinLines', 'Labels & markers', 'Label min lines',
      'Minimum lines a block must span before LabelLongBlocks adds the marker. Default: 15',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.LabelMinLines end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.LabelMinLines := V end),
    MakeOpt('MarkUnclosed', 'Labels & markers', 'Mark unclosed blocks',
      'Add a "// UNCLOSED" marker when an opening keyword has no matching close. Default: false',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.MarkUnclosed end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.MarkUnclosed := V end),
    MakeOpt('Backup', 'File & CLI (no preview effect)', 'Backup before overwrite',
      'Create a backup of every file before overwriting it. Default: false',
      okBool, False,
      function(const O: TYadfOptions): Variant begin Result := O.Backup end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Backup := V end),
    MakeOpt('BackupDir', 'File & CLI (no preview effect)', 'Backup directory',
      'Directory for backups (used when Backup=true). Empty = next to original file. Default: empty',
      okString, False,
      function(const O: TYadfOptions): Variant begin Result := O.BackupDir end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BackupDir := VarToStr(V) end),
    MakeOpt('ResultDir', 'File & CLI (no preview effect)', 'Result directory',
      'Directory for formatted output. Empty = format in place. Default: empty',
      okString, False,
      function(const O: TYadfOptions): Variant begin Result := O.ResultDir end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.ResultDir := VarToStr(V) end),
    MakeOpt('Encoding', 'File & CLI (no preview effect)', 'Output encoding',
      'File encoding to write: ANSI, UTF-8 (with BOM), or UTF-16 (with BOM). Default: ANSI',
      okEnum, False,
      function(const O: TYadfOptions): Variant begin Result := EncodingToStr(O.Encoding) end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Encoding := ParseEncoding(VarToStr(V), encANSI) end),
    MakeOpt('Logging', 'File & CLI (no preview effect)', 'Logging',
      'Write a log file with details of every option resolved and file processed. Default: false',
      okBool, False,
      function(const O: TYadfOptions): Variant begin Result := O.Logging end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Logging := V end)
  ];
  Result := GOptTable;
end;

function LoadOptionsFromIni(const APath: string): TYadfOptions;
var
  Ini: TIniFile;
  T  : TArray<TOptInfo>;
  i  : Integer;
begin
  Result := DefaultOptions;
  if (APath = '') or (not FileExists(APath)) then Exit;
  T := OptionTable;
  Ini := TIniFile.Create(APath);
  try
    for i := 0 to High(T) do
      case T[i].Kind of
        okInt:
          T[i].SetVal(Result, Ini.ReadInteger('Format', T[i].Ident, T[i].GetVal(Result)));
        okBool:
          T[i].SetVal(Result, ReadBoolIni(Ini, 'Format', T[i].Ident, T[i].GetVal(Result)));
        okString, okEnum:
          T[i].SetVal(Result, Ini.ReadString('Format', T[i].Ident, VarToStr(T[i].GetVal(Result))));
      end;
  finally
    Ini.Free;
  end;
end;

procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);
var
  Ini : TIniFile;
  T   : TArray<TOptInfo>;
  i   : Integer;
  iVal: Integer;
  bVal: Boolean;
begin
  // Ensure the commented template exists first so WinAPI INI writes update
  // values in place and leave the ';' comment lines intact.
  EnsureIniExists(APath);
  T := OptionTable;
  Ini := TIniFile.Create(APath);
  try
    for i := 0 to High(T) do
      case T[i].Kind of
        okInt :
          begin
            iVal := T[i].GetVal(AOpts);
            Ini.WriteInteger('Format', T[i].Ident, iVal);
          end;
        okBool:
          begin
            bVal := T[i].GetVal(AOpts);
            Ini.WriteString('Format', T[i].Ident, IfThen(bVal, 'true', 'false'));
          end;
        okString, okEnum:
            Ini.WriteString('Format', T[i].Ident, VarToStr(T[i].GetVal(AOpts)));
      end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

function SharedAppDataIniPath: string;
begin
  // TPath.GetHomePath on Windows = %APPDATA% (Roaming). Subdirectory
  // is `YADF` (family name) -- YADF.exe, YADFOT.bpl and YADFSetup.exe all
  // write/read here so they always converge on the same file.
  Result:= TPath.Combine(
    TPath.Combine(TPath.GetHomePath, 'YADF'), 'yadf.ini');
end;

function DefaultValueStr(const AInfo: TOptInfo): string;
var
  D   : TYadfOptions;
  bVal: Boolean;
begin
  D := DefaultOptions;
  case AInfo.Kind of
    okBool:
      begin
        bVal := AInfo.GetVal(D);
        Result := IfThen(bVal, 'true', 'false');
      end;
  else
    Result := VarToStr(AInfo.GetVal(D));
  end;
end;

procedure WriteDefaultIniTemplate(const APath: string);
var
  L      : TStringList;
  DirName: string;
  T      : TArray<TOptInfo>;
  i      : Integer;
  CurGrp : string;
begin
  DirName:= ExtractFilePath(APath);
  if (DirName <> '') and (not DirectoryExists(DirName)) then
    ForceDirectories(DirName);
  T := OptionTable;
  L:= TStringList.Create;
  try
    L.Add('; YADF -- Yet Another Delphi Formatter');
    L.Add('; Default configuration. Edit values and re-run.');
    L.Add('; Lines starting with `;` are comments.');
    L.Add('; CLI flags override these values; --ini <path> overrides location.');
    L.Add('');
    L.Add('[Format]');
    CurGrp := '';
    for i := 0 to High(T) do
    begin
      if T[i].Group <> CurGrp then
      begin
        CurGrp := T[i].Group;
        L.Add('');
        L.Add('; ---- ' + CurGrp + ' ----');
      end;
      L.Add('');
      L.Add('; ' + T[i].Hint);
      L.Add(T[i].Ident + ' = ' + DefaultValueStr(T[i]));
    end;
    L.SaveToFile(APath, TEncoding.ANSI);
  finally
    L.Free;
  end;
end;

function OptionsHelpText: string;
var
  T     : TArray<TOptInfo>;
  i     : Integer;
  CurGrp: string;
  SB    : TStringBuilder;
begin
  T := OptionTable;
  SB := TStringBuilder.Create;
  try
    CurGrp := '';
    for i := 0 to High(T) do
    begin
      if T[i].Group <> CurGrp then
      begin
        CurGrp := T[i].Group;
        SB.AppendLine;
        SB.AppendLine('  [' + CurGrp + ']');
      end;
      SB.AppendLine(Format('    %-22s %s', [T[i].Ident, T[i].Hint]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

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
end;

end.
