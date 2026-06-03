unit uYADFSetupMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Variants,
  System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Samples.Spin, Vcl.Clipbrd,
  YADF.Options, YADF.Layout;

type
  TfrmMain = class(TForm)
    pnlSettings: TPanel;
    splLeft: TSplitter;
    pnlSource: TPanel;
    splRight: TSplitter;
    pnlResult: TPanel;
    pnlSettingsBar: TPanel;
    btnLoadSettings: TButton;
    btnSaveSettings: TButton;
    btnReset: TButton;
    lblIniPath: TLabel;
    sbSettings: TScrollBox;
    pnlSourceBar: TPanel;
    btnOpenSource: TButton;
    lblSourceFile: TLabel;
    memSource: TMemo;
    pnlResultBar: TPanel;
    btnCopy: TButton;
    lblResultStatus: TLabel;
    memResult: TMemo;
    dlgOpen: TOpenDialog;
    dlgSaveIni: TSaveDialog;
    tmrReformat: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure btnOpenSourceClick(Sender: TObject);
    procedure btnLoadSettingsClick(Sender: TObject);
    procedure btnSaveSettingsClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure memSourceChange(Sender: TObject);
    procedure tmrReformatTimer(Sender: TObject);
  private
    FOpts: TYadfOptions;
    FIniPath: string;
    FControls: array of TControl;   // index-aligned to OptionTable
    FUpdating: Boolean;             // True while we push FOpts -> controls;
                                    // suppresses OptionChanged so the
                                    // programmatic writes don't clobber FOpts.
    procedure BuildOptionControls;
    procedure OptionsToControls;
    procedure ControlsToOptions;
    procedure OptionChanged(Sender: TObject);
    procedure Reformat;
    procedure AutoSave;
    procedure LoadSample;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

{$I YADF.Version.inc}

// Read the FileVersion stamped into THIS running exe (so the title bar always
// reflects the actual binary -- the YADF.Version.inc constant is only a
// fallback if the version resource is missing).
function GetExeVersion: string;
var
  Sz, H : DWORD;
  Buf   : TBytes;
  Fixed : PVSFixedFileInfo;
  Len   : UINT;
begin
  Result := '';
  Sz := GetFileVersionInfoSize(PChar(Application.ExeName), H);
  if Sz = 0 then Exit;
  SetLength(Buf, Sz);
  if GetFileVersionInfo(PChar(Application.ExeName), 0, Sz, Pointer(Buf)) then
    if VerQueryValue(Pointer(Buf), '\', Pointer(Fixed), Len) and (Fixed <> nil) then
      Result := Format('%d.%d.%d.%d',
        [HiWord(Fixed.dwFileVersionMS), LoWord(Fixed.dwFileVersionMS),
         HiWord(Fixed.dwFileVersionLS), LoWord(Fixed.dwFileVersionLS)]);
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  Ver: string;
begin
  Ver := GetExeVersion;
  if Ver = '' then Ver := YADF_VERSION;
  Caption := 'YADFSetup ' + Ver + '  -  Settings | Source | Result';
  FIniPath := SharedAppDataIniPath;
  EnsureIniExists(FIniPath);
  FOpts := LoadOptionsFromIni(FIniPath);
  lblIniPath.Caption := 'INI: ' + FIniPath;
  BuildOptionControls;
  OptionsToControls;
  LoadSample;
  Reformat;
end;

procedure TfrmMain.BuildOptionControls;
var
  T: TArray<TOptInfo>;
  i, y: Integer;
  CurGrp: string;
  gb: TGroupBox;
  parent: TWinControl;
  yIn: Integer;
  cb: TCheckBox;
  se: TSpinEdit;
  ed: TEdit;
  cmb: TComboBox;
  lbl: TLabel;
begin
  T := OptionTable;
  SetLength(FControls, Length(T));
  CurGrp := '';
  gb := nil;
  parent := sbSettings;
  y := 4;
  yIn := 0;
  for i := 0 to High(T) do
  begin
    if T[i].Group <> CurGrp then
    begin
      CurGrp := T[i].Group;
      gb := TGroupBox.Create(Self);
      gb.Parent := sbSettings;
      gb.Left := 4;
      gb.Top := y;
      gb.Width := sbSettings.ClientWidth - 28;
      gb.Anchors := [akLeft, akTop, akRight];
      gb.Caption := CurGrp;
      parent := gb;
      yIn := 18;
    end;
    case T[i].Kind of
      okBool:
        begin
          cb := TCheckBox.Create(Self);
          cb.Parent := parent;
          cb.Left := 10; cb.Top := yIn; cb.Width := gb.Width - 20;
          cb.Caption := T[i].Caption;
          cb.Hint := T[i].Hint; cb.ShowHint := True;
          cb.Tag := i; cb.OnClick := OptionChanged;
          FControls[i] := cb;
          Inc(yIn, 24);
        end;
      okInt:
        begin
          lbl := TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left := 10; lbl.Top := yIn + 3;
          lbl.Caption := T[i].Caption;
          se := TSpinEdit.Create(Self);
          se.Parent := parent; se.Left := 200; se.Top := yIn; se.Width := 70;
          se.MinValue := 0; se.MaxValue := 100000;
          se.Hint := T[i].Hint; se.ShowHint := True;
          se.Tag := i; se.OnChange := OptionChanged;
          FControls[i] := se;
          Inc(yIn, 28);
        end;
      okString:
        begin
          lbl := TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left := 10; lbl.Top := yIn + 3;
          lbl.Caption := T[i].Caption;
          ed := TEdit.Create(Self);
          ed.Parent := parent; ed.Left := 200; ed.Top := yIn; ed.Width := gb.Width - 210;
          ed.Anchors := [akLeft, akTop, akRight];
          ed.Hint := T[i].Hint; ed.ShowHint := True;
          ed.Tag := i; ed.OnChange := OptionChanged;
          FControls[i] := ed;
          Inc(yIn, 28);
        end;
      okEnum:
        begin
          lbl := TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left := 10; lbl.Top := yIn + 3;
          lbl.Caption := T[i].Caption;
          cmb := TComboBox.Create(Self);
          cmb.Parent := parent; cmb.Left := 200; cmb.Top := yIn; cmb.Width := 100;
          cmb.Style := csDropDownList;
          cmb.Items.Add('ANSI'); cmb.Items.Add('UTF-8'); cmb.Items.Add('UTF-16');
          cmb.Hint := T[i].Hint; cmb.ShowHint := True;
          cmb.Tag := i; cmb.OnChange := OptionChanged;
          FControls[i] := cmb;
          Inc(yIn, 28);
        end;
    end;
    if gb <> nil then
    begin
      gb.Height := yIn + 6;
      y := gb.Top + gb.Height + 6;
    end;
  end;
end;

procedure TfrmMain.OptionsToControls;
var
  T: TArray<TOptInfo>;
  i: Integer;
  v: Variant;
begin
  T := OptionTable;
  // Setting Checked/Value/Text/ItemIndex fires the control's OnClick/OnChange,
  // i.e. OptionChanged. Suppress it: otherwise each programmatic write would
  // read back the not-yet-updated controls and clobber FOpts mid-loop (which
  // broke Reset and left spin edits stuck at 0).
  FUpdating := True;
  try
    for i := 0 to High(T) do
    begin
      v := T[i].GetVal(FOpts);
      case T[i].Kind of
        okBool  : TCheckBox(FControls[i]).Checked := v;
        okInt   : TSpinEdit(FControls[i]).Value := v;
        okString: TEdit(FControls[i]).Text := VarToStr(v);
        okEnum  : TComboBox(FControls[i]).ItemIndex :=
                    TComboBox(FControls[i]).Items.IndexOf(VarToStr(v));
      end;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TfrmMain.ControlsToOptions;
var
  T: TArray<TOptInfo>;
  i: Integer;
begin
  T := OptionTable;
  for i := 0 to High(T) do
    case T[i].Kind of
      okBool  : T[i].SetVal(FOpts, TCheckBox(FControls[i]).Checked);
      okInt   : T[i].SetVal(FOpts, TSpinEdit(FControls[i]).Value);
      okString: T[i].SetVal(FOpts, TEdit(FControls[i]).Text);
      okEnum  : T[i].SetVal(FOpts, TComboBox(FControls[i]).Text);
    end;
end;

procedure TfrmMain.OptionChanged(Sender: TObject);
var
  T: TArray<TOptInfo>;
  idx: Integer;
begin
  if FUpdating then Exit;   // programmatic population in progress -- ignore
  ControlsToOptions;
  AutoSave;
  T := OptionTable;
  idx := TControl(Sender).Tag;
  if (idx >= 0) and (idx <= High(T)) and T[idx].AffectsPreview then
    Reformat;
end;

procedure TfrmMain.AutoSave;
begin
  try
    SaveOptionsToIni(FOpts, FIniPath);
    lblIniPath.Caption := 'INI: ' + FIniPath + '  (saved)';
  except
    on E: Exception do
      lblIniPath.Caption := 'INI: ' + FIniPath + '  (save failed: ' + E.Message + ')';
  end;
end;

procedure TfrmMain.Reformat;
begin
  try
    memResult.Text := FormatSource(memSource.Text, FOpts);
    lblResultStatus.Caption := 'OK';
  except
    on E: Exception do
    begin
      memResult.Text := '[Format error] ' + E.ClassName + ': ' + E.Message;
      lblResultStatus.Caption := 'error';
    end;
  end;
end;

procedure TfrmMain.memSourceChange(Sender: TObject);
begin
  tmrReformat.Enabled := False;   // debounce
  tmrReformat.Enabled := True;
end;

procedure TfrmMain.tmrReformatTimer(Sender: TObject);
begin
  tmrReformat.Enabled := False;
  Reformat;
end;

procedure TfrmMain.btnOpenSourceClick(Sender: TObject);
begin
  if dlgOpen.Execute then
  begin
    memSource.Lines.LoadFromFile(dlgOpen.FileName);
    lblSourceFile.Caption := 'file: ' + ExtractFileName(dlgOpen.FileName);
    Reformat;
  end;
end;

procedure TfrmMain.btnSaveSettingsClick(Sender: TObject);
begin
  if dlgSaveIni.Execute then
    SaveOptionsToIni(FOpts, dlgSaveIni.FileName);
end;

procedure TfrmMain.btnLoadSettingsClick(Sender: TObject);
begin
  if dlgOpen.Execute then
  begin
    FOpts := LoadOptionsFromIni(dlgOpen.FileName);
    OptionsToControls;
    AutoSave;        // current state mirrors the shared ini (autosave model)
    Reformat;
  end;
end;

procedure TfrmMain.btnResetClick(Sender: TObject);
begin
  if MessageDlg('Reset all settings to defaults? This overwrites the shared yadf.ini.',
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FOpts := DefaultOptions;
  OptionsToControls;
  AutoSave;
  Reformat;
end;

procedure TfrmMain.btnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := memResult.Text;
end;

procedure TfrmMain.LoadSample;
var
  P: string;
begin
  P := ExtractFilePath(Application.ExeName) + 'Sample.pas';
  if not FileExists(P) then
    P := ExtractFilePath(Application.ExeName) + 'Demo\Sample.pas';
  if not FileExists(P) then
    P := ExtractFilePath(Application.ExeName) + '..\..\..\Demo\Sample.pas';
  if FileExists(P) then
  begin
    memSource.Lines.LoadFromFile(P);
    lblSourceFile.Caption := 'file: Sample.pas';
  end
  else
    lblSourceFile.Caption := 'file: (paste or open a .pas)';
end;

end.
