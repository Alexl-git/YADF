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

unit YadfMain;

// YADF - Yet Another Delphi Formatter
// =====================================
//
// CATALOG OF FORMATTING RULES (Pass 1)
// -------------------------------------
//
// Line budget
// -----------
// - Every emitted line of code must fit within MaxLen (default 180) chars.
// - Lines that contain // line-comments or string literals are exempt: a
//   long comment or string can extend past MaxLen and is left alone.
//
// Whitespace
// ----------
// - Output line endings are always CRLF, regardless of input.
// - Consecutive blank lines are collapsed to MaxBlankLines (default 1).
// - Leading whitespace tabs are converted to spaces; one tab = TabWidth
//   spaces (default 4). Tabs inside strings/comments are preserved.
// - Trailing whitespace on each line is removed (TrimTrailing default on).
//
// Capitalization
// --------------
// - Reserved keywords are lowercased: begin/end/if/else/var/etc.
//   (LowercaseKeywords default on).
// - Hex digits in $-prefixed numbers and exponent E in floats are
//   uppercased: $FF, 1E5 (UpperHexNumbers default on).
// - Compiler-directive names are uppercased: {$IFDEF}, {$DEFINE}
//   (UpperDirectives default on).
// - Identifiers are normalized to their first occurrence's casing
//   throughout the file (FirstOccCasing default on). Pascal is
//   case-insensitive, so this is semantically safe.
//
// Reflow (full reflow when ReflowLines on)
// ----------------------------------------
// - User's existing line breaks are dropped where not structurally
//   required. Adjacent lines that fit MaxLen when joined are merged.
// - Block boundaries that ALWAYS break: lines ending in `;`, `.`, `}`,
//   `begin`, `end`, `try`, `finally`, `except`, `repeat`, `asm`, `of`,
//   `record`, section keywords, visibility keywords. Lines starting with
//   `begin`, `end`, `interface`, `implementation`, `type`, `var`, `const`,
//   `procedure`, `function`, visibility, `uses`, `//`, `{$`.
// - When joining at `(` or `[`, no space is inserted. When the next
//   token starts with `)`, `]`, `,`, `;`, `.` ? same.
//
// Blank-line enforcement (each defaults to 0; INI options)
// --------------------------------------------------------
// - BlanksBeforeSection: ensure N blank lines before interface/
//   implementation/initialization/finalization keywords.
// - BlanksBeforeMethod: before procedure/function/constructor/destructor
//   declarations at top level.
// - BlanksBeforeType: before the `type` keyword.
//
// Round-trip + idempotency
// ------------------------
// - The internal --check mode emits tokens byte-faithfully.
// - The format pipeline is idempotent: format(format(x)) == format(x).
//
// Uses clauses
// ------------
// - When UsesAlwaysBreak is on (default), every uses/contains/requires
//   clause is rendered one identifier per line in comma-first style,
//   regardless of whether it would fit on a single line. The closing
//   semicolon is placed on its own line at the same column as the
//   leading commas. Example:
//       uses
//         System.SysUtils
//       , System.Classes
//       ;
// - When UsesAlwaysBreak is off, the clause stays inline if it fits in
//   MaxLen and contains no `in 'path'` items; otherwise it breaks (and
//   the semicolon still goes on its own line in broken form).
//
// Parens and brackets
// -------------------
// - If a parens or brackets group with multiple comma-separated items
//   would overflow, it is broken:
//       Header(
//           item1,                     items at LineWS + 2*Indent
//           item2,
//           item3
//       );                             close at LineWS (same as opener)
// - The opening paren/bracket stays on the previous line. The closing
//   paren/bracket goes on its own line at the indent of the opener.
// - An inline brace comment that follows a comma on the same source
//   line as that comma sticks with the preceding item.
// - If an item itself overflows AND is a single nested parens/brackets
//   group with multiple items, that sub-group is recursively broken.
//
// Operator chains
// ---------------
// - For long lines containing + - or and xor operators (with surrounding
//   spaces), the line is broken with the operator leading the next line
//   (greedy fill: pack operands onto each line until the next would
//   overflow, then break before that operator).
// - Operators inside parens count too (depth-aware).
//
// Long argument lists inside parens
// ---------------------------------
// - If after operator-chain breaking a line is still too long and
//   contains a comma inside parens (any depth), the line is broken
//   after the comma so the next argument starts on a new line.
//
// Block-end labels
// ----------------
// - When LabelLongBlocks is on (default), any block (begin, record,
//   case, try, asm, object) spanning more than LabelMinLines output
//   lines (default 15) gets a trailing comment with the introducing
//   keyword: end; // while, end; // for, end; // procedure, etc.
// - For begin/end, the keyword is found by walking back to the nearest
//   while / for / if / else / procedure / function / constructor /
//   destructor / try / initialization / finalization.
// - If the closing line already ends with a // comment, no label added.
//
// Unclosed-block markers (--mark-unclosed, off by default)
// --------------------------------------------------------
// - Pascal source with an unmatched begin/record/etc. is force-closed in
//   the group parser.
// - When --mark-unclosed is enabled, each force-closed opener emits a
//   // TODO -oYADF : '<keyword>' on line N has no matching 'end'  // dl:ok compiler-magic-comments@e3b0
//   comment at end-of-file. Innermost unclosed block first.
// - The dedup check skips emission if an identical marker already
//   appears in the source.
//
// Out-of-scope / untouched
// ------------------------
// - Content inside block comments is never reformatted.
// - Content inside string literals is never altered.
// - A class/record type body is not tracked as a structural group by
//   ParseGroups; its indentation and `end` alignment are handled by the
//   re-indentation pass instead.

interface

uses
  System.SysUtils
  ;

type
  /// <summary>Raised for a malformed command line -- an unknown flag, a
  /// missing required value, or an unresolvable path/spec. Signals user
  /// error rather than an internal fault, so the top-level handler in
  /// YADF.dpr can print the message and a usage hint instead of an
  /// "internal error" style report.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (YADF.dpr) ?, YadfMain.ExpandFileSpec (YadfMain.pas), YadfMain.ExtractIniPath (YadfMain.pas), YadfMain.ParseFlags (YadfMain.pas), YadfMain.ParseFlags.NextValue (YadfMain.pas)</para>
  /// <para>Used in units: YADF, YadfMain</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  EYadfUsage = class(Exception);

/// <exception cref="EYadfUsage"><!-- drag-lint:auto exc -->via YadfMain.ExpandFileSpec: Directory not found:; via YadfMain.ExtractIniPath: --ini and --no-ini cannot be combined; via YadfMain.ParseFlags (+4 more)</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: main block (YADF.dpr)</para>
/// <para>Calls: Default, ExpandFileName, Format, LowerCase, ParamStr, Trim, Writeln, YADF.Options.DefaultOptions, YADF.Options.EnsureIniExists, YADF.Options.ReadOptionsFromIni (+17 more)</para>
/// <para>Complexity: 29 (cyclomatic, outer body), 185 lines (full implementation)</para>
/// <seealso cref="YADF.Options.DefaultOptions"/>
/// <seealso cref="YADF.Options.EnsureIniExists"/>
/// <seealso cref="YADF.Options.ReadOptionsFromIni"/>
/// <seealso cref="YADF.Options.ResolveOptions"/>
/// <seealso cref="YadfMain.BatchFormat"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure RunYadf;

implementation

uses
  Winapi.Windows
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , System.Math
  , SimpleParser.Lexer.Types
  , YADF.Tokens
  , YADF.Options
  , YADF.Groups
  , YADF.Layout
  , YADF.Debug
  ;

const
  /// <summary>Process exit code: at least one file was declined by the content guard and left unchanged (no failures).</summary>
  EXIT_DECLINED = 3;
  /// <summary>Process exit code: at least one file failed (read/format/write error). Fixed value, never the failure count, so it cannot collide with EXIT_DECLINED.</summary>
  EXIT_FAILED = 1;
  /// <summary>Argument count of the --batch mode: --batch, a list file and an output directory.</summary>
  BATCH_ARG_COUNT = 3;

/// <summary>Records a guard decline in the process exit code.</summary>
/// <remarks>Only lifts a clean 0 to EXIT_DECLINED; a failure code already set is never masked.</remarks>
procedure NoteDecline;
begin
  if ExitCode = 0 then
    ExitCode:= EXIT_DECLINED;
end;

/// <summary>Writes a MESSAGE (a `wrote` / `declined` line, a `--- file ---`
/// header, a FAIL line, the debug tree) to stdout.</summary>
/// <param name="S">The message text; nothing is written when empty.</param>
/// <remarks>Task 10: ANSI bytes turned a non-ANSI file name into `?`. On a console
/// the text goes out as UTF-16 (WriteConsoleW), so every character shows. Redirected
/// (a pipe or a file, e.g. drag-lint reading YADF's output) the bytes stay ANSI --
/// what the existing consumers decode -- unless the text has a character the ANSI
/// code page cannot hold; that text is written as UTF-8 instead of being damaged.
/// Formatted source text never goes through here (WriteStdoutBytes, exact bytes).</remarks>
procedure WriteStdoutRaw(const S: string);
var
  Bytes  : TBytes;
  Written: DWORD ;
  Mode   : DWORD ;
  Handle : THandle;
begin
  if S = '' then
    Exit;
  Handle:= GetStdHandle(STD_OUTPUT_HANDLE);
  if GetConsoleMode(Handle, Mode) then
  begin
    // A console that refuses the write falls through to the byte path.
    if WriteConsoleW(Handle, PChar(S), Length(S), Written, nil) then
      Exit;
  end;
  Bytes:= TEncoding.ANSI.GetBytes(S);
  if TEncoding.ANSI.GetString(Bytes) <> S then
    Bytes:= TEncoding.UTF8.GetBytes(S);
  WriteFile(Handle, Bytes[0], Length(Bytes), Written, nil);  // dl:ok ignored-must-use-result@e5cb -- a failed stdout write (closed pipe) has no channel left to report on; same as WriteStdoutBytes
end;

procedure WriteStdoutBytes(const ABytes: TBytes);
var
  Written: DWORD;
begin
  if Length(ABytes) = 0 then
    Exit;
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), ABytes[0], Length(ABytes), Written, nil);  // dl:ok ignored-must-use-result@51a4 -- a failed stdout write (closed pipe) has no channel left to report on; same as WriteStdoutRaw
end;

procedure WriteStdoutLine(const S: string);
begin
  WriteStdoutRaw(S + sLineBreak);
end;

var
  GLogPath   : string ;
  GLogEnabled: Boolean;

function LogFilePath: string;
begin
  // %APPDATA%\YADF (Roaming), beside yadf.ini -- NOT beside the exe, which is
  // read-only once installed under Program Files. LogMsg creates the folder.
  if GLogPath = '' then
    GLogPath:= TPath.Combine(ProfilesDir, 'yadf-startup.log');
  Result:= GLogPath;
end;

procedure LogMsg(const S: string);
var
  Line: string;
begin
  if not GLogEnabled then
    Exit;
  Line:= FormatDateTime('hh:nn:ss.zzz ', Now) + S;
  OutputDebugString(PChar('[YADF] ' + Line));  // dl:ok outputdebugstring@70fb
  try
    ForceDirectories(ExtractFilePath(LogFilePath));  // dl:ok ignored-must-use-result@7caf -- a folder that cannot be made fails the AppendAllText below, which the except mirrors to OutputDebugString
    TFile.AppendAllText(LogFilePath, Line + sLineBreak, TEncoding.ANSI);
  except
    on E: Exception do
      // Never let a logging failure break the run -- but don't let it be
      // invisible either. OutputDebugString mirrors the write attempt above.
      OutputDebugString(PChar('[YADF] log write failed: ' + E.Message));  // dl:ok outputdebugstring@60f9
  end;
end;

// TYadfEncoding -> display name ('ANSI' / 'UTF-8-BOM' / 'UTF-16-BOM'); shared by
// the startup log and the --help banner.
function EncName(E: TYadfEncoding): string;
begin
  case E of
    encUTF8BOM : Result:= 'UTF-8-BOM';
    encUTF16BOM: Result:= 'UTF-16-BOM';
    else
      Result:= 'ANSI';
  end;
end;

procedure LogStartup(const AArgs: TArray<string>; const AOpts: TYadfOptions; const AIniPath: string);

  function BoolStr(B: Boolean): string;
  begin
    Result:= if B then 'true' else 'false';
  end;

var
  i: Integer;
begin
  if not GLogEnabled then
    Exit;
  LogMsg('==== YADF startup ====');
  LogMsg('  CWD:       ' + GetCurrentDir);
  LogMsg('  Exe:       ' + ParamStr(0));
  LogMsg('  INI:       ' + AIniPath      );
  LogMsg('  RawCmd:    ' + GetCommandLine);
  LogMsg('  Args[' + IntToStr(Length(AArgs)) + ']:');
  for i:= 0 to High(AArgs) do
    LogMsg('    [' + IntToStr(i) + '] ' + AArgs[i]);
  LogMsg('  Resolved options:');
  LogMsg('    ResultDir       = ' + AOpts.ResultDir);
  LogMsg('    Backup          = ' + BoolStr(AOpts.Backup));
  LogMsg('    BackupDir       = ' + AOpts.BackupDir);
  LogMsg('    BackupKeep      = ' + IntToStr(AOpts.BackupKeep));
  LogMsg('    Encoding        = ' + EncName(AOpts.Encoding       ));
  LogMsg('    UsesAlwaysBreak = ' + BoolStr(AOpts.UsesAlwaysBreak));
end; // begin

// Read AFileName by DETECTING its encoding (shared DetectSourceEncoding: BOM,
// else BOM-less multi-byte UTF-8, else ANSI) -- detection is independent of
// the options, so a conversion request can never decode the file wrongly.
// AWriteEnc/AWriteBOM say how the file should be written BACK: Encoding=ANSI
// (the default) means "ANSI, or preserve what was detected" -- the file keeps
// its own encoding and BOM-ness; an explicit utf8/utf16 setting is a
// conversion request applied at WRITE time only (+BOM).
function LoadFile(const AFileName: string; const AOpts: TYadfOptions; out AWriteEnc: TEncoding; out AWriteBOM: Boolean): string; overload;
var
  Bytes   : TBytes   ;
  Detected: TEncoding;
  PreLen  : Integer  ;
begin
  Bytes:= TFile.ReadAllBytes(AFileName);
  DetectSourceEncoding(Bytes, Detected, PreLen);
  Result:= Detected.GetString(Bytes, PreLen, Length(Bytes) - PreLen);
  if AOpts.Encoding = encANSI then
  begin
    AWriteEnc:= Detected; // preserve mode: write back as read
    AWriteBOM:= PreLen > 0;
  end
  else
  begin
    AWriteEnc:= EncodingOf(AOpts.Encoding); // explicit conversion (+BOM)
    AWriteBOM:= True;
  end;
end; // function

function LoadFile(const AFileName: string; const AOpts: TYadfOptions): string; overload;
var
  WEnc: TEncoding;
  WBom: Boolean  ;
begin
  Result:= LoadFile(AFileName, AOpts, WEnc, WBom);
end;


function RoundTrip(const ASource: string): string;
var
  Tokens: TTokenList;
begin
  Tokens:= LoadTokensFromString(ASource);
  try
    Result:= EmitTokens(Tokens);
  finally
    Tokens.Free;
  end;
end;

function FirstDiffIndex(const A, B: string): Integer;
var
  i: Integer;
  n: Integer;
begin
  n:= Length(A);
  if Length(B) < n then
    n:= Length(B);
  for i:= 1 to n do if A[i] <> B[i] then
    Exit(i);
  if Length(A) <> Length(B) then
    Exit(n + 1);
  Result:= 0;
end;

function CheckFile(const AFileName: string; const AOpts: TYadfOptions; out FirstDiff: Integer): Boolean;
var
  Output: string;
  Source: string;
begin
  Source:= LoadFile(AFileName, AOpts);
  Output:= RoundTrip(Source);
  FirstDiff:= FirstDiffIndex(Source, Output);
  Result:= FirstDiff = 0;
end;

procedure FormatToStdout(const AFileName: string; const AOpts: TYadfOptions);
var
  Source  : string  ;
  Declined: string  ;
  WEnc    : TEncoding;
  WBom    : Boolean ;
begin
  Source:= LoadFile(AFileName, AOpts, WEnc, WBom);
  // The exact bytes --o / in-place would write (detected or explicit encoding, BOM iff the file would carry one).
  WriteStdoutBytes(EncodeForSave(FormatSource(Source, AOpts, Declined), WEnc, WBom));
  // stdout carries the (unchanged) source; the decline note goes to stderr so
  // pipelines still work while the user learns the file was left as-is.
  if Declined <> '' then
  begin
    Writeln(ErrOutput, 'declined ' + AFileName + ' (content guard: ' + Declined + ') -- output is the unchanged input');
    NoteDecline;
  end;
end;

function ProcessOneFile(const AFile: string; const AOpts: TYadfOptions): Boolean; forward;

procedure FormatToFile(const AInFile, AOutFile: string; const AOpts: TYadfOptions);
var
  Dir     : string      ;
  Source  : string      ;
  Declined: string      ;
  WEnc    : TEncoding   ;
  WBom    : Boolean     ;
  InPlace : TYadfOptions;
begin
  // `--o <the input itself>` is an in-place format: unchanged check and
  // backup apply, exactly as without --o (review 2026-10-14).
  if SameFileName(ExpandFileName(AInFile), ExpandFileName(AOutFile)) then
  begin
    InPlace:= AOpts;
    InPlace.ResultDir:= '';
    if not ProcessOneFile(AInFile, InPlace) then
      ExitCode:= 1;
    Exit;
  end;
  try
    Source:= LoadFile(AInFile, AOpts, WEnc, WBom);
    Dir:= TPath.GetDirectoryName(AOutFile);
    if Dir <> '' then
      TDirectory.CreateDirectory(Dir);
    SaveFile(AOutFile, FormatSource(Source, AOpts, Declined), WEnc, WBom);
  except
    // Same contract as the in-place path (ProcessOneFile): a failed read or
    // write (read-only target, locked file, bad path) is a reported FAILURE
    // with exit 1, not an unhandled exception (exit 2).
    on E: Exception do
    begin
      LogMsg('    FAIL ' + E.ClassName + ': ' + E.Message);
      WriteStdoutLine(Format('FAIL  %s  (%s: %s)', [AInFile, E.ClassName, E.Message]));
      ExitCode:= EXIT_FAILED;
      Exit;
    end;
  end;
  if Declined <> '' then
  begin
    WriteStdoutLine('declined ' + AInFile + ' (content guard: ' + Declined + ') -- wrote the unchanged input');
    NoteDecline;
  end
  else
    WriteStdoutLine('wrote ' + AOutFile);
end; // procedure

// Width the backup numbers are zero-padded to so that text order = numeric order.
const
  BACKUP_KEY_WIDTH = 20;

/// <summary>The sort key of AName when it is a backup YADF itself names for the
/// file ABase, else ''. Sibling form: ABase.BCKn (key = n). Folder form:
/// ABase.yyyymmdd-hhnnss[-n].bak (key = stamp + collision number).</summary>
/// <param name="AName">A file name (no path) found in the backup location.</param>
/// <param name="ABase">The file name (no path) whose backups are wanted.</param>
/// <param name="ASibling">True for the ABase.BCKn form, False for the .bak form.</param>
/// <returns>A key that sorts oldest-first as plain text, or '' for any other name.</returns>
/// <remarks>The match is anchored and ABase is escaped, so a different file's
/// backups (xABase..., ABase2...) can never match.</remarks>
function BackupSortKey(const AName, ABase: string; ASibling: Boolean): string;
var
  M: TMatch;
begin
  Result:= '';
  if ASibling then
  begin
    M:= TRegEx.Match(AName, '^' + TRegEx.Escape(ABase) + '\.BCK(\d+)$', [roIgnoreCase]);
    if M.Success then
      Result:= M.Groups[1].Value.PadLeft(BACKUP_KEY_WIDTH, '0');
  end
  else
  begin
    M:= TRegEx.Match(AName, '^' + TRegEx.Escape(ABase) + '\.(\d{8}-\d{6})(?:-(\d+))?\.bak$', [roIgnoreCase]);
    if M.Success then
      Result:= M.Groups[1].Value + '|' + (if (M.Groups.Count > 2) and (M.Groups[2].Value <> '') then M.Groups[2].Value else '1').PadLeft(BACKUP_KEY_WIDTH, '0');
  end;
end; // function

function NextSiblingBackupName(const AFile: string): string;
var
  Base: string;
  Dir : string;
  F   : string;
  Key : string;
  n   : Integer;
  Top : Integer;
begin
  Dir := ExtractFilePath(AFile);
  Base:= ExtractFileName(AFile);
  // One above the highest existing number (never a freed lower one), so the
  // numbers stay in age order even after BackupKeep has pruned the old ones.
  Top:= 0;
  for F in TDirectory.GetFiles(if Dir = '' then '.' else Dir, Base + '.*') do
  begin
    Key:= BackupSortKey(ExtractFileName(F), Base, True);
    n:= StrToIntDef(Key, 0);
    if n > Top then
      Top:= n;
  end;
  Result:= TPath.Combine(Dir, Base + '.BCK' + IntToStr(Top + 1));
end;

/// <summary>Deletes the older backups of AFile beyond the newest AKeep.</summary>
/// <param name="AFile">The file that was just backed up.</param>
/// <param name="ABackupDir">The backup folder; empty = the siblings next to AFile.</param>
/// <param name="AKeep">How many backups to keep; 0 or less keeps all.</param>
/// <remarks>Only names BackupOriginalFile itself generates for this exact file
/// are candidates (see BackupSortKey). A backup that cannot be deleted is logged
/// and left; it never fails the run.</remarks>
procedure PruneBackups(const AFile, ABackupDir: string; AKeep: Integer);
var
  Base : string     ;
  Dir  : string     ;
  F    : string     ;
  i    : Integer    ;
  Key  : string     ;
  Found: TStringList;
begin
  if AKeep <= 0 then
    Exit;
  Base:= ExtractFileName(AFile);
  Dir:= if Trim(ABackupDir) = '' then ExtractFilePath(AFile) else ABackupDir;
  Found:= TStringList.Create;
  try
    for F in TDirectory.GetFiles(if Dir = '' then '.' else Dir, Base + '.*') do
    begin
      Key:= BackupSortKey(ExtractFileName(F), Base, Trim(ABackupDir) = '');
      if Key <> '' then
        Found.Add(Key + #9 + F);
    end;
    Found.CaseSensitive:= True;
    Found.Sort;
    for i:= 0 to Found.Count - AKeep - 1 do
    try
      TFile.Delete(Copy(Found[i], Pos(#9, Found[i]) + 1, MaxInt));
    except
      on E: Exception do
        LogMsg('    backup prune failed: ' + Found[i] + ' (' + E.Message + ')');
    end;
  finally
    Found.Free;
  end;
end; // procedure
/// <summary>Copies AFile to a new backup (sibling .BCKn, or a timestamped .bak in
/// ABackupDir), then prunes this file's older backups beyond the newest AKeep.</summary>
/// <param name="AFile">The file about to be overwritten.</param>
/// <param name="ABackupDir">Backup folder; empty = next to AFile.</param>
/// <param name="AKeep">BackupKeep option; 0 keeps every backup.</param>
procedure BackupOriginalFile(const AFile: string; const ABackupDir: string; AKeep: Integer);
var
  F     : string ;
  Key   : string ;
  Stamp : string ;
  Target: string ;
  n     : Integer;
begin
  if Trim(ABackupDir) = '' then
  begin
    Target:= NextSiblingBackupName(AFile);
    TFile.Copy(AFile, Target, True);
    PruneBackups(AFile, ABackupDir, AKeep);
    Exit;
  end;
  if not TDirectory.Exists(ABackupDir) then
    TDirectory.CreateDirectory(ABackupDir);
  Stamp:= FormatDateTime('yyyymmdd-hhnnss', Now);
  Target:= TPath.Combine(ABackupDir, ExtractFileName(AFile) + '.' + Stamp + '.bak');
  // Two inputs with the same basename in one second used to share this name
  // and the second Copy overwrote the first file's only backup. Never
  // overwrite: number the collision instead.
  // Number above every backup of this file made in this second, not just the
  // first free name: once BackupKeep pruned the unnumbered one, reusing its
  // name would file the NEWEST backup as the oldest and prune it at once.
  n:= 1;
  for F in TDirectory.GetFiles(ABackupDir, ExtractFileName(AFile) + '.' + Stamp + '*') do
  begin
    Key:= BackupSortKey(ExtractFileName(F), ExtractFileName(AFile), False);
    if Key <> '' then
      n:= Max(n, StrToIntDef(Copy(Key, Pos('|', Key) + 1, MaxInt), 1));
  end;
  if n > 1 then
  begin
    Target:= TPath.Combine(ABackupDir, ExtractFileName(AFile) + '.' + Stamp + '-' + IntToStr(n + 1) + '.bak');
    Inc(n);
  end;
  while TFile.Exists(Target) do
  begin
    Inc(n);
    Target:= TPath.Combine(ABackupDir, ExtractFileName(AFile) + '.' + Stamp + '-' + IntToStr(n) + '.bak');
  end;
  TFile.Copy(AFile, Target, False);
  PruneBackups(AFile, ABackupDir, AKeep);
end; // procedure

// True when AArg names a source input rather than a folder: a .pas/.dpr/
// .dproj/.dpk/.inc file name or a wildcard spec.
function LooksLikeSourceSpec(const AArg: string): Boolean;
const
  SOURCE_EXTS: array[0..4] of string = ('.pas', '.dpr', '.dproj', '.dpk', '.inc');
var
  Ext: string;
begin
  if AArg.Contains('*') or AArg.Contains('?') then
    Exit(True);
  Ext:= ExtractFileExt(AArg);
  for var S in SOURCE_EXTS do
    if SameText(Ext, S) then
      Exit(True);
  Result:= False;
end;

procedure CheckDir(const ADir: string; const AOpts: TYadfOptions);
var
  Diff : Integer       ;
  F    : string        ;
  Fail : Integer       ;
  Files: TArray<string>;
  Pass : Integer       ;
begin
  Files:= TDirectory.GetFiles(ADir, '*.pas', TSearchOption.soAllDirectories);
  Pass:= 0;
  Fail:= 0;
  for F in Files do
  begin
    if CheckFile(F, AOpts, Diff) then
    begin
      Inc(Pass);
      WriteStdoutLine('PASS  ' + F);
    end
    else
    begin
      Inc(Fail);
      WriteStdoutLine(Format('FAIL  %s  (first diff at byte %d)', [F, Diff]));
    end;
  end; // for
  WriteStdoutLine(Format('--- %d pass, %d fail ---', [Pass, Fail]));
  if Fail > 0 then
    ExitCode:= 1;
end; // procedure

procedure BatchFormat(const AInDir, AOutDir: string; const AOpts: TYadfOptions);
var
  Count   : Integer       ;
  F       : string        ;
  Files   : TArray<string>;
  OutVal    : string        ;
  RelName : string        ;
  Source  : string        ;
  Declined: string        ;
  WEnc    : TEncoding     ;
  WBom    : Boolean       ;
begin
  if not TDirectory.Exists(AInDir) then
  begin
    WriteStdoutLine('error: input directory not found: ' + AInDir);
    ExitCode:= 1;
    Exit;
  end;
  // Batch writes every result, declined ones included, with no backup: it
  // must never target the input folder itself (review 2026-10-14).
  if SameFileName(ExcludeTrailingPathDelimiter(ExpandFileName(AInDir)), ExcludeTrailingPathDelimiter(ExpandFileName(AOutDir))) then
  begin
    WriteStdoutLine('error: --batch output folder is the input folder -- use in-place mode (with --b) instead');
    ExitCode:= 1;
    Exit;
  end;
  TDirectory.CreateDirectory(AOutDir);
  Files:= TDirectory.GetFiles(AInDir, '*.pas', TSearchOption.soTopDirectoryOnly);
  Count:= 0;
  for F in Files do
  begin
    Source:= LoadFile(F, AOpts, WEnc, WBom);
    RelName:= ExtractFileName(F);
    OutVal:= TPath.Combine(AOutDir, RelName);
    SaveFile(OutVal, FormatSource(Source, AOpts, Declined), WEnc, WBom);
    if Declined <> '' then
    begin
      WriteStdoutLine(Format('declined %s (content guard: %s) -- wrote the unchanged input', [F, Declined]));
      NoteDecline;
    end
    else
      WriteStdoutLine(Format('wrote %s', [OutVal]));
    Inc(Count);
  end; // for
  WriteStdoutLine(Format('--- %d file(s) formatted into %s ---', [Count, AOutDir]));
end; // procedure

function ParseDprUnits(const ADprFile: string; const AOpts: TYadfOptions): TArray<string>;
var
  CurName    : string       ;
  EndIdx     : Integer      ;
  FilePath   : string       ;
  i          : Integer      ;
  InInClause : Boolean      ;
  Items      : TList<string>;
  Raw        : string       ;
  ResolvedDir: string       ;
  Source     : string       ;
  T          : TToken       ;
  Tokens     : TTokenList   ;
  UsesIdx    : Integer      ;
begin
  Source:= LoadFile(ADprFile, AOpts);
  ResolvedDir:= ExtractFilePath     (ADprFile);
  Tokens     := LoadTokensFromString(Source  );
  Items:= TList<string>.Create;
  try
    Items.Add(ADprFile);
    UsesIdx:= -1;
    for i:= 0 to Tokens.Count - 1 do if Tokens[i].Kind = ptUses then
    begin
      UsesIdx:= i;
      Break;
    end;
    if UsesIdx < 0 then
      Exit(Items.ToArray);
    EndIdx:= Tokens.Count - 1;
    for i:= UsesIdx + 1 to Tokens.Count - 1 do if Tokens[i].Kind = ptSemiColon then
    begin
      EndIdx:= i;
      Break;
    end;
    CurName   := '';
    FilePath  := '';
    InInClause:= False;
    for i:= UsesIdx + 1 to EndIdx do
    begin
      T:= Tokens[i];
      case T.Kind of
        ptIdentifier: if not InInClause then
          CurName:= CurName + T.Text;  // dl:ok concat-in-loop@c25a
        ptPoint: if not InInClause then
          CurName:= CurName + '.';  // dl:ok concat-in-loop@c83e
        ptIn         : InInClause:= True;
        ptStringConst: if InInClause then
        begin
          Raw:= T.Text;
          FilePath:= if (Length(Raw) >= 2) and (Raw[1] = '''') and (Raw[Length(Raw)] = '''') then Copy(Raw, 2, Length(Raw) - 2) else Raw;
        end;
        ptComma, ptSemiColon:
        begin
          if Trim(CurName) <> '' then
          begin
            if FilePath = '' then
            begin
              FilePath:= TPath.Combine(ResolvedDir, CurName + '.pas');
              if TFile.Exists(FilePath) then
                Items.Add(FilePath);
            end
            else
            begin
              if not TPath.IsPathRooted(FilePath) then
                FilePath:= TPath.Combine(ResolvedDir, FilePath);
              Items.Add(FilePath);
            end;
          end; // if
          CurName   := '';
          FilePath  := '';
          InInClause:= False;
        end; // begin
      end; // case
    end; // for
    Result:= Items.ToArray;
  finally
    Items.Free;
    Tokens.Free;
  end; // try
end; // function

function ParseDprojUnits(const ADprojFile: string; const AOpts: TYadfOptions): TArray<string>;
var
  AttrVal : string       ;
  Items   : TList<string>;
  P       : Integer      ;
  Q       : Integer      ;
  Resolved: string       ;
  Source  : string       ;
const
  Marker = '<DCCReference Include="';
begin
  Source:= LoadFile(ADprojFile, AOpts);
  Resolved:= ExtractFilePath(ADprojFile);
  Items:= TList<string>.Create;
  try
    P:= 1;
    while P <= Length(Source) do
    begin
      P:= Pos(Marker, Source, P);
      if P = 0 then
        Break;
      Inc(P, Length(Marker));
      Q:= Pos('"', Source, P);
      if Q = 0 then
        Break;
      AttrVal:= Copy(Source, P, Q - P);
      if SameText(ExtractFileExt(AttrVal), '.pas') then
      begin
        if not TPath.IsPathRooted(AttrVal) then
          AttrVal:= TPath.Combine(Resolved, AttrVal);
        Items.Add(AttrVal);
      end;
      P:= Q + 1;
    end; // while
    Result:= Items.ToArray;
  finally
    Items.Free;
  end; // try
end; // function

function ExpandFileSpec(const ASpec: string; const AOpts: TYadfOptions): TArray<string>;
var
  Dir: string;
  Ext: string;
  Pat: string;
begin
  if ASpec.Contains('*') or ASpec.Contains('?') then
  begin
    Dir:= ExtractFilePath(ASpec);
    if Dir = '' then
      Dir:= GetCurrentDir;
    Pat:= ExtractFileName(ASpec);
    if not TDirectory.Exists(Dir) then
      raise EYadfUsage.Create('Directory not found: ' + Dir);
    Result:= TDirectory.GetFiles(Dir, Pat, TSearchOption.soTopDirectoryOnly);
    Exit;
  end;
  Ext:= LowerCase(ExtractFileExt(ASpec));
  if Ext = '.dpr' then
    Result:= ParseDprUnits(ASpec, AOpts)
  else if Ext = '.dproj' then
    Result:= ParseDprojUnits(ASpec, AOpts)
  else
  begin
    SetLength(Result, 1);
    Result[0]:= ASpec;
  end;
end; // function

function ProcessOneFile(const AFile: string; const AOpts: TYadfOptions): Boolean;
var
  OutFile : string   ;
  Output  : string   ;
  Source  : string   ;
  Declined: string   ;
  WEnc    : TEncoding;
  WBom    : Boolean  ;
begin
  Result:= True;
  LogMsg('  ProcessOneFile: ' + AFile);
  try
    Source:= LoadFile (AFile , AOpts, WEnc, WBom);
    Output:= FormatSource(Source, AOpts, Declined);
    if Declined <> '' then
    begin
      // The content guard vetoed the output (see YADF.Guard): the file is
      // left byte-identical. Say so -- a silent decline reads as "formatter
      // mysteriously does nothing on this file" and masks the very bug the
      // guard caught.
      LogMsg('    DECLINED by content guard: ' + Declined);
      WriteStdoutLine('declined ' + AFile + ' (content guard: ' + Declined + ') -- left unchanged');
      NoteDecline;
      Exit;
    end;
    // A result dir that resolves to the input's own folder is IN-PLACE: take
    // the in-place path below (unchanged check + backup), never a blind
    // overwrite of the source (review 2026-10-14).
    if (Trim(AOpts.ResultDir) <> '')
      and not SameFileName(ExpandFileName(TPath.Combine(AOpts.ResultDir, ExtractFileName(AFile))), ExpandFileName(AFile)) then
    begin
      if not TDirectory.Exists(AOpts.ResultDir) then
        TDirectory.CreateDirectory(AOpts.ResultDir);
      OutFile:= TPath.Combine(AOpts.ResultDir, ExtractFileName(AFile));
      LogMsg('    mode = result-dir, writing to ' + OutFile);
      SaveFile(OutFile, Output, WEnc, WBom);
      WriteStdoutLine('wrote ' + OutFile);
    end
    else
    begin
      if Output = Source then
      begin
        LogMsg('    unchanged (no diff after format)');
        WriteStdoutLine('unchanged ' + AFile);
        Exit;
      end;
      if AOpts.Backup then
      begin
        LogMsg('    backup requested, BackupDir=' + AOpts.BackupDir);
        BackupOriginalFile(AFile, AOpts.BackupDir, AOpts.BackupKeep);
      end
      else
        LogMsg('    backup off, writing in-place');
      SaveFile(AFile, Output, WEnc, WBom);
      WriteStdoutLine('wrote ' + AFile);
    end; // else
  except
    on E: Exception do
    begin
      LogMsg('    FAIL ' + E.ClassName + ': ' + E.Message);
      WriteStdoutLine(Format('FAIL  %s  (%s: %s)', [AFile, E.ClassName, E.Message]));
      Result:= False;
    end;
  end; // try
end; // function

procedure ProcessFiles(const AFiles: TArray<string>; const AOpts: TYadfOptions);
var
  F   : string ;
  Fail: Integer;
  Pass: Integer;
begin
  Pass:= 0;
  Fail:= 0;
  for F in AFiles do if ProcessOneFile(F, AOpts) then
    Inc(Pass)
  else
    Inc(Fail);
  if Length(AFiles) > 1 then
    WriteStdoutLine(Format('--- %d ok, %d failed ---', [Pass, Fail]));
  if Fail > 0 then
    ExitCode:= EXIT_FAILED;
end; // procedure

procedure DebugTree(const AFileName: string; const AOpts: TYadfOptions);
var
  Root  : TGroup    ;
  Source: string    ;
  Tokens: TTokenList;
begin
  Source:= LoadFile(AFileName, AOpts);
  Tokens:= LoadTokensFromString(Source);
  try
    Root:= ParseGroups(Tokens);
    try
      WriteStdoutRaw(RenderGroupTree(Tokens, Root));
    finally
      Root.Free;
    end;
  finally
    Tokens.Free;
  end;
end; // procedure

procedure ShowUsage(const AOpts: TYadfOptions);

  function OnOff(B: Boolean): string;
  begin
    Result:= if B then 'on' else 'off';
  end;

  function Quoted(const S: string): string;
  begin
    Result:= if S = '' then '(none)' else S;
  end;

begin
  WriteStdoutLine('YADF - Yet Another Delphi Formatter'                                            );
  WriteStdoutLine(''                                                                               );
  WriteStdoutLine('Usage:'                                                                         );
  WriteStdoutLine('  yadf <input> [options]            format the input(s)'                        );
  WriteStdoutLine('  yadf --check <file.pas>           byte-faithful round-trip check'             );
  WriteStdoutLine('  yadf --check-dir <dir>            round-trip check recursively'               );
  WriteStdoutLine('  yadf --batch <in-dir> <out-dir>   format every *.pas in in-dir'               );
  WriteStdoutLine('  yadf --debug-tree <file.pas>      print structural TGroup tree'               );
  WriteStdoutLine('  yadf -h | /h | /? | --help        show this help'                             );
  WriteStdoutLine(''                                                                               );
  WriteStdoutLine('Input forms:'                                                                   );
  WriteStdoutLine('  <file.pas>            single source file'                                     );
  WriteStdoutLine('  *.pas | dir\*.pas     wildcard, top-level only (non-recursive)'               );
  WriteStdoutLine('  <project>.dpr         format the .dpr and every unit named in its uses clause');
  WriteStdoutLine('  <project>.dproj       format every .pas referenced in the .dproj XML'         );
  WriteStdoutLine(''                                                                               );
  WriteStdoutLine('Output (formats in place unless --stdout, --o or --of is given):'                 );
  WriteStdoutLine('  --stdout              write formatted text to stdout; for a single input these are the exact bytes --o would write (input/--encoding encoding, BOM iff the file would have one); with several inputs each result follows a ''--- <file> ---'' line');
  WriteStdoutLine('  --o <file>            write the result to <file> (single input only)'         );
  WriteStdoutLine(Format('  --of <folder>         write each result to <folder>\<basename>          [%s]', [Quoted(AOpts.ResultDir)]));
  WriteStdoutLine('  --no-o                clear --of/--o; format in place'              );
  WriteStdoutLine('Exit codes: 0 ok | 1 at least one file failed | 2 usage error / unhandled exception | 3 declined by the content guard (file left unchanged; a failure outranks it)');
  WriteStdoutLine(''                                                                     );
  WriteStdoutLine('Backup (opt-in; only when in-place; skipped when --o or --of is set):');
  WriteStdoutLine(Format('  --b                   backup; write <source>.BCKn next to source     [Backup=%s]', [OnOff (AOpts.Backup   )]));
  WriteStdoutLine(Format('  --b <folder>          backup; write timestamped .bak under <folder>   [%s]'      , [Quoted(AOpts.BackupDir)]));
  WriteStdoutLine(Format('  --no-b                skip backup                                    [Backup=%s]', [OnOff(AOpts.Backup)]));
  WriteStdoutLine(Format('  --backup-keep N       keep only the newest N backups per file; 0 = all [%d]'      , [AOpts.BackupKeep]));
  WriteStdoutLine(''                                             );
  WriteStdoutLine('Encoding:'                                    );
  WriteStdoutLine(Format(
      '  --encoding ansi|utf8|utf16   ansi = keep the file''s own encoding (BOM or detected UTF-8); utf8/utf16 = convert (+BOM)   [Encoding=%s]', [EncName(AOpts.Encoding)]));
  WriteStdoutLine('                          (an existing BOM in the input is auto-detected)'     );
  WriteStdoutLine(''                                                                                     );
  WriteStdoutLine('Configuration:'                                                                       );
  WriteStdoutLine('  --ini <file>          explicit INI file (overrides the F profile below)'            );
  WriteStdoutLine('                          default: the F profile named in %APPDATA%\YADF\profiles.ini');
  WriteStdoutLine('                          (F=yadf.ini out of the box; created on first run if absent)');
  WriteStdoutLine('  --no-ini              read no INI and create none: compiled-in defaults + these flags');
  WriteStdoutLine(Format('  --log / --no-log      append %%APPDATA%%\YADF\yadf-startup.log + OutputDebugString  [Logging=%s]', [OnOff(AOpts.Logging)]));
  WriteStdoutLine(Format('  --d10 / --no-d10      downgrade inline vars for Delphi 10.2.3 (best-effort)        [Delphi10Compat=%s]', [OnOff(AOpts.Delphi10Compat)]));
  WriteStdoutLine(''                              );
  WriteStdoutLine('Layout (current values in []):');
  WriteStdoutLine(Format('  --max-len N           max line length                                  [%d]', [AOpts.MaxLen       ]));
  WriteStdoutLine(Format('  --indent N            indent step in spaces                            [%d]', [AOpts.Indent       ]));
  WriteStdoutLine(Format('  --tab-width N         a leading tab = N spaces                         [%d]', [AOpts.TabWidth     ]));
  WriteStdoutLine(Format('  --max-blank-lines N   cap consecutive blank lines                      [%d]', [AOpts.MaxBlankLines]));
  WriteStdoutLine(Format('  --reflow|--no-reflow  reflow long lines / preserve source line breaks  [reflow=%s]', [OnOff(AOpts.ReflowLines)]));
  WriteStdoutLine(Format('  --collapse-blocks     fold a short begin..end body (if/for/while/with, case arm, case else) onto one line [collapse=%s]', [OnOff(AOpts.CollapseShortBlocks)]));
  WriteStdoutLine(Format('  --no-collapse-blocks  expand one-line begin..end blocks                [collapse=%s]', [OnOff(AOpts.CollapseShortBlocks)]));
  WriteStdoutLine(Format('  --break-loop          break for/while body onto its own line             [loop=%s]', [OnOff(AOpts.BreakLoopBody)]));
  WriteStdoutLine(Format('  --no-break-loop       join a short loop body onto the do line         [loop=%s]', [OnOff(AOpts.BreakLoopBody)]));
  WriteStdoutLine(Format('  --break-with          break with..do body onto its own line              [with=%s]', [OnOff(AOpts.BreakWithBody)]));
  WriteStdoutLine(Format('  --no-break-with       join a short with body onto the do line         [with=%s]', [OnOff(AOpts.BreakWithBody)]));
  WriteStdoutLine(Format('  --break-if            break if then/else body onto its own line          [if=%s]', [OnOff(AOpts.BreakIfBody)]));
  WriteStdoutLine(Format('  --no-break-if         one-line if when it fits (if C then A else B;)  [if=%s]', [OnOff(AOpts.BreakIfBody)]));
  WriteStdoutLine(Format('  --pack-bodies         preset: --no-break-if/-loop/-with + --case-arm-on-label;  [PackShortBodies=%s]', [OnOff(AOpts.PackShortBodies)]));
  WriteStdoutLine('                          an explicit switch for one of those four wins (any order); beats the INI');
  WriteStdoutLine('  --no-pack-bodies      cancel the preset (--pack-bodies and an INI PackShortBodies=true)');
  WriteStdoutLine(Format('  --begin-on-header     begin on the then/do/else/label line (then begin) [begin=%s]', [OnOff(AOpts.BeginOnHeaderLine)]));
  WriteStdoutLine(Format('  --no-begin-on-header  begin on its own line; end / else / begin apart [begin=%s]', [OnOff(AOpts.BeginOnHeaderLine)]));
  WriteStdoutLine(Format('  --pack-statements     pack adjacent plain statements on one line     [pack=%s]', [OnOff(AOpts.PackStatements)]));
  WriteStdoutLine(Format('  --no-pack-statements  one statement per line                          [pack=%s]', [OnOff(AOpts.PackStatements)]));
  WriteStdoutLine(Format('  --break-params        break routine parameters one per line              [params=%s]', [OnOff(AOpts.BreakParamsOnePerLine)]));
  WriteStdoutLine(Format('  --no-break-params     keep the parameter list inline                   [params=%s]', [OnOff(AOpts.BreakParamsOnePerLine)]));
  WriteStdoutLine(Format('  --join-headers        join split routine headers                       [join=%s]', [OnOff(AOpts.JoinRoutineHeaders)]));
  WriteStdoutLine(Format('  --no-join-headers     one parameter per line (implies --break-params)  [join=%s]', [OnOff(AOpts.JoinRoutineHeaders)]));
  WriteStdoutLine(Format('  --break-expr          break a long line one component per line             [expr=%s]', [OnOff(AOpts.BreakLongExpressions)]));
  WriteStdoutLine(Format('  --no-break-expr       use the greedy line breaker                          [expr=%s]', [OnOff(AOpts.BreakLongExpressions)]));
  WriteStdoutLine(Format('  --[no-]trim-trailing  trim / keep trailing whitespace                  [trim=%s]', [OnOff(AOpts.TrimTrailing)]));
  WriteStdoutLine(''            );
  WriteStdoutLine('Uses clause:');
  WriteStdoutLine(Format('  --uses-break          always break uses one-per-line, comma-first      [break=%s]', [OnOff(AOpts.UsesAlwaysBreak)]));
  WriteStdoutLine(Format('  --no-uses-break       keep uses inline if it fits in MaxLen             [break=%s]', [OnOff(AOpts.UsesAlwaysBreak)]));
  WriteStdoutLine(''                                                             );
  WriteStdoutLine('Case statements:'                                             );
  WriteStdoutLine(Format('  --break-case          split multi-label case arms one per line          [break=%s]', [OnOff(AOpts.BreakCaseLabels)]));
  WriteStdoutLine(Format('  --no-break-case       keep multi-label case arms on one line           [break=%s]', [OnOff(AOpts.BreakCaseLabels)]));
  WriteStdoutLine(Format('  --case-arm-on-label   short case arm statement on its label line        [arm=%s]', [OnOff(AOpts.CaseArmOnLabelLine)]));
  WriteStdoutLine(Format('  --no-case-arm-on-label  arm statement on its own line under the label  [arm=%s]', [OnOff(AOpts.CaseArmOnLabelLine)]));
  WriteStdoutLine('                          (also the case else part: else X;)');
  WriteStdoutLine(''                                                                        );
  WriteStdoutLine('Comments:'                                                               );
  WriteStdoutLine(Format('  --indent-comments     re-indent comments to code depth                   [indent=%s]', [OnOff(AOpts.IndentComments)]));
  WriteStdoutLine('  --no-indent-comments  keep comments at their authored indentation'           );
  WriteStdoutLine('                          (a comment starting with `//.` is always kept fixed)');
  WriteStdoutLine(''                                                                              );
  WriteStdoutLine('Block labels & markers:'                                                       );
  WriteStdoutLine(Format('  --label-min-lines N   min block size for `// while`                    [%d]', [AOpts.LabelMinLines]));
  WriteStdoutLine(Format('  --[no-]label-blocks   enable / disable block-end labels                [labels=%s]', [OnOff(AOpts.LabelLongBlocks)]));
  WriteStdoutLine(Format('  --[no-]mark-unclosed  mark unclosed begin/record (or not)              [marker=%s]', [OnOff(AOpts.MarkUnclosed)]));
  WriteStdoutLine(''               );
  WriteStdoutLine('Capitalization:');
  WriteStdoutLine(Format('  --[no-]lowercase-keywords  lowercase / keep keyword casing             [lowercase=%s]', [OnOff(AOpts.LowercaseKeywords)]));
  WriteStdoutLine(Format('  --[no-]upper-hex           uppercase / keep hex digit casing           [uppercase=%s]', [OnOff(AOpts.UpperHexNumbers)]));
  WriteStdoutLine(Format('  --[no-]upper-directives    uppercase / keep directive casing           [uppercase=%s]', [OnOff(AOpts.UpperDirectives)]));
  WriteStdoutLine(Format('  --[no-]first-occ           normalize / keep identifier casing          [normalize=%s]', [OnOff(AOpts.FirstOccCasing)]));
  WriteStdoutLine(''                  );
  WriteStdoutLine('Blank-line policy:');
  WriteStdoutLine(Format('  --blanks-before-section N   blanks before interface/etc               [%d]' , [AOpts.BlanksBeforeSection]));
  WriteStdoutLine(Format('  --blanks-before-method N    blanks before procedure/func              [%d]' , [AOpts.BlanksBeforeMethod ]));
  WriteStdoutLine(Format('  --blanks-before-type N      blanks before `type`                       [%d]', [AOpts.BlanksBeforeType   ]));
  WriteStdoutLine('');
  WriteStdoutLine('INI-only keys (section [Format]; no CLI flag; current values):');
  WriteStdoutLine(Format('  AssignNoSpaceBefore=%s  AssignSpaceAfter=%s  SpaceAroundOperators=%s', [OnOff(AOpts.AssignNoSpaceBefore), OnOff(AOpts.AssignSpaceAfter), OnOff(AOpts.SpaceAroundOperators)]));
  WriteStdoutLine(Format('  AlignConstEquals=%s  AlignTypeColon=%s  AlignSmartAssign=%s  AlignDeclSemicolons=%s', [OnOff(AOpts.AlignConstEquals), OnOff(AOpts.AlignTypeColon), OnOff(AOpts.AlignSmartAssign), OnOff(AOpts.AlignDeclSemicolons)]));
  WriteStdoutLine(Format('  AlignMatchingShapes=%s  AlignShapeMinAnchors=%d  AlignCommentMaxShift=%d  AlignMaxColumn=%d', [OnOff(AOpts.AlignMatchingShapes), AOpts.AlignShapeMinAnchors, AOpts.AlignCommentMaxShift, AOpts.AlignMaxColumn]));
  WriteStdoutLine(Format('  UsesCommaLast=%s  SplitMultiVarDecls=%s', [OnOff(AOpts.UsesCommaLast), OnOff(AOpts.SplitMultiVarDecls)]));
  WriteStdoutLine(''                                                          );
  WriteStdoutLine('Precedence: CLI flags > INI values > compiled-in defaults (--no-ini: CLI flags > defaults).');
end; // begin

// ParseEncoding now lives in YADF.Options (shared by CLI, wizard, GUI).

// Default INI resolution (when no --ini is passed). The CLI has no profile
// flag, so the default IS the F profile -- the same source of truth the IDE
// (YADFOT) and YADFSetup use:
//   * %APPDATA%\YADF\profiles.ini names the F file ([Profiles]F=<name>,
//     default 'yadf.ini'); ResolveProfileIniPath turns that name into a full
//     path under %APPDATA%\YADF (an absolute name passes through unchanged).
//   * If the resolved F file does not exist (fresh install), materialise the
//     commented default yadf.ini and pin profiles.ini's F entry to it, so the
//     CLI, the IDE, and YADFSetup all converge on that one file from then on.
//     Until it exists the run still proceeds on compiled-in DefaultOptions
//     (LoadIniDefaults no-ops on a missing file -- but EnsureIniExists here
//     writes the template first, so the very first run already reads it).
// --ini <path> still overrides this entirely (handled in ExtractIniPath).
// NOTE: the previous cwd/exe-folder walk for a project-local yadf.ini was
// removed on purpose -- it silently shadowed the user's saved F profile, so
// edits made in YADFSetup / the IDE Options page appeared to be ignored.
function DefaultIniPath: string;
var
  Profiles: TYadfProfiles;
begin
  Profiles:= LoadProfiles; // F defaults to 'yadf.ini'
  Result:= ResolveProfileIniPath(Profiles.F);
  if Result = '' then
    Result:= SharedAppDataIniPath; // defensive; F is never ''
  if not FileExists(Result) then
  begin
    // Fresh install: create the default template and make F point at it so all
    // three front-ends (CLI / IDE / YADFSetup) share it going forward.
    EnsureIniExists(Result);
  end;
end; // function

// All [Format] keys are read by the shared, table-driven loader in
// YADF.Options. The CLI seeds DefaultOptions then overlays the INI; here
// we just delegate so the CLI, the IDE wizard, and YADFSetup stay in lockstep.
procedure LoadIniDefaults(var AOpts: TYadfOptions; const AIniPath: string);
begin
  if not FileExists(AIniPath) then
    Exit;
  AOpts:= LoadOptionsFromIni(AIniPath);
end; // procedure

function IsHelpArg(const A: string): Boolean;
begin
  Result:= (A = '-h') or (A = '/h') or (A = '/H') or (A = '/?') or (A = '-?') or (A = '--help') or (A = '/help');  // dl:ok boolean-expression-complexity@6698
end;

function ExtractIniPath(var AArgs: TArray<string>): string;
var
  Filtered: TList<string>;
  i       : Integer      ;
  NoIni   : Boolean      ;
  HasIni  : Boolean      ;
begin
  // --no-ini (SPEC-2026-11-03): no INI is read and none is created -- not even
  // the F profile's, so DefaultIniPath (which materialises it) must not run.
  NoIni := False;
  HasIni:= False;
  for i:= 0 to High(AArgs) do
    if AArgs[i] = '--no-ini' then
      NoIni:= True
    else if AArgs[i] = '--ini' then
      HasIni:= True;
  if NoIni and HasIni then
    raise EYadfUsage.Create('--ini and --no-ini cannot be combined');
  Result:= if NoIni then '' else DefaultIniPath;
  Filtered:= TList<string>.Create;
  try
    i:= 0;
    while i <= High(AArgs) do
    begin
      if AArgs[i] = '--no-ini' then
      begin
        Inc(i);
        Continue;
      end;
      // A help arg is never an INI path. Without this guard `yadf --ini --help`
      // would consume '--help' as the path -- suppressing the help it asked for
      // and creating a file literally named '--help'. Leaving '--ini' unconsumed
      // lets ParseFlags raise the proper "--ini requires a path value".
      if (AArgs[i] = '--ini') and (i + 1 <= High(AArgs)) and not IsHelpArg(AArgs[i + 1]) then
      begin
        Result:= AArgs[i + 1];
        Inc(i, 2);
      end
      else
      begin
        Filtered.Add(AArgs[i]);
        Inc(i);
      end;
    end; // while
    AArgs:= Filtered.ToArray;
  finally
    Filtered.Free;
  end; // try
end; // function

procedure ParseFlags(var AArgs: TArray<string>; var AOpts: TYadfOptions; var AOver: TOptionOverrides; out AOutFile: string; out AStdoutMode: Boolean);
var
  i     : Integer      ;
  OutVal: TList<string>;

  // The argument after the flag at i; steps i past both. Raises AMissing
  // when the flag is the last argument.
  function NextValue(const AMissing: string): string;
  begin
    if i + 1 > High(AArgs) then
      raise EYadfUsage.Create(AMissing);
    Result:= AArgs[i + 1];
    Inc(i, 2);
  end;

  // AArgs[i] is AOn or AOff: sets AField (True for AOn) and steps past it.
  function BoolFlag(const AOn, AOff: string; var AField: Boolean): Boolean;
  begin
    Result:= (AArgs[i] = AOn) or (AArgs[i] = AOff);
    if Result then
    begin
      AField:= AArgs[i] = AOn;
      Inc(i);
    end;
  end;

  // BoolFlag for one of the four rules --pack-bodies presets: also records that
  // the CLI layer set it explicitly, so the CLI preset leaves it alone (SPEC-2026-11-03).
  function BodyFlag(const AOn, AOff: string; var AField, AExplicit: Boolean): Boolean;
  begin
    Result:= BoolFlag(AOn, AOff, AField);
    if Result then
      AExplicit:= True;
  end;

  // AArgs[i] is AName: reads the integer after it into AField.
  function IntFlag(const AName: string; var AField: Integer): Boolean;
  begin
    Result:= AArgs[i] = AName;
    if Result then
      AField:= StrToInt(NextValue(AName + ' requires a value'));
  end;

  // Every flag that only sets one option field: True when AArgs[i] was one.
  function TableFlag: Boolean;  // dl:ok cyclomatic-complexity@e039 -- each "or" is one row of the flag table, not a decision; splitting it would only bring back the repetition
  begin
    Result:= IntFlag('--max-len', AOpts.MaxLen)  // dl:ok boolean-expression-complexity@89ee -- the expression IS the flag table, one row per line
      or IntFlag('--indent', AOpts.Indent)
      or IntFlag('--tab-width', AOpts.TabWidth)
      or IntFlag('--label-min-lines', AOpts.LabelMinLines)
      or IntFlag('--backup-keep', AOpts.BackupKeep)
      or IntFlag('--max-blank-lines', AOpts.MaxBlankLines)
      or IntFlag('--blanks-before-section', AOpts.BlanksBeforeSection)
      or IntFlag('--blanks-before-method', AOpts.BlanksBeforeMethod)
      or IntFlag('--blanks-before-type', AOpts.BlanksBeforeType)
      or BoolFlag('--mark-unclosed', '--no-mark-unclosed', AOpts.MarkUnclosed)
      or BoolFlag('--label-blocks', '--no-label-blocks', AOpts.LabelLongBlocks)
      or BoolFlag('--trim-trailing', '--no-trim-trailing', AOpts.TrimTrailing)
      or BoolFlag('--reflow', '--no-reflow', AOpts.ReflowLines)
      or BoolFlag('--lowercase-keywords', '--no-lowercase-keywords', AOpts.LowercaseKeywords)
      or BoolFlag('--upper-hex', '--no-upper-hex', AOpts.UpperHexNumbers)
      or BoolFlag('--upper-directives', '--no-upper-directives', AOpts.UpperDirectives)
      or BoolFlag('--first-occ', '--no-first-occ', AOpts.FirstOccCasing)
      or BoolFlag('--d10', '--no-d10', AOpts.Delphi10Compat)
      or BoolFlag('--log', '--no-log', AOpts.Logging)
      or BoolFlag('--uses-break', '--no-uses-break', AOpts.UsesAlwaysBreak)
      or BoolFlag('--break-case', '--no-break-case', AOpts.BreakCaseLabels)
      or BodyFlag('--case-arm-on-label', '--no-case-arm-on-label', AOpts.CaseArmOnLabelLine, AOver.Cli.ExplicitArm)
      or BoolFlag('--begin-on-header', '--no-begin-on-header', AOpts.BeginOnHeaderLine)
      or BoolFlag('--pack-statements', '--no-pack-statements', AOpts.PackStatements)
      or BoolFlag('--indent-comments', '--no-indent-comments', AOpts.IndentComments)
      or BoolFlag('--collapse-blocks', '--no-collapse-blocks', AOpts.CollapseShortBlocks)
      or BodyFlag('--break-loop', '--no-break-loop', AOpts.BreakLoopBody, AOver.Cli.ExplicitLoop)
      or BodyFlag('--break-with', '--no-break-with', AOpts.BreakWithBody, AOver.Cli.ExplicitWith)
      or BodyFlag('--break-if', '--no-break-if', AOpts.BreakIfBody, AOver.Cli.ExplicitIf)
      or BoolFlag('--break-params', '--no-break-params', AOpts.BreakParamsOnePerLine)
      or BoolFlag('--join-headers', '--no-join-headers', AOpts.JoinRoutineHeaders)
      or BoolFlag('--break-expr', '--no-break-expr', AOpts.BreakLongExpressions);
  end;

begin
  AOutFile   := '';
  AStdoutMode:= False;
  OutVal:= TList<string>.Create;
  try
    i:= 0;
    while i <= High(AArgs) do
    begin
      if TableFlag then
        Continue;
      if AArgs[i] = '--o' then
        AOutFile:= NextValue('--o requires a file path')
      else if AArgs[i] = '--of' then
        AOpts.ResultDir:= NextValue('--of requires a folder path')
      else if AArgs[i] = '--no-o' then
      begin
        AOpts.ResultDir:= '';
        AOutFile:= '';
        Inc(i);
      end
      else if AArgs[i] = '--b' then
      begin
        AOpts.Backup:= True;
        // The next argument is the backup FOLDER only when it cannot be an
        // input: an existing directory, or anything that is not a source
        // spec. `yadf --b foo.pas` used to make foo.pas the BackupDir and
        // format nothing (review 2026-10-14).
        if (i + 1 <= High(AArgs)) and not AArgs[i + 1].StartsWith('--')
          and (TDirectory.Exists(AArgs[i + 1]) or not LooksLikeSourceSpec(AArgs[i + 1])) then
          AOpts.BackupDir:= NextValue('')
        else
        begin
          AOpts.BackupDir:= '';
          Inc(i);
        end;
      end // if
      else if AArgs[i] = '--no-b' then
      begin
        AOpts.Backup:= False;
        Inc(i);
      end
      else if AArgs[i] = '--stdout' then
      begin
        AStdoutMode:= True;
        Inc(i);
      end
      else if AArgs[i] = '--encoding' then
      begin
        if i + 1 > High(AArgs) then
          raise EYadfUsage.Create('--encoding requires ansi|utf8|utf16');
        // An unknown value used to fall back to the current encoding silently.
        // Unknown = ParseEncoding just hands back whichever default it gets.
        if (ParseEncoding(AArgs[i + 1], encANSI) = encANSI) and (ParseEncoding(AArgs[i + 1], encUTF8BOM) = encUTF8BOM) then
          raise EYadfUsage.Create('--encoding: unknown value "' + AArgs[i + 1] + '" (use ansi|utf8|utf16)');
        AOpts.Encoding:= ParseEncoding(AArgs[i + 1], AOpts.Encoding);
        Inc(i, 2);
      end
      else if AArgs[i] = '--pack-bodies' then
      begin
        AOver.Cli.Pack:= True; // the CLI layer's preset; applied by ResolveOptions
        Inc(i);
      end
      else if AArgs[i] = '--no-pack-bodies' then
      begin
        AOver.NoPack:= True; // cancels the preset in the INI and the CLI layer
        Inc(i);
      end
      else if AArgs[i] = '--ini' then
        // ExtractIniPath already consumed every valid `--ini <path>` pair; a
        // bare `--ini` reaching this parser means the value was forgotten --
        // say that, instead of the misleading "unknown option --ini".
        raise EYadfUsage.Create('--ini requires a path value')
      else if AArgs[i].StartsWith('--') and (AArgs[i] <> '--check') and (AArgs[i] <> '--check-dir') and (AArgs[i] <> '--batch') and (AArgs[i] <> '--debug-tree') then
      begin
        // Anything else that looks like a flag is a typo or an unsupported
        // option; reject it loudly instead of treating it as a file spec
        // (which used to produce a confusing "file not found" run). The four
        // positional mode flags above are parsed later by RunYadf and must
        // pass through untouched.
        raise EYadfUsage.Create('unknown option ' + AArgs[i] + ' (run yadf --help for the flag list)');
      end
      else
      begin
        OutVal.Add(AArgs[i]);
        Inc(i);
      end;
    end; // while
    AArgs:= OutVal.ToArray;
  finally
    OutVal.Free;
  end; // try
end; // procedure

// True when two inputs share a basename (case-insensitive); ADup receives it.
// With --of every result lands in one folder as <basename>, so the second would
// silently overwrite the first.
function FindDuplicateBaseName(const AFiles: TList<string>; out ADup: string): Boolean;
var
  F   : string                    ;
  Seen: TDictionary<string, Boolean>;
begin
  Result:= False;
  ADup  := '';
  Seen  := TDictionary<string, Boolean>.Create;
  try
    for F in AFiles do
      if Seen.ContainsKey(LowerCase(ExtractFileName(F))) then
      begin
        ADup  := ExtractFileName(F);
        Result:= True;
        Break;
      end
      else
        Seen.Add(LowerCase(ExtractFileName(F)), True);
  finally
    Seen.Free;
  end;
end; // function

procedure RunYadf;  // dl:ok too-many-exit-points@f480
var
  AllFiles  : TList<string> ;
  Args      : TArray<string>;
  Diff      : Integer       ;
  F         : string        ;
  Files     : TArray<string>;
  i         : Integer       ;
  IniPath   : string        ;
  Opts      : TYadfOptions  ;
  OutFile   : string        ;
  Spec      : string        ;
  StdoutMode: Boolean       ;
  Clamped   : string        ;
  Over      : TOptionOverrides;
  Dup       : string        ;
  Seen      : TDictionary<string, Boolean>;
begin
  SetLength(Args, ParamCount);
  for i:= 1 to ParamCount do
    Args[i - 1]:= ParamStr(i);

  // Resolve the config BEFORE the help branch: --help prints every option's
  // current value, so it must read the SAME INI a real run would use. While
  // this ran after the help branch, `yadf --ini X --help` described the
  // %APPDATA% profile instead of X -- help that contradicts the run it is
  // documenting (it has already produced one false bug report).
  IniPath:= ExtractIniPath(Args);

  for i:= 0 to High(Args) do if IsHelpArg(Args[i]) then
  begin
    Opts:= DefaultOptions;
    // Same first-run contract as a normal run: materialise the template at
    // the resolved path when it is absent. The help text itself promises
    // this ("created on first run if absent"), and it is what makes
    // `yadf --ini <new> --help` a usable way to get a commented config.
    if EnsureIniExists(IniPath) then
      WriteStdoutLine('Created default config: ' + IniPath);
    LoadIniDefaults(Opts, IniPath);
    ShowUsage(Opts);
    Exit;
  end;

  Opts:= DefaultOptions;
  // First-run: if no INI exists at the resolved path, materialise a
  // fully-commented template with all defaults. Subsequent runs see
  // an existing file and load it normally.
  if EnsureIniExists(IniPath) then
    WriteStdoutLine('Created default config: ' + IniPath);
  // Layers (SPEC-2026-11-03): read every value from the INI, then the flags,
  // recording per layer what each asked for; only then apply the Pack preset of
  // each layer (CLI over INI; inside a layer an explicit rule beats the preset)
  // and the range clamp, so neither key nor argument order matters. Out-of-range
  // INI and CLI values are both reported, to stderr (in --stdout mode stdout
  // carries the formatted source). --no-ini leaves IniPath '' (nothing read).
  Over:= Default(TOptionOverrides);
  ReadOptionsFromIni(IniPath, Opts, Over);
  ParseFlags(Args, Opts, Over, OutFile, StdoutMode);
  Clamped:= ResolveOptions(Opts, Over);
  if Clamped <> '' then
    Writeln(ErrOutput, 'warning: out-of-range option(s) corrected: ' + Clamped);
  GLogEnabled:= Opts.Logging;
  LogStartup(Args, Opts, IniPath);

  if Length(Args) = 0 then
  begin
    ShowUsage(Opts);
    Exit;
  end;

  if Args[0] = '--check' then
  begin
    if Length(Args) <> 2 then
    begin
      ShowUsage(Opts);
      ExitCode:= 1;
      Exit;
    end;
    if CheckFile(Args[1], Opts, Diff) then
      WriteStdoutLine('PASS  ' + Args[1])
    else
    begin
      WriteStdoutLine(Format('FAIL  %s  (first diff at byte %d)', [Args[1], Diff]));
      ExitCode:= 1;
    end;
    Exit;
  end; // if

  if Args[0] = '--check-dir' then
  begin
    if Length(Args) <> 2 then
    begin
      ShowUsage(Opts);
      ExitCode:= 1;
      Exit;
    end;
    CheckDir(Args[1], Opts);
    Exit;
  end;

  if Args[0] = '--batch' then
  begin
    if Length(Args) <> BATCH_ARG_COUNT then
    begin
      ShowUsage(Opts);
      ExitCode:= 1;
      Exit;
    end;
    BatchFormat(Args[1], Args[2], Opts);
    Exit;
  end;

  if Args[0] = '--debug-tree' then
  begin
    if Length(Args) <> 2 then
    begin
      ShowUsage(Opts);
      ExitCode:= 1;
      Exit;
    end;
    DebugTree(Args[1], Opts);
    Exit;
  end;

  AllFiles:= TList<string>.Create;
  try
    Seen:= TDictionary<string, Boolean>.Create;
    try
      for Spec in Args do
      begin
        Files:= ExpandFileSpec(Spec, Opts);
        // The same file reached twice (named + wildcard, or two specs) is formatted once; order kept.
        for F in Files do
          if not Seen.ContainsKey(LowerCase(ExpandFileName(F))) then
          begin
            Seen.Add(LowerCase(ExpandFileName(F)), True);
            AllFiles.Add(F);
          end;
      end;
    finally
      Seen.Free;
    end;

    if AllFiles.Count = 0 then
    begin
      WriteStdoutLine('error: no .pas files matched');
      ExitCode:= 1;
      Exit;
    end;

    if (OutFile <> '') and (AllFiles.Count > 1) then
    begin
      WriteStdoutLine('error: --o only valid with a single input file');
      ExitCode:= 1;
      Exit;
    end;

    if (Trim(Opts.ResultDir) <> '') and (OutFile = '') and not StdoutMode and FindDuplicateBaseName(AllFiles, Dup) then
    begin
      WriteStdoutLine('error: --of: two inputs share the file name ' + Dup + ' -- the second result would overwrite the first; nothing was written');
      ExitCode:= 1;
      Exit;
    end;

    if OutFile <> '' then
    begin
      FormatToFile(AllFiles[0], OutFile, Opts);
      Exit;
    end;

    if StdoutMode then
    begin
      for i:= 0 to AllFiles.Count - 1 do
      begin
        if AllFiles.Count > 1 then
          WriteStdoutLine(Format('--- %s ---', [AllFiles[i]]));
        FormatToStdout(AllFiles[i], Opts);
      end;
      Exit;
    end;

    ProcessFiles(AllFiles.ToArray, Opts);
  finally
    AllFiles.Free;
  end; // try
end; // procedure

end.


