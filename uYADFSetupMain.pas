unit uYADFSetupMain;

interface

uses
  Winapi.Windows
  , System.SysUtils
  , System.Classes
  , System.UITypes
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.Dialogs
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , YADF.OptionsFrame
  ;

type
  /// <summary>YADFSetup main window: a thin shell around the shared
  /// TYadfOptionsFrame (YADF.OptionsFrame), which carries the Profiles panel,
  /// the option grid and the live preview for BOTH YADFSetup and the IDE
  /// options page. The shell contributes only the top bar -- Load Settings /
  /// Save As... / Reset buttons and the INI status label -- and runs the frame
  /// under SetupPersistPolicy (autosave on every change; no OK/Cancel).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (YADFSetup.dpr), declaration (uYADFSetupMain.pas), declaration (Micronite2027.dpr), declaration (uMain.pas), uMain.TfrmMAIN.FormCreate (uMain.pas) (+55 more)
  /// Used in units: drag_lint_graph, MainForm, Micronite2027, uCompileToolFeatures, uCompileToolMain, uMain, Unit1, uYADFSetupMain, YADFSetup
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TfrmMain = class(TForm)
    pnlTopBar      : TPanel     ;
    btnLoadSettings: TButton    ;
    btnSaveSettings: TButton    ;
    btnReset       : TButton    ;
    lblIniPath     : TLabel     ;
    dlgOpen        : TOpenDialog;
    dlgSaveIni     : TSaveDialog;
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.Create, YADF.OptionsFrame.TYadfOptionsFrame.Load
    /// Reads: FFrame   Writes: FFrame
    /// Handles: frmMain.OnCreate
    /// UI thread only -- touches FFrame
    /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Create"/>
    /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Load"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnLoadSettingsClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnResetClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnSaveSettingsClick"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure FormCreate          (Sender: TObject);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.LoadOptionsFromFile
    /// Reads: dlgOpen, FFrame
    /// Handles: btnLoadSettings.OnClick
    /// UI thread only -- touches FFrame
    /// Pure
    /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.LoadOptionsFromFile"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnResetClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnSaveSettingsClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.FormCreate"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.HandleIniStatus"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure btnLoadSettingsClick(Sender: TObject);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.SaveOptionsToFile
    /// Reads: dlgSaveIni, FFrame
    /// Handles: btnSaveSettings.OnClick
    /// UI thread only -- touches FFrame
    /// Pure
    /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.SaveOptionsToFile"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnLoadSettingsClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnResetClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.FormCreate"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.HandleIniStatus"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure btnSaveSettingsClick(Sender: TObject);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: ExtractFileName, MessageDlg, YADF.OptionsFrame.TYadfOptionsFrame.ResetToDefaults
    /// Reads: FFrame
    /// Handles: btnReset.OnClick
    /// UI thread only -- touches FFrame
    /// Pure
    /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.ResetToDefaults"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnLoadSettingsClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.btnSaveSettingsClick"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.FormCreate"/>
    /// <seealso cref="uYADFSetupMain.TfrmMain.HandleIniStatus"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure btnResetClick       (Sender: TObject);
    private
      FFrame: TYadfOptionsFrame; // owned by the form; fills the client area
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Reads: lblIniPath
      /// Pure
      /// <seealso cref="uYADFSetupMain.TfrmMain.btnLoadSettingsClick"/>
      /// <seealso cref="uYADFSetupMain.TfrmMain.btnResetClick"/>
      /// <seealso cref="uYADFSetupMain.TfrmMain.btnSaveSettingsClick"/>
      /// <seealso cref="uYADFSetupMain.TfrmMain.FormCreate"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleIniStatus(const AText: string);
  end;

var
  frmMain: TfrmMain;  // dl:ok global-form-variable@0045

implementation

{$R *.dfm}

{$I YADF.Version.inc}

// Read the FileVersion stamped into THIS running exe (so the title bar always
// reflects the actual binary -- the YADF.Version.inc constant is only a
// fallback if the version resource is missing).
function GetExeVersion: string;
var
  Sz   : DWORD           ;
  H    : DWORD           ;
  Buf  : TBytes          ;
  Fixed: PVSFixedFileInfo;
  Len  : UINT            ;
begin
  Result:= '';
  Sz:= GetFileVersionInfoSize(PChar(Application.ExeName), H);
  if Sz = 0 then
    Exit;
  SetLength(Buf, Sz);
  if GetFileVersionInfo(PChar(Application.ExeName), 0, Sz, Pointer(Buf)) then
    if VerQueryValue(Pointer(Buf), '\', Pointer(Fixed), Len) and (Fixed <> nil) then
      Result:= Format('%d.%d.%d.%d', [HiWord(Fixed.dwFileVersionMS), LoWord(Fixed.dwFileVersionMS), HiWord(Fixed.dwFileVersionLS), LoWord(Fixed.dwFileVersionLS)]);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  Ver: string;
begin
  Ver:= GetExeVersion;
  if Ver = '' then
    Ver:= YADF_VERSION;
  Caption:= 'YADFSetup ' + Ver + '  -  Profiles | Settings | Source | Result';
  FFrame:= TYadfOptionsFrame.Create(Self);
  FFrame.Parent     := Self;
  FFrame.Align      := alClient;
  FFrame.Policy     := SetupPersistPolicy; // autosave + F -> yadf.ini mirror
  FFrame.OnIniStatus:= HandleIniStatus;
  FFrame.Load;
end; // procedure

procedure TfrmMain.HandleIniStatus(const AText: string);
begin
  lblIniPath.Caption:= AText;
end;

procedure TfrmMain.btnLoadSettingsClick(Sender: TObject);
begin
  if dlgOpen.Execute then
    FFrame.LoadOptionsFromFile(dlgOpen.FileName);
end;

procedure TfrmMain.btnSaveSettingsClick(Sender: TObject);
begin
  if dlgSaveIni.Execute then
    FFrame.SaveOptionsToFile(dlgSaveIni.FileName);
end;

procedure TfrmMain.btnResetClick(Sender: TObject);
begin
  if MessageDlg('Reset all settings to defaults? This overwrites ' + ExtractFileName(FFrame.CurrentIniPath) + '.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  FFrame.ResetToDefaults;
end;

end.
