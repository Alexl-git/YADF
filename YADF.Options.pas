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
  System.IOUtils;

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

function DefaultOptions: TYadfOptions;

// Shared per-user fallback path used by both YADF.exe and YADFOT.bpl
// when no project-local yadf.ini is found anywhere in the walk-up
// hierarchy. Returns %APPDATA%\YADF\yadf.ini -- subdirectory is named
// after the family, not the specific tool, so the EXE and BPL find
// the same file regardless of which one ran first.
function SharedAppDataIniPath: string;

// Write a fully-commented yadf.ini at APath with every option, its
// default value, and a one-line explanation. Used on first run when no
// INI exists -- the user sees the file appear and can edit it. Safe
// to call if directory does not exist (it gets created). Does NOT
// overwrite an existing file.
procedure WriteDefaultIniTemplate(const APath: string);

// Convenience: if APath does not exist, write the template; otherwise
// no-op. Returns True when a new file was created (so callers can
// surface a 'created default config at X' status line).
function EnsureIniExists(const APath: string): Boolean;

implementation

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

function SharedAppDataIniPath: string;
begin
  // TPath.GetHomePath on Windows = %APPDATA% (Roaming). Subdirectory
  // is `YADF` (family name) -- both YADF.exe and YADFOT.bpl write/read
  // here so they always converge on the same file.
  Result:= TPath.Combine(
    TPath.Combine(TPath.GetHomePath, 'YADF'), 'yadf.ini');
end;

procedure WriteDefaultIniTemplate(const APath: string);
var
  L      : TStringList;
  DirName: string;
begin
  DirName:= ExtractFilePath(APath);
  if (DirName <> '') and (not DirectoryExists(DirName)) then
    ForceDirectories(DirName);
  L:= TStringList.Create;
  try
    L.Add('; YADF -- Yet Another Delphi Formatter');
    L.Add('; Default configuration. Edit values and re-run.');
    L.Add('; Lines starting with `;` are comments.');
    L.Add('; CLI flags override these values; --ini <path> overrides location.');
    L.Add('');
    L.Add('[Format]');
    L.Add('');
    L.Add('; ---- Line length & indentation -------------------------------');
    L.Add('');
    L.Add('; Maximum line length in columns. Long lines are reflowed when');
    L.Add('; ReflowLines is true.  Default: 180');
    L.Add('MaxLen = 180');
    L.Add('');
    L.Add('; Indentation step in spaces (each nesting level adds this many).');
    L.Add('; Default: 2');
    L.Add('Indent = 2');
    L.Add('');
    L.Add('; Width assumed for an existing tab character on input. YADF');
    L.Add('; always emits spaces; this only affects how tabs are counted');
    L.Add('; while reading. Default: 4');
    L.Add('TabWidth = 4');
    L.Add('');
    L.Add('; ---- Reflow & whitespace -------------------------------------');
    L.Add('');
    L.Add('; Reflow lines that exceed MaxLen. When false, long lines are');
    L.Add('; left as-is. Default: true');
    L.Add('ReflowLines = true');
    L.Add('');
    L.Add('; Trim trailing whitespace from every output line. Default: true');
    L.Add('TrimTrailing = true');
    L.Add('');
    L.Add('; Maximum number of consecutive blank lines kept in output.');
    L.Add('; Excess blanks are collapsed.  Default: 1');
    L.Add('MaxBlankLines = 1');
    L.Add('');
    L.Add('; Blank lines forced before each interface section (uses,');
    L.Add('; type, const, var, procedure, function...). 0 = no change.');
    L.Add('; Default: 0');
    L.Add('BlanksBeforeSection = 0');
    L.Add('');
    L.Add('; Blank lines forced before each method body. Default: 0');
    L.Add('BlanksBeforeMethod = 0');
    L.Add('');
    L.Add('; Blank lines forced before each top-level type declaration.');
    L.Add('; Default: 0');
    L.Add('BlanksBeforeType = 0');
    L.Add('');
    L.Add('; ---- Casing --------------------------------------------------');
    L.Add('');
    L.Add('; Lowercase Pascal keywords (begin, end, if, then ...).');
    L.Add('; Default: true');
    L.Add('LowercaseKeywords = true');
    L.Add('');
    L.Add('; Uppercase hex digits in numeric literals ($AB instead of $ab).');
    L.Add('; Default: true');
    L.Add('UpperHexNumbers = true');
    L.Add('');
    L.Add('; Uppercase compiler-directive keywords ({$IFDEF}, {$R+}, ...).');
    L.Add('; Default: true');
    L.Add('UpperDirectives = true');
    L.Add('');
    L.Add('; Cascade casing from the FIRST occurrence of each identifier');
    L.Add('; in the file to all later uses. Useful when the codebase has');
    L.Add('; inconsistent casing.  Default: true');
    L.Add('FirstOccCasing = true');
    L.Add('');
    L.Add('; ---- Assignment & alignment ----------------------------------');
    L.Add('');
    L.Add('; No space BEFORE `:=` ("X:= 1" not "X := 1"). Default: true');
    L.Add('AssignNoSpaceBefore = true');
    L.Add('');
    L.Add('; Single space AFTER `:=` ("X:= 1" not "X:=1"). Default: true');
    L.Add('AssignSpaceAfter = true');
    L.Add('');
    L.Add('; Vertical-align `=` in const blocks. Default: true');
    L.Add('AlignConstEquals = true');
    L.Add('');
    L.Add('; Vertical-align `:` in type / var / parameter blocks.');
    L.Add('; Default: true');
    L.Add('AlignTypeColon = true');
    L.Add('');
    L.Add('; Smart-align `:=` across consecutive assignment statements.');
    L.Add('; Default: true');
    L.Add('AlignSmartAssign = true');
    L.Add('');
    L.Add('; Maximum column an alignment is allowed to push to. Past this,');
    L.Add('; alignment is skipped so a single long identifier does not');
    L.Add('; shove the whole group right.  Default: 140');
    L.Add('AlignMaxColumn = 140');
    L.Add('');
    L.Add('; Align matching "shapes" (e.g. record-init lines, repeated');
    L.Add('; record-field declarations). Default: true');
    L.Add('AlignMatchingShapes = true');
    L.Add('');
    L.Add('; Minimum number of anchors required before shape-alignment');
    L.Add('; kicks in. Default: 3');
    L.Add('AlignShapeMinAnchors = 3');
    L.Add('');
    L.Add('; Maximum columns a trailing comment is allowed to shift when');
    L.Add('; aligning to a shape.  Default: 7');
    L.Add('AlignCommentMaxShift = 7');
    L.Add('');
    L.Add('; ---- Uses clauses --------------------------------------------');
    L.Add('');
    L.Add('; Always break `uses` clauses one unit per line. Default: true');
    L.Add('UsesAlwaysBreak = true');
    L.Add('');
    L.Add('; ---- var / const / field declaration splitting --------------');
    L.Add('');
    L.Add('; Split combined declarations like `I, J: integer;` into one');
    L.Add('; line per name (`I: integer;` + `J: integer;`) so the type');
    L.Add('; colons align cleanly. Applies to top-level var/const blocks');
    L.Add('; and record/class field declarations. Does NOT touch parameter');
    L.Add('; lists inside `(...)` (that would change procedure signatures).');
    L.Add('; Default: true');
    L.Add('SplitMultiVarDecls = true');
    L.Add('');
    L.Add('; After AlignTypeColon, also align the trailing `;` on');
    L.Add('; consecutive declaration lines so the right edge is flush.');
    L.Add('; Only fires on lines that look like `name : type;` -- regular');
    L.Add('; statement semicolons are not touched. Default: true');
    L.Add('AlignDeclSemicolons = true');
    L.Add('');
    L.Add('; ---- Labels & markers ----------------------------------------');
    L.Add('');
    L.Add('; Insert "// end of <Name>" markers after long blocks.');
    L.Add('; Default: true');
    L.Add('LabelLongBlocks = true');
    L.Add('');
    L.Add('; Minimum lines a block must span before LabelLongBlocks adds');
    L.Add('; the marker.  Default: 15');
    L.Add('LabelMinLines = 15');
    L.Add('');
    L.Add('; Add a "// UNCLOSED" marker comment when an opening keyword');
    L.Add('; (begin/case/try) has no matching close. Default: false');
    L.Add('MarkUnclosed = false');
    L.Add('');
    L.Add('; ---- Backup & output -----------------------------------------');
    L.Add('');
    L.Add('; Create a backup of every file before overwriting it.');
    L.Add('; Default: false');
    L.Add('Backup = false');
    L.Add('');
    L.Add('; Directory for backups (used when Backup=true). Empty = next');
    L.Add('; to original file with .bak.NN suffix. Default: empty');
    L.Add('BackupDir =');
    L.Add('');
    L.Add('; Directory for formatted output (--result-dir style). Empty =');
    L.Add('; format in place. Default: empty');
    L.Add('ResultDir =');
    L.Add('');
    L.Add('; File encoding to write: ANSI, UTF-8 (with BOM), or UTF-16');
    L.Add('; (with BOM). Default: ANSI');
    L.Add('Encoding = ANSI');
    L.Add('');
    L.Add('; ---- Logging --------------------------------------------------');
    L.Add('');
    L.Add('; Write a log file alongside YADF.exe / YADFOT.bpl with details');
    L.Add('; of every option resolved and every file processed.');
    L.Add('; Default: false');
    L.Add('Logging = false');
    L.SaveToFile(APath, TEncoding.ANSI);
  finally
    L.Free;
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
    // Best-effort: a read-only location (Program Files, archive bit,
    // permissions) is non-fatal -- the run still proceeds with the
    // compiled defaults.  Logging this would require a logger here
    // but we'd rather not pull one in; callers can detect by checking
    // FileExists(APath) post-call.
    Result:= False;
  end;
end;

end.
