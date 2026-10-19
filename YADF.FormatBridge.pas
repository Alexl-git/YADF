{
  YADF.FormatBridge -- IDE-independent logic behind the Delphi 13.2
  IOTACodeFormatter adapter (YADFOT.CodeFormatter).

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Everything here is a pure string/byte function (no ToolsAPI, no VCL
  dialogs), so it is unit-testable from a console program
  (Test\FormatBridgeTest.dpr) and compiles in every IDE generation.

  Offset model: the IDE hands the formatter UTF8String content and BYTE
  offsets into it. All offsets here are 0-based byte offsets (the same base
  IOTAEditReader.GetText uses). This is an ASSUMPTION about the 13.2 IDE that
  Test\MANUAL-IDE-CODEFORMATTER.md verifies live.
}

unit YADF.FormatBridge;

interface

uses
  YADF.Options;

type
  /// <summary>Signature of the string-to-string formatting step (the shape of
  /// YADF.Layout.FormatSource with a decline reason). Exists as a test seam.</summary>
  /// <param name="ASource">Unit text to format.</param>
  /// <param name="AOpts">Resolved options.</param>
  /// <param name="ADeclineReason">'' on success, else why the content guard declined.</param>
  /// <returns>The formatted text (only meaningful when ADeclineReason is '').</returns>
  TYadfFormatFunc = function(const ASource: string; const AOpts: TYadfOptions; out ADeclineReason: string): string;

/// <summary>True when AFileName has an extension YADF can format (.pas .dpr .dpk .inc).</summary>
/// <param name="AFileName">Any path or bare file name; case-insensitive.</param>
/// <returns>False for form streams (.dfm/.fmx), resources, scratch buffers and ''.</returns>
function IsPascalSourceFile(const AFileName: string): Boolean;

/// <summary>Decodes IDE UTF-8 content to a Delphi string without touching a BOM.</summary>
/// <param name="AContent">UTF-8 bytes as the IDE passes them.</param>
/// <returns>The decoded text; '' for empty input.</returns>
function Utf8ToText(const AContent: UTF8String): string;

/// <summary>Encodes text to UTF-8 bytes (surrogate pairs preserved), never adding a BOM.</summary>
/// <param name="AText">Delphi string.</param>
/// <returns>The UTF-8 bytes; empty for empty input.</returns>
function TextToUtf8(const AText: string): UTF8String;

/// <summary>Formats IDE content with the YADF engine, all-or-nothing.</summary>
/// <param name="AContent">UTF-8 unit content from the IDE.</param>
/// <param name="AOpts">Resolved options.</param>
/// <param name="AFormatted">Formatted UTF-8 text on True; on False it is AContent unchanged.</param>
/// <param name="ADeclined">'' on True; else the guard decline reason or 'ClassName: message' of an engine exception.</param>
/// <param name="AFormat">Test seam; nil (default) uses the real YADF.Layout.FormatSource.</param>
/// <returns>True only when the engine ran and the content guard accepted its result.</returns>
/// <remarks>Never raises. A decline or exception can therefore never hand the IDE partial or
/// corrupt text: the original bytes come back and the reason is reported. Not thread-safe
/// (the engine keeps unit-level state); call from the IDE main thread.</remarks>
function FormatUtf8Content(const AContent: UTF8String; const AOpts: TYadfOptions; out AFormatted: UTF8String;
  out ADeclined: string; AFormat: TYadfFormatFunc = nil): Boolean;

/// <summary>Expands a byte range to the whole lines that contain it.</summary>
/// <param name="AContent">The unit content.</param>
/// <param name="AOffset">0-based byte offset of the selection start (the caret when ALen = 0).</param>
/// <param name="ALen">Selection length in bytes.</param>
/// <param name="ALineStart">Byte offset of the first covered line's first byte.</param>
/// <param name="ALineEnd">Byte offset just past the last covered line's line break (or the content length).</param>
/// <returns>False when the range is invalid (negative, or reaching past the content).</returns>
/// <remarks>A selection that ends exactly at the start of a line does not include that line.</remarks>
function ExpandToWholeLines(const AContent: UTF8String; AOffset, ALen: Integer; out ALineStart, ALineEnd: Integer): Boolean;

/// <summary>True when the selection, expanded to whole lines, is the entire non-empty content
/// (e.g. Select All). The adapter treats such a selection as a whole-file format.</summary>
/// <param name="AContent">The unit content.</param>
/// <param name="AOffset">0-based byte offset of the selection start.</param>
/// <param name="ALen">Selection length in bytes.</param>
/// <returns>False for an invalid range, empty content or a partial selection.</returns>
function SelectionCoversWholeContent(const AContent: UTF8String; AOffset, ALen: Integer): Boolean;

/// <summary>Maps a caret byte offset from the original to the formatted text by (line, column).</summary>
/// <param name="AOriginal">Content before formatting.</param>
/// <param name="AFormatted">Content after formatting.</param>
/// <param name="AOffset">0-based caret byte offset in AOriginal (clamped into range).</param>
/// <returns>A byte offset in AFormatted on the same line index and column, each clamped to what
/// exists, never inside a multi-byte UTF-8 character; 0 for empty AFormatted.</returns>
/// <remarks>Formatting can change line counts, so this is a best-effort caret restore, not offset
/// remapping (the adapter reports SupportsOffsetRemapping = False).</remarks>
function RemapCursorOffset(const AOriginal, AFormatted: UTF8String; AOffset: Integer): Integer;

/// <summary>Options of the F profile, resolved exactly as the Ctrl+Shift+Alt+F command does.</summary>
/// <returns>%APPDATA%\YADF\profiles.ini [Profiles]F (default yadf.ini), materialised with the
/// commented template when absent, then loaded over DefaultOptions.</returns>
/// <exception cref="EIniFileException">Raised if profiles/INI cannot be read.</exception>
function ResolveFProfileOptions: TYadfOptions;

implementation

uses
  System.SysUtils
  , YADF.Layout
  ;

function IsPascalSourceFile(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext:= LowerCase(ExtractFileExt(AFileName));
  Result:= (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc');
end;

function Utf8ToText(const AContent: UTF8String): string;
begin
  if Length(AContent) = 0 then Exit('');
  Result:= TEncoding.UTF8.GetString(BytesOf(AContent));
end;

function TextToUtf8(const AText: string): UTF8String;
var
  Bytes: TBytes;
begin
  if AText = '' then Exit('');
  Bytes:= TEncoding.UTF8.GetBytes(AText);
  SetLength(Result, Length(Bytes));
  Move(Bytes[0], Result[1], Length(Bytes));
end;

function EngineFormat(const ASource: string; const AOpts: TYadfOptions; out ADeclineReason: string): string;
begin
  Result:= FormatSource(ASource, AOpts, ADeclineReason);
end;

function FormatUtf8Content(const AContent: UTF8String; const AOpts: TYadfOptions; out AFormatted: UTF8String;
  out ADeclined: string; AFormat: TYadfFormatFunc): Boolean;
var
  Fmt      : TYadfFormatFunc;
  Text     : string;
  Formatted: string;
begin
  AFormatted:= AContent;
  ADeclined := '';
  Fmt:= AFormat;
  if not Assigned(Fmt) then Fmt:= EngineFormat;
  try
    Text     := Utf8ToText(AContent);
    Formatted:= Fmt(Text, AOpts, ADeclined);
  except
    on E: Exception do
    begin
      ADeclined := E.ClassName + ': ' + E.Message;
      AFormatted:= AContent;
      Exit(False);
    end;
  end;
  if ADeclined <> '' then
  begin
    AFormatted:= AContent;
    Exit(False);
  end;
  AFormatted:= TextToUtf8(Formatted);
  Result    := True;
end;

function ExpandToWholeLines(const AContent: UTF8String; AOffset, ALen: Integer; out ALineStart, ALineEnd: Integer): Boolean;
var
  L, LastB: Integer;
begin
  ALineStart:= 0;
  ALineEnd  := 0;
  L:= Length(AContent);
  if (AOffset < 0) or (ALen < 0) or (AOffset > L) or (AOffset + ALen > L) then Exit(False);
  ALineStart:= AOffset;
  while (ALineStart > 0) and (AContent[ALineStart] <> #10) do Dec(ALineStart);
  LastB:= AOffset;
  if ALen > 0 then LastB:= AOffset + ALen - 1;
  ALineEnd:= LastB;
  while (ALineEnd < L) and (AContent[ALineEnd + 1] <> #10) do Inc(ALineEnd);
  if ALineEnd < L then Inc(ALineEnd);
  Result:= True;
end;

function SelectionCoversWholeContent(const AContent: UTF8String; AOffset, ALen: Integer): Boolean;
var
  S, E: Integer;
begin
  Result:= (Length(AContent) > 0) and ExpandToWholeLines(AContent, AOffset, ALen, S, E) and (S = 0) and (E = Length(AContent));
end;

function RemapCursorOffset(const AOriginal, AFormatted: UTF8String; AOffset: Integer): Integer;
const
  ContMask = $C0;   // UTF-8 continuation bytes are 10xxxxxx
  ContBits = $80;
var
  i, Line, LineStart, Col, S, E, K, LenB: Integer;
begin
  LenB:= Length(AFormatted);
  if LenB = 0 then Exit(0);
  if AOffset < 0 then AOffset:= 0;
  if AOffset > Length(AOriginal) then AOffset:= Length(AOriginal);
  // line index and byte column of the caret in the original
  Line     := 0;
  LineStart:= 0;
  for i:= 1 to AOffset do
    if AOriginal[i] = #10 then
    begin
      Inc(Line);
      LineStart:= i;
    end;
  Col:= AOffset - LineStart;
  // start of the same line index in the result (clamped to its last line)
  S:= 0;
  K:= 0;
  while K < Line do
  begin
    E:= S;
    while (E < LenB) and (AFormatted[E + 1] <> #10) do Inc(E);
    if E >= LenB then Break;
    S:= E + 1;
    Inc(K);
  end;
  // end of that line, excluding its CR/LF
  E:= S;
  while (E < LenB) and (AFormatted[E + 1] <> #13) and (AFormatted[E + 1] <> #10) do Inc(E);
  if Col > E - S then Col:= E - S;
  Result:= S + Col;
  while (Result > S) and (Result < LenB) and ((Byte(AFormatted[Result + 1]) and ContMask) = ContBits) do Dec(Result);
end;

function ResolveFProfileOptions: TYadfOptions;
var
  IniPath: string;
begin
  Result:= DefaultOptions;
  IniPath:= ResolveProfileIniPath(LoadProfiles.F);
  if IniPath = '' then
    IniPath:= SharedAppDataIniPath;   // defensive: F is never '' (defaults to yadf.ini)
  EnsureIniExists(IniPath);
  if FileExists(IniPath) then
    Result:= LoadOptionsFromIni(IniPath);
end;

end.
