{
  YADFOT.CodeFormatter -- registers YADF as the IDE's own code formatter on
  Delphi 13.2+ (Open Tools API IOTACodeFormatter / IOTACodeFormatterServices).

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Gate: the whole implementation sits behind YADF_HAS_CODEFORMATTER (see
  YADFOT.CodeFormatter.inc). On an IDE whose ToolsAPI lacks IOTACodeFormatter
  this unit compiles to three no-ops, so older IDEs build and behave exactly
  as before. The public procedures are declared unconditionally so callers
  (YADFOT.Wizard, YADFOT.Options) carry no conditional code of their own.

  Coexistence with the classic path: the Tools-menu item and the
  Ctrl+Shift+Alt+F / R shortcuts (YADFOT.Wizard) are untouched and keep
  writing the editor buffer through the undoable writer. The new path is
  opt-in ([IDE] NativeFormatter in profiles.ini, off by default): when on, the
  IDE's own Format Source (and format-on-save, if the user enabled it in the
  IDE) asks THIS formatter; the IDE applies the returned text itself, so it
  owns undo, caret and form-designer safety. The R profile stays exclusive to
  its shortcut. Safety guard: any decline or engine failure returns False and
  the IDE keeps the original text.
}

unit YADFOT.CodeFormatter;

interface

uses
  ToolsAPI;  // dl:ok unused-unit-in-uses@0152 -- DECLARED(IOTACodeFormatter) in the .inc resolves against it

{$I YADFOT.CodeFormatter.inc}

/// <summary>True when this build can register an IDE code formatter (ToolsAPI declares
/// IOTACodeFormatter, i.e. Delphi 13.2+, and YADF_NO_CODEFORMATTER is not defined).</summary>
/// <returns>A compile-time constant; the Options page shows its switch only when True.</returns>
function CodeFormatterAvailable: Boolean;

/// <summary>Registers YADF with IOTACodeFormatterServices when the build supports it AND the
/// user enabled profiles.ini [IDE] NativeFormatter. Idempotent.</summary>
/// <remarks>Call from the package Register procedure on the IDE main thread. A no-op on IDEs
/// without IOTACodeFormatter and when the switch is off.</remarks>
procedure RegisterYadfCodeFormatter;

/// <summary>Hands the formatter back to the IDE. Idempotent; safe when the services are
/// already gone (late IDE shutdown).</summary>
/// <remarks>Call from the wizard's Destroyed (primary, before the BPL code segment is
/// dropped) and from finalization (backstop).</remarks>
procedure UnregisterYadfCodeFormatter;

implementation

{$IFDEF YADF_HAS_CODEFORMATTER}
uses
  System.SysUtils
  , System.UITypes
  , Vcl.Dialogs
  , YADF.Options
  , YADF.FormatBridge
  ;

type
  /// <summary>YADF as an IOTACodeFormatter: whole-unit formatting with the F profile.</summary>
  /// <remarks>Main-thread only (the IDE calls it from its UI thread; the engine is not
  /// thread-safe). FormatLine/CanFormatLine and offset remapping are deliberately
  /// unsupported. Reference-counted: the module global holds one reference, the IDE another.</remarks>
  TYadfCodeFormatter = class(TInterfacedObject, IOTACodeFormatter)
  private
    FConfirmDlg: Boolean;
    procedure ReportProblem(const AText: string);
  public
    /// <summary>True for .pas .dpr .dpk .inc.</summary>
    function HandleFile(const AFileName: string): Boolean;
    /// <summary>Formats the selection only when it covers every line (Select All); otherwise declines.</summary>
    /// <returns>False (IDE keeps the text) for a partial selection: fragments cannot be formatted
    /// safely because the engine needs a whole unit to establish indentation.</returns>
    function FormatSelected(const AModule: IOTAModule; const AContent: UTF8String;
      ASelectedOffset, ASelectedLen: Integer; var ACursorOffset: Integer;
      var AFormattedText: UTF8String): Boolean;
    /// <summary>Formats the whole unit with the F profile.</summary>
    /// <returns>True with AFormattedText set; False when the guard declines or the engine fails
    /// (a dialog names the reason and the IDE keeps the original text).</returns>
    function FormatFile(const AModule: IOTAModule; const AContent: UTF8String;
      var ACursorOffset: Integer; var AFormattedText: UTF8String): Boolean;
    /// <summary>Unsupported: always False.</summary>
    function FormatLine(const AModule: IOTAModule; const AEditorContent: IOTAEditorContent;
      const AContent: UTF8String; ASelectedOffset, ASelectedLen: Integer;
      var ACursorOffset: Integer; var AFormattedText: UTF8String): Boolean;
    /// <summary>Unsupported: always False, so the IDE never auto-formats single lines.</summary>
    function CanFormatLine(const AModule: IOTAModule; const AEdPos: TOTAEditPos;
      ANumLines: Integer): Boolean;
    /// <summary>False: breakpoints/bookmarks are not remapped.</summary>
    function SupportsOffsetRemapping: Boolean;
    /// <summary>False: YADF has no format-on-save option of its own.</summary>
    function CanFormatOnSave: Boolean;
    function GetConfirmDlg: Boolean;
    procedure SetConfirmDlg(AValue: Boolean);
    /// <summary>''. The classic command never prompts, and neither does this path.</summary>
    function GetConfirmDlgHintText: string;
  end;

var
  GFormatter: IOTACodeFormatter = nil;

procedure TYadfCodeFormatter.ReportProblem(const AText: string);
begin
  MessageDlg('YADFOT: ' + AText, mtWarning, [mbOK], 0);
end;

function TYadfCodeFormatter.HandleFile(const AFileName: string): Boolean;
begin
  Result:= IsPascalSourceFile(AFileName);
end;

function TYadfCodeFormatter.FormatFile(const AModule: IOTAModule; const AContent: UTF8String;
  var ACursorOffset: Integer; var AFormattedText: UTF8String): Boolean;
var
  Declined: string;
  Text    : UTF8String;
begin
  Result:= False;
  try
    if not FormatUtf8Content(AContent, ResolveFProfileOptions, Text, Declined) then
    begin
      ReportProblem('buffer left unchanged -- the content guard declined the result.' + sLineBreak + Declined);
      Exit;
    end;
    ACursorOffset  := RemapCursorOffset(AContent, Text, ACursorOffset);
    AFormattedText := Text;
    Result:= True;
  except
    on E: Exception do
      ReportProblem('format failed.' + sLineBreak + E.ClassName + ': ' + E.Message);
  end;
end;

function TYadfCodeFormatter.FormatSelected(const AModule: IOTAModule; const AContent: UTF8String;
  ASelectedOffset, ASelectedLen: Integer; var ACursorOffset: Integer; var AFormattedText: UTF8String): Boolean;
begin
  if SelectionCoversWholeContent(AContent, ASelectedOffset, ASelectedLen) then
    Exit(FormatFile(AModule, AContent, ACursorOffset, AFormattedText));
  ReportProblem('selection left unchanged -- YADF formats whole units only.' + sLineBreak +
    'Select nothing (or Select All) and format again.');
  Result:= False;
end;

function TYadfCodeFormatter.FormatLine(const AModule: IOTAModule; const AEditorContent: IOTAEditorContent;
  const AContent: UTF8String; ASelectedOffset, ASelectedLen: Integer; var ACursorOffset: Integer;
  var AFormattedText: UTF8String): Boolean;
begin
  Result:= False;
end;

function TYadfCodeFormatter.CanFormatLine(const AModule: IOTAModule; const AEdPos: TOTAEditPos;
  ANumLines: Integer): Boolean;
begin
  Result:= False;
end;

function TYadfCodeFormatter.SupportsOffsetRemapping: Boolean;
begin
  Result:= False;
end;

function TYadfCodeFormatter.CanFormatOnSave: Boolean;
begin
  Result:= False;
end;

function TYadfCodeFormatter.GetConfirmDlg: Boolean;
begin
  Result:= FConfirmDlg;
end;

procedure TYadfCodeFormatter.SetConfirmDlg(AValue: Boolean);
begin
  FConfirmDlg:= AValue;
end;

function TYadfCodeFormatter.GetConfirmDlgHintText: string;
begin
  Result:= '';
end;

function CodeFormatterAvailable: Boolean;
begin
  Result:= True;
end;

procedure RegisterYadfCodeFormatter;
var
  Svc: IOTACodeFormatterServices;
begin
  if GFormatter <> nil then Exit;
  if not LoadNativeFormatterFlag(ProfilesIniPath) then Exit;
  if not Supports(BorlandIDEServices, IOTACodeFormatterServices, Svc) then Exit;
  GFormatter:= TYadfCodeFormatter.Create;
  Svc.AddFormatter(GFormatter);
end;

procedure UnregisterYadfCodeFormatter;
var
  Svc: IOTACodeFormatterServices;
begin
  if GFormatter = nil then Exit;
  if Supports(BorlandIDEServices, IOTACodeFormatterServices, Svc) then
    try Svc.RemoveFormatter(GFormatter); except end;  // dl:ok empty-except@cf01
  GFormatter:= nil;
end;

initialization

finalization
  try UnregisterYadfCodeFormatter; except end;  // dl:ok empty-except@cf02

{$ELSE}

function CodeFormatterAvailable: Boolean;
begin
  Result:= False;
end;

procedure RegisterYadfCodeFormatter;
begin
  // Older IDE (no IOTACodeFormatter): nothing to register.
end;

procedure UnregisterYadfCodeFormatter;
begin
  // Older IDE: nothing was registered.
end;

{$ENDIF}

end.
