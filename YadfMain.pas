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
//   // TODO -oYADF : '<keyword>' on line N has no matching 'end'
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

procedure RunYadf;

implementation

uses
  Winapi.Windows
  , Winapi.ShlObj
  , System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.IniFiles
  , System.Generics.Collections
  , SimpleParser.Lexer.Types
  , YADF.Tokens
  , YADF.Options
  , YADF.Groups
  , YADF.Layout
  , YADF.Debug
  ;

procedure WriteStdoutRaw(const S: string);
var
  Bytes  : TBytes;
  Written: DWORD;
begin
  if S = '' then Exit;
  Bytes:= TEncoding.ANSI.GetBytes(S);
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), Bytes[0], Length(Bytes), Written, nil);
end;

procedure WriteStdoutLine(const S: string);
begin
  WriteStdoutRaw(S + sLineBreak);
end;

var
  GLogPath   : string;
  GLogEnabled: Boolean;

function LogFilePath: string;
begin
  if GLogPath = '' then
    GLogPath:= TPath.Combine(ExtractFilePath(ParamStr(0)), 'yadf-startup.log');
  Result:= GLogPath;
end;

procedure LogMsg(const S: string);
var
  Line: string;
begin
  if not GLogEnabled then Exit;
  Line:= FormatDateTime('hh:nn:ss.zzz ', Now) + S;
  OutputDebugString(PChar('[YADF] ' + Line));
  try
    TFile.AppendAllText(LogFilePath, Line + sLineBreak, TEncoding.ANSI);
  except
    // never let logging break the run
  end;
end;

// TYadfEncoding -> display name ('ANSI' / 'UTF-8-BOM' / 'UTF-16-BOM'); shared by
// the startup log and the --help banner.
function EncName(E: TYadfEncoding): string;
begin
  case E of
    encUTF8BOM : Result:= 'UTF-8-BOM' ;
    encUTF16BOM: Result:= 'UTF-16-BOM';
    else
      Result:= 'ANSI';
  end;
end;

procedure LogStartup(const AArgs: TArray<string>; const AOpts: TYadfOptions; const AIniPath: string);

  function BoolStr(B: Boolean): string;
  begin
    if B then Result:= 'true' else Result:= 'false';
  end;

var
  i: Integer;
begin
  if not GLogEnabled then Exit;
  LogMsg('==== YADF startup ====');
  LogMsg('  CWD:       ' + GetCurrentDir);
  LogMsg('  Exe:       ' + ParamStr(0));
  LogMsg('  INI:       ' + AIniPath);
  LogMsg('  RawCmd:    ' + GetCommandLine);
  LogMsg('  Args[' + IntToStr(Length(AArgs)) + ']:');
  for i:= 0 to High(AArgs) do LogMsg('    [' + IntToStr(i) + '] ' + AArgs[i]);
  LogMsg('  Resolved options:');
  LogMsg('    ResultDir       = ' + AOpts.ResultDir);
  LogMsg('    Backup          = ' + BoolStr(AOpts.Backup));
  LogMsg('    BackupDir       = ' + AOpts.BackupDir);
  LogMsg('    Encoding        = ' + EncName(AOpts.Encoding));
  LogMsg('    UsesAlwaysBreak = ' + BoolStr(AOpts.UsesAlwaysBreak));
end; // begin

function ResolveEncoding(const AOpts: TYadfOptions): TEncoding;
begin
  case AOpts.Encoding of
    encUTF8BOM : Result:= TEncoding.UTF8   ;
    encUTF16BOM: Result:= TEncoding.Unicode;
    else
      Result:= TEncoding.ANSI;
  end;
end;

function LoadFile(const AFileName: string; const AOpts: TYadfOptions): string;
var
  Bytes   : TBytes;
  Detected: TEncoding;
  PreLen  : Integer;
begin
  Bytes:= TFile.ReadAllBytes(AFileName);
  Detected:= nil;
  PreLen:= TEncoding.GetBufferEncoding(Bytes, Detected, ResolveEncoding(AOpts));
  Result:= Detected.GetString(Bytes, PreLen, Length(Bytes) - PreLen);
end;

procedure SaveFile(const AFileName, AContent: string; const AOpts: TYadfOptions);

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
    H : THandle;
    Ft: TFileTime;
  begin
    H:= CreateFileW(PWideChar(AFile), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if H = INVALID_HANDLE_VALUE then Exit;
    try
      GetSystemTimeAsFileTime(Ft);
      SetFileTime(H, nil, nil, @Ft);
    finally
      CloseHandle(H);
    end;
  end;

var
  All     : TBytes;
  Bytes   : TBytes;
  Enc     : TEncoding;
  Preamble: TBytes;
  Tmp     : string;
begin
  Enc:= ResolveEncoding(AOpts);
  Preamble:= Enc.GetPreamble;
  Bytes:= Enc.GetBytes(AContent);
  if Length(Preamble) > 0 then
  begin
    SetLength(All, Length(Preamble) + Length(Bytes));
    Move(Preamble[0], All[0], Length(Preamble));
    Move(Bytes[0], All[Length(Preamble)], Length(Bytes));
  end
  else
    All:= Bytes;

  Tmp:= AFileName + '.yadf-tmp';
  try
    WriteAllBytesFlushed(Tmp, All);
    if not MoveFileExW(PWideChar(Tmp), PWideChar(AFileName), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    DeleteFileW(PWideChar(Tmp));
    raise;
  end;
  BumpModifiedTime(AFileName);
  SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, PWideChar(AFileName), nil);
end; // begin

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
  if Length(B) < n then n:= Length(B);
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
  Source: string;
begin
  Source:= LoadFile(AFileName, AOpts);
  WriteStdoutRaw(FormatSource(Source, AOpts));
end;

procedure FormatToFile(const AInFile, AOutFile: string; const AOpts: TYadfOptions);
var
  Dir   : string;
  Source: string;
begin
  Source:= LoadFile(AInFile, AOpts);
  Dir:= TPath.GetDirectoryName(AOutFile);
  if Dir <> '' then
    TDirectory.CreateDirectory(Dir);
  SaveFile(AOutFile, FormatSource(Source, AOpts), AOpts);
  WriteStdoutLine('wrote ' + AOutFile);
end;

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

procedure BackupOriginalFile(const AFile: string; const ABackupDir: string);
var
  Stamp : string;
  Target: string;
begin
  if Trim(ABackupDir) = '' then
  begin
    Target:= NextSiblingBackupName(AFile);
    TFile.Copy(AFile, Target, True);
    Exit;
  end;
  if not TDirectory.Exists(ABackupDir) then
    TDirectory.CreateDirectory(ABackupDir);
  Stamp:= FormatDateTime('yyyymmdd-hhnnss', Now);
  Target:= TPath.Combine(ABackupDir, ExtractFileName(AFile) + '.' + Stamp + '.bak');
  TFile.Copy(AFile, Target, True);
end;

procedure CheckDir(const ADir: string; const AOpts: TYadfOptions);
var
  Diff : Integer;
  F    : string;
  Fail : Integer;
  Files: TArray<string>;
  Pass : Integer;
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
  end;
  WriteStdoutLine(Format('--- %d pass, %d fail ---', [Pass, Fail]));
  if Fail > 0 then
    ExitCode:= 1;
end; // procedure

procedure BatchFormat(const AInDir, AOutDir: string; const AOpts: TYadfOptions);
var
  Count  : Integer;
  F      : string;
  Files  : TArray<string>;
  Out_   : string;
  RelName: string;
  Source : string;
begin
  if not TDirectory.Exists(AInDir) then
  begin
    WriteStdoutLine('error: input directory not found: ' + AInDir);
    ExitCode:= 1;
    Exit;
  end;
  TDirectory.CreateDirectory(AOutDir);
  Files:= TDirectory.GetFiles(AInDir, '*.pas', TSearchOption.soTopDirectoryOnly);
  Count:= 0;
  for F in Files do
  begin
    Source:= LoadFile(F, AOpts);
    RelName:= ExtractFileName(F);
    Out_:= TPath.Combine(AOutDir, RelName);
    SaveFile(Out_, FormatSource(Source, AOpts), AOpts);
    WriteStdoutLine(Format('wrote %s', [Out_]));
    Inc(Count);
  end;
  WriteStdoutLine(Format('--- %d file(s) formatted into %s ---', [Count, AOutDir]));
end; // procedure

function ParseDprUnits(const ADprFile: string; const AOpts: TYadfOptions): TArray<string>;
var
  CurName    : string;
  EndIdx     : Integer;
  FilePath   : string;
  i          : Integer;
  InInClause : Boolean;
  Items      : TList<string>;
  Raw        : string;
  ResolvedDir: string;
  Source     : string;
  T          : TToken;
  Tokens     : TTokenList;
  UsesIdx    : Integer;
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
    CurName   := ''   ;
    FilePath  := ''   ;
    InInClause:= False;
    for i:= UsesIdx + 1 to EndIdx do
    begin
      T:= Tokens[i];
      case T.Kind of
        ptIdentifier: if not InInClause then
          CurName:= CurName + T.Text;
        ptPoint: if not InInClause then
          CurName:= CurName + '.';
        ptIn         : InInClause:= True;
        ptStringConst: if InInClause then
        begin
          Raw:= T.Text;
          if (Length(Raw) >= 2) and (Raw[1] = '''') and (Raw[Length(Raw)] = '''') then
            FilePath:= Copy(Raw, 2, Length(Raw) - 2)
          else
            FilePath:= Raw;
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
          end;
          CurName   := ''   ;
          FilePath  := ''   ;
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
  AttrVal : string;
  Items   : TList<string>;
  P       : Integer;
  Q       : Integer;
  Resolved: string;
  Source  : string;
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
      if P = 0 then Break;
      Inc(P, Length(Marker));
      Q:= Pos('"', Source, P);
      if Q = 0 then Break;
      AttrVal:= Copy(Source, P, Q - P);
      if SameText(ExtractFileExt(AttrVal), '.pas') then
      begin
        if not TPath.IsPathRooted(AttrVal) then
          AttrVal:= TPath.Combine(Resolved, AttrVal);
        Items.Add(AttrVal);
      end;
      P:= Q + 1;
    end;
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
  if (Pos('*', ASpec) > 0) or (Pos('?', ASpec) > 0) then
  begin
    Dir:= ExtractFilePath(ASpec);
    if Dir = '' then Dir:= GetCurrentDir;
    Pat:= ExtractFileName(ASpec);
    if not TDirectory.Exists(Dir) then
      raise Exception.Create('Directory not found: ' + Dir);
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
  OutFile: string;
  Output : string;
  Source : string;
begin
  Result:= True;
  LogMsg('  ProcessOneFile: ' + AFile);
  try
    Source:= LoadFile    (AFile , AOpts);
    Output:= FormatSource(Source, AOpts);
    if Trim(AOpts.ResultDir) <> '' then
    begin
      if not TDirectory.Exists(AOpts.ResultDir) then
        TDirectory.CreateDirectory(AOpts.ResultDir);
      OutFile:= TPath.Combine(AOpts.ResultDir, ExtractFileName(AFile));
      LogMsg('    mode = result-dir, writing to ' + OutFile);
      SaveFile(OutFile, Output, AOpts);
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
        BackupOriginalFile(AFile, AOpts.BackupDir);
      end
      else
        LogMsg('    backup off, writing in-place');
      SaveFile(AFile, Output, AOpts);
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
  F   : string;
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
    ExitCode:= Fail;
end;

procedure DebugTree(const AFileName: string; const AOpts: TYadfOptions);
var
  Root  : TGroup;
  Source: string;
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
end;

procedure ShowUsage(const AOpts: TYadfOptions);

  function OnOff(B: Boolean): string;
  begin
    if B then Result:= 'on' else Result:= 'off';
  end;

  function Quoted(const S: string): string;
  begin
    if S = '' then Result:= '(none)' else Result:= S;
  end;

begin
  WriteStdoutLine('YADF - Yet Another Delphi Formatter');
  WriteStdoutLine('');
  WriteStdoutLine('Usage:');
  WriteStdoutLine('  yadf <input> [options]            format the input(s)');
  WriteStdoutLine('  yadf --check <file.pas>           byte-faithful round-trip check');
  WriteStdoutLine('  yadf --check-dir <dir>            round-trip check recursively');
  WriteStdoutLine('  yadf --batch <in-dir> <out-dir>   format every *.pas in in-dir');
  WriteStdoutLine('  yadf --debug-tree <file.pas>      print structural TGroup tree');
  WriteStdoutLine('  yadf -h | /h | /? | --help        show this help');
  WriteStdoutLine('');
  WriteStdoutLine('Input forms:');
  WriteStdoutLine('  <file.pas>            single source file');
  WriteStdoutLine('  *.pas | dir\*.pas     wildcard, top-level only (non-recursive)');
  WriteStdoutLine('  <project>.dpr         format the .dpr and every unit named in its uses clause');
  WriteStdoutLine('  <project>.dproj       format every .pas referenced in the .dproj XML');
  WriteStdoutLine('');
  WriteStdoutLine('Output (default = format in place):');
  WriteStdoutLine('  --stdout              write formatted text to stdout (no files written)');
  WriteStdoutLine('  --o <file>            write the result to <file> (single input only)');
  WriteStdoutLine(Format('  --of <folder>         write each result to <folder>\<basename>          [%s]', [Quoted(AOpts.ResultDir)]));
  WriteStdoutLine('  --no-o                clear --of/--o; format in place');
  WriteStdoutLine('');
  WriteStdoutLine('Backup (opt-in; only when in-place; skipped when --o or --of is set):');
  WriteStdoutLine(Format('  --b                   backup; write <source>.BCKn next to source     [Backup=%s]', [OnOff(AOpts.Backup)]));
  WriteStdoutLine(Format('  --b <folder>          backup; write timestamped .bak under <folder>   [%s]', [Quoted(AOpts.BackupDir)]));
  WriteStdoutLine('  --no-b                skip backup (default)');
  WriteStdoutLine('');
  WriteStdoutLine('Encoding:');
  WriteStdoutLine(Format('  --encoding ansi|utf8|utf16   read/write as ANSI / UTF-8+BOM / UTF-16+BOM   [Encoding=%s]', [EncName(AOpts.Encoding)]));
  WriteStdoutLine('                          (default ANSI; existing BOM in input is auto-detected)');
  WriteStdoutLine('');
  WriteStdoutLine('Configuration:');
  WriteStdoutLine('  --ini <file>          alternate INI file (default: yadf.ini, searched up from the exe folder)');
  WriteStdoutLine(Format('  --log / --no-log      write yadf-startup.log next to the exe + OutputDebugString  [Logging=%s]', [OnOff(AOpts.Logging)]));
  WriteStdoutLine(Format('  --d10 / --no-d10      downgrade inline vars for Delphi 10.2.3 (best-effort)        [Delphi10Compat=%s]', [OnOff(AOpts.Delphi10Compat)]));
  WriteStdoutLine('');
  WriteStdoutLine('Layout (current values in []):');
  WriteStdoutLine(Format('  --max-len N           max line length                                  [%d]', [AOpts.MaxLen]));
  WriteStdoutLine(Format('  --indent N            indent step in spaces                            [%d]', [AOpts.Indent]));
  WriteStdoutLine(Format('  --tab-width N         a leading tab = N spaces                         [%d]', [AOpts.TabWidth]));
  WriteStdoutLine(Format('  --max-blank-lines N   cap consecutive blank lines                      [%d]', [AOpts.MaxBlankLines]));
  WriteStdoutLine(Format('  --no-reflow           preserve source line breaks                      [reflow=%s]', [OnOff(AOpts.ReflowLines)]));
  WriteStdoutLine(Format('  --pack-bodies         pack short loop/if bodies + case arms onto one line [pack=%s]', [OnOff(AOpts.PackShortBodies)]));
  WriteStdoutLine('  --no-pack-bodies      keep each body / case arm on its own line (default)');
  WriteStdoutLine(Format('  --collapse-blocks     fold a short if/for/while begin..end body onto one line [collapse=%s]', [OnOff(AOpts.CollapseShortBlocks)]));
  WriteStdoutLine('  --no-collapse-blocks  keep begin..end blocks expanded (default)');
  WriteStdoutLine(Format('  --no-trim-trailing    keep trailing whitespace                         [trim=%s]', [OnOff(AOpts.TrimTrailing)]));
  WriteStdoutLine('');
  WriteStdoutLine('Uses clause:');
  WriteStdoutLine(Format('  --uses-break          always break uses one-per-line, comma-first      [break=%s]', [OnOff(AOpts.UsesAlwaysBreak)]));
  WriteStdoutLine('  --no-uses-break       keep uses inline if it fits in MaxLen');
  WriteStdoutLine('');
  WriteStdoutLine('Case statements:');
  WriteStdoutLine(Format('  --break-case          split multi-label case arms one per line          [break=%s]', [OnOff(AOpts.BreakCaseLabels)]));
  WriteStdoutLine('  --no-break-case       keep multi-label case arms on one line (default)');
  WriteStdoutLine('');
  WriteStdoutLine('Comments:');
  WriteStdoutLine(Format('  --indent-comments     re-indent comments to code depth                   [indent=%s]', [OnOff(AOpts.IndentComments)]));
  WriteStdoutLine('  --no-indent-comments  keep comments at their authored indentation');
  WriteStdoutLine('                          (a comment starting with `//.` is always kept fixed)');
  WriteStdoutLine('');
  WriteStdoutLine('Block labels & markers:');
  WriteStdoutLine(Format('  --label-min-lines N   min block size for `// while`                    [%d]', [AOpts.LabelMinLines]));
  WriteStdoutLine(Format('  --no-label-blocks     disable block-end labels                         [labels=%s]', [OnOff(AOpts.LabelLongBlocks)]));
  WriteStdoutLine(Format('  --mark-unclosed       mark unclosed begin/record                       [marker=%s]', [OnOff(AOpts.MarkUnclosed)]));
  WriteStdoutLine('');
  WriteStdoutLine('Capitalization:');
  WriteStdoutLine(Format('  --no-lowercase-keywords  keep keyword casing                           [lowercase=%s]', [OnOff(AOpts.LowercaseKeywords)]));
  WriteStdoutLine(Format('  --no-upper-hex           keep hex digit casing                         [uppercase=%s]', [OnOff(AOpts.UpperHexNumbers)]));
  WriteStdoutLine(Format('  --no-upper-directives    keep directive casing                         [uppercase=%s]', [OnOff(AOpts.UpperDirectives)]));
  WriteStdoutLine(Format('  --no-first-occ           keep identifier casing                        [normalize=%s]', [OnOff(AOpts.FirstOccCasing)]));
  WriteStdoutLine('');
  WriteStdoutLine('Blank-line policy:');
  WriteStdoutLine(Format('  --blanks-before-section N   blanks before interface/etc               [%d]', [AOpts.BlanksBeforeSection]));
  WriteStdoutLine(Format('  --blanks-before-method N    blanks before procedure/func              [%d]', [AOpts.BlanksBeforeMethod]));
  WriteStdoutLine(Format('  --blanks-before-type N      blanks before `type`                       [%d]', [AOpts.BlanksBeforeType]));
  WriteStdoutLine('');
  WriteStdoutLine(Format('Pass-2 alignment max column (INI: AlignMaxColumn): %d', [AOpts.AlignMaxColumn]));
  WriteStdoutLine('');
  WriteStdoutLine('Precedence: CLI flags > INI values > compiled-in defaults.');
end; // begin

// ParseEncoding now lives in YADF.Options (shared by CLI, wizard, GUI).

// Lookup order:
//   1. Walk UP from cwd up to 9 levels looking for yadf.ini (project-
//      local override).
//   2. Walk UP from the .exe's own folder up to 5 levels (portable-app
//      pattern: yadf.ini ships next to YADF.exe).
//   3. Shared per-user fallback %APPDATA%\YADF\yadf.ini -- same path
//      YADFOT.bpl uses, so the IDE wizard and the CLI converge on the
//      same file.
// First hit wins. If nothing exists, returns the shared fallback path
// (which EnsureIniExists will then materialise as a commented template).
function DefaultIniPath: string;
  function WalkUp(const AStart: string; ADepth: Integer): string;
  var
    Dir, Candidate, Parent: string;
    i: Integer;
  begin
    Result:= '';
    Dir:= AStart;
    for i:= 0 to ADepth do
    begin
      if Dir = '' then Break;
      Candidate:= TPath.Combine(Dir, 'yadf.ini');
      if TFile.Exists(Candidate) then Exit(Candidate);
      Parent:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
      if (Parent = '') or SameText(Parent,
        ExcludeTrailingPathDelimiter(Dir)) then Break;
      Dir:= IncludeTrailingPathDelimiter(Parent);
    end;
  end;
var
  Hit: string;
begin
  Hit:= WalkUp(IncludeTrailingPathDelimiter(GetCurrentDir), 9);
  if Hit <> '' then Exit(Hit);
  Hit:= WalkUp(ExtractFilePath(ParamStr(0)), 5);
  if Hit <> '' then Exit(Hit);
  Result:= SharedAppDataIniPath;
end;

// All [Format] keys are read by the shared, table-driven loader in
// YADF.Options. The CLI seeds DefaultOptions then overlays the INI; here
// we just delegate so the CLI, the IDE wizard, and YADFSetup stay in lockstep.
procedure LoadIniDefaults(var AOpts: TYadfOptions; const AIniPath: string);
begin
  if not FileExists(AIniPath) then Exit;
  AOpts:= LoadOptionsFromIni(AIniPath);
end; // procedure

function IsHelpArg(const A: string): Boolean;
begin
  Result:= (A = '-h') or (A = '/h') or (A = '/H') or (A = '/?') or (A = '-?') or (A = '--help') or (A = '/help');
end;

function ExtractIniPath(var AArgs: TArray<string>): string;
var
  Filtered: TList<string>;
  i       : Integer;
begin
  Result:= DefaultIniPath;
  Filtered:= TList<string>.Create;
  try
    i:= 0;
    while i <= High(AArgs) do
    begin
      if (AArgs[i] = '--ini') and (i + 1 <= High(AArgs)) then
      begin
        Result:= AArgs[i + 1];
        Inc(i, 2);
      end
      else
      begin
        Filtered.Add(AArgs[i]);
        Inc(i);
      end;
    end;
    AArgs:= Filtered.ToArray;
  finally
    Filtered.Free;
  end; // try
end; // function

procedure ParseFlags(var AArgs: TArray<string>; var AOpts: TYadfOptions; out AOutFile: string; out AStdoutMode: Boolean);
var
  i   : Integer;
  Out_: TList<string>;
begin
  AOutFile   := ''   ;
  AStdoutMode:= False;
  Out_:= TList<string>.Create;
  try
    i:= 0;
    while i <= High(AArgs) do
    begin
      if AArgs[i] = '--max-len' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--max-len requires a value');
        AOpts.MaxLen:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--indent' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--indent requires a value');
        AOpts.Indent:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--tab-width' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--tab-width requires a value');
        AOpts.TabWidth:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--o' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--o requires a file path');
        AOutFile:= AArgs[i + 1];
        Inc(i, 2);
      end
      else if AArgs[i] = '--of' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--of requires a folder path');
        AOpts.ResultDir:= AArgs[i + 1];
        Inc(i, 2);
      end
      else if AArgs[i] = '--no-o' then
      begin
        AOpts.ResultDir:= '';
        AOutFile:= '';
        Inc(i);
      end
      else if AArgs[i] = '--b' then
      begin
        AOpts.Backup:= True;
        if (i + 1 <= High(AArgs)) and not AArgs[i + 1].StartsWith('--') then
        begin
          AOpts.BackupDir:= AArgs[i + 1];
          Inc(i, 2);
        end
        else
        begin
          AOpts.BackupDir:= '';
          Inc(i);
        end;
      end
      else if AArgs[i] = '--no-b' then
      begin
        AOpts.Backup:= False;
        Inc(i);
      end
      else if AArgs[i] = '--mark-unclosed' then
      begin
        AOpts.MarkUnclosed:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-label-blocks' then
      begin
        AOpts.LabelLongBlocks:= False;
        Inc(i);
      end
      else if AArgs[i] = '--label-min-lines' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--label-min-lines requires a value');
        AOpts.LabelMinLines:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--max-blank-lines' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--max-blank-lines requires a value');
        AOpts.MaxBlankLines:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--no-trim-trailing' then
      begin
        AOpts.TrimTrailing:= False;
        Inc(i);
      end
      else if AArgs[i] = '--no-reflow' then
      begin
        AOpts.ReflowLines:= False;
        Inc(i);
      end
      else if AArgs[i] = '--no-lowercase-keywords' then
      begin
        AOpts.LowercaseKeywords:= False;
        Inc(i);
      end
      else if AArgs[i] = '--no-upper-hex' then
      begin
        AOpts.UpperHexNumbers:= False;
        Inc(i);
      end
      else if AArgs[i] = '--no-upper-directives' then
      begin
        AOpts.UpperDirectives:= False;
        Inc(i);
      end
      else if AArgs[i] = '--no-first-occ' then
      begin
        AOpts.FirstOccCasing:= False;
        Inc(i);
      end
      else if AArgs[i] = '--blanks-before-section' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--blanks-before-section requires a value');
        AOpts.BlanksBeforeSection:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--blanks-before-method' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--blanks-before-method requires a value');
        AOpts.BlanksBeforeMethod:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--blanks-before-type' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--blanks-before-type requires a value');
        AOpts.BlanksBeforeType:= StrToInt(AArgs[i + 1]);
        Inc(i, 2);
      end
      else if AArgs[i] = '--stdout' then
      begin
        AStdoutMode:= True;
        Inc(i);
      end
      else if AArgs[i] = '--d10' then
      begin
        AOpts.Delphi10Compat:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-d10' then
      begin
        AOpts.Delphi10Compat:= False;
        Inc(i);
      end
      else if AArgs[i] = '--encoding' then
      begin
        if i + 1 > High(AArgs) then
          raise Exception.Create('--encoding requires ansi|utf8|utf16');
        AOpts.Encoding:= ParseEncoding(AArgs[i + 1], AOpts.Encoding);
        Inc(i, 2);
      end
      else if AArgs[i] = '--log' then
      begin
        AOpts.Logging:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-log' then
      begin
        AOpts.Logging:= False;
        Inc(i);
      end
      else if AArgs[i] = '--uses-break' then
      begin
        AOpts.UsesAlwaysBreak:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-uses-break' then
      begin
        AOpts.UsesAlwaysBreak:= False;
        Inc(i);
      end
      else if AArgs[i] = '--break-case' then
      begin
        AOpts.BreakCaseLabels:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-break-case' then
      begin
        AOpts.BreakCaseLabels:= False;
        Inc(i);
      end
      else if AArgs[i] = '--indent-comments' then
      begin
        AOpts.IndentComments:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-indent-comments' then
      begin
        AOpts.IndentComments:= False;
        Inc(i);
      end
      else if AArgs[i] = '--pack-bodies' then
      begin
        AOpts.PackShortBodies:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-pack-bodies' then
      begin
        AOpts.PackShortBodies:= False;
        Inc(i);
      end
      else if AArgs[i] = '--collapse-blocks' then
      begin
        AOpts.CollapseShortBlocks:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-collapse-blocks' then
      begin
        AOpts.CollapseShortBlocks:= False;
        Inc(i);
      end
      else
      begin
        Out_.Add(AArgs[i]);
        Inc(i);
      end;
    end; // while
    AArgs:= Out_.ToArray;
  finally
    Out_.Free;
  end; // try
end; // procedure

procedure RunYadf;
var
  AllFiles  : TList<string>;
  Args      : TArray<string>;
  Diff      : Integer;
  F         : string;
  Files     : TArray<string>;
  i         : Integer;
  IniPath   : string;
  Opts      : TYadfOptions;
  OutFile   : string;
  Spec      : string;
  StdoutMode: Boolean;
begin
  SetLength(Args, ParamCount);
  for i:= 1 to ParamCount do Args[i - 1]:= ParamStr(i);

  for i:= 0 to High(Args) do if IsHelpArg(Args[i]) then
  begin
    Opts:= DefaultOptions;
    LoadIniDefaults(Opts, DefaultIniPath);
    ShowUsage(Opts);
    Exit;
  end;

  IniPath:= ExtractIniPath(Args);
  Opts:= DefaultOptions;
  // First-run: if no INI exists at the resolved path, materialise a
  // fully-commented template with all defaults. Subsequent runs see
  // an existing file and load it normally.
  if EnsureIniExists(IniPath) then
    WriteStdoutLine('Created default config: ' + IniPath);
  LoadIniDefaults(Opts, IniPath);
  ParseFlags(Args, Opts, OutFile, StdoutMode);
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
    if Length(Args) <> 3 then
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
    for Spec in Args do
    begin
      Files:= ExpandFileSpec(Spec, Opts);
      for F in Files do AllFiles.Add(F);
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
