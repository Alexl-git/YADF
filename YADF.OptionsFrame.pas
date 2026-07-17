{
  YADF.OptionsFrame -- the ONE shared options-editing surface.

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  One TFrame hosts the complete YADF settings UI -- the Profiles panel
  (%APPDATA%\YADF\*.ini list, [F]/[R] badges, assign/unassign/new), the option
  grid code-built from YADF.Options.OptionTable, and the live Source | Result
  preview -- and is compiled into BOTH shipping hosts: YADFSetup.exe (hosted on
  the main form) and YADFOT.bpl (registered as the Tools > Options > Third
  Party > YADF page). Before this unit the two hosts carried ~350 copy-pasted
  and slowly diverging lines each; now the only per-host difference is the
  TYadfOptionsPersistPolicy record the host assigns after Create.

  Persistence semantics by policy:
  - YADFSetup (SetupPersistPolicy): AutoSave -- every option change writes the
    edited profile INI immediately; there is no OK/Cancel.
  - IDE page (IdePersistPolicy): option VALUES are written only when the host
    calls Commit (the dialog's OK); Commit also mirrors the F profile onto the
    standard yadf.ini so the F shortcut / CLI default stay in sync even when F
    points at a custom-named file.
  Profile ACTIONS (assign F/R, unassign, new profile, switch which profile is
  edited) save immediately under EITHER policy -- they always did on both
  surfaces; switching profiles flushes the currently edited values first so no
  edits are silently discarded.
}

unit YADF.OptionsFrame;

interface

uses
  Winapi.Windows,
  System.SysUtils, System.Classes, System.Variants, System.IOUtils,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  Vcl.Samples.Spin, Vcl.Clipbrd,
  YADF.Options, YADF.Layout;

type
  /// <summary>Per-host persistence behavior of TYadfOptionsFrame. Assign one
  /// of the ready-made SetupPersistPolicy / IdePersistPolicy constants to the
  /// frame's Policy property right after Create (default: both False -- the
  /// frame is inert until told otherwise).</summary>
  /// <remarks>AutoSave: write the edited profile INI on every option change
  /// (YADFSetup model; no OK/Cancel). MirrorFOnCommit: when Commit writes the
  /// F profile, also copy it onto the standard %APPDATA%\YADF\yadf.ini
  /// (IDE-page model, where values persist only on OK).</remarks>
  TYadfOptionsPersistPolicy = record
    AutoSave       : Boolean;
    MirrorFOnCommit: Boolean;
  end;

  /// <summary>Fired whenever the frame loads, saves, or switches the edited
  /// INI, with a ready-to-display line such as 'INI: C:\...\yadf.ini  (saved)'.
  /// Hosts with a status label (YADFSetup) subscribe; others ignore it.</summary>
  TYadfIniStatusEvent = procedure(const AText: string) of object;

  /// <summary>The shared YADF settings frame: Profiles panel + option grid +
  /// live before/after preview. Controls are code-built by iterating
  /// YADF.Options.OptionTable (adding a field to TYadfOptions/OptionTable makes
  /// it appear in every host automatically); the .dfm resource is a bare
  /// streamable root only -- required because TCustomFrame.Create streams a
  /// per-class resource and raises EResNotFound when none exists.</summary>
  /// <remarks>Not thread-safe; both hosts drive it on the main VCL thread.
  /// FControls is index-aligned to OptionTable; FProfileFiles to the profile
  /// list rows. Call sequence for hosts: Create -> Policy := ... ->
  /// [OnIniStatus := ...] -> Load. IDE host additionally calls Commit on OK.
  /// The preview is LIVE (debounced); reformat is skipped for options whose
  /// TOptInfo.AffectsPreview is False (their output would be identical).</remarks>
  TYadfOptionsFrame = class(TFrame)
  private
    FOpts       : TYadfOptions;
    FPolicy     : TYadfOptionsPersistPolicy;
    FOnIniStatus: TYadfIniStatusEvent;
    FScroll     : TScrollBox;
    FControls   : array of TControl;  // index-aligned to OptionTable
    FUpdating   : Boolean;            // True while pushing FOpts -> controls;
                                      // suppresses OptionChanged so programmatic
                                      // writes don't clobber FOpts mid-loop
    // --- profiles panel ---
    FProfiles    : TYadfProfiles;     // current F/R mapping from profiles.ini
    FProfileFiles: TArray<string>;    // file names, index-aligned to list rows
    FCurrentIni  : string;            // full path of the profile being edited
    FProfileList : TListBox;          // the profiles list control
    FEditingLbl  : TLabel;            // 'Editing: <file>'
    // --- live before/after preview ---
    FSource     : TMemo;              // editable sample source (input)
    FResult     : TMemo;              // formatted output (read-only)
    FSourceName : TLabel;             // 'file: <name>' for the loaded sample
    FResultStat : TLabel;             // 'OK' / 'error'
    FOpenDlg    : TOpenDialog;        // load-your-own-.pas dialog
    FReformatTmr: TTimer;             // debounce reformat on rapid changes
    procedure BuildProfilePanel(AHost: TWinControl);
    procedure BuildControls;
    procedure BuildPreview;
    procedure OptionsToControls;
    procedure ControlsToOptions;
    procedure RefreshProfileList;
    procedure SwitchEditTo(const AIniFile: string);
    procedure Reformat;
    procedure LoadSample;
    procedure SaveCurrentProfile;
    procedure DoIniStatus(const ASuffix: string);
    procedure AssignShortcut(AWhich: Char);
    procedure UnassignSelected;
    // event handlers
    procedure OptionChanged(Sender: TObject);
    procedure SourceChanged(Sender: TObject);
    procedure ReformatTimer(Sender: TObject);
    procedure OpenSourceClick(Sender: TObject);
    procedure CopyResultClick(Sender: TObject);
    procedure ProfileListClick(Sender: TObject);
    procedure ProfileListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SetFClick(Sender: TObject);
    procedure SetRClick(Sender: TObject);
    procedure UnassignClick(Sender: TObject);
    procedure NewProfileClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Start editing the F profile (the file the F shortcut, the CLI
    /// default and YADFSetup all resolve): read it into FOpts, populate the
    /// controls and the profiles list, load a sample and render the first
    /// preview. Call once, after assigning Policy.</summary>
    procedure Load;
    /// <summary>Persist the edited values on the host's explicit save point
    /// (the IDE dialog's OK). Read-modify-write of the profile CURRENTLY being
    /// edited: re-read the record fresh so any field not surfaced as a control
    /// survives, apply this frame's controls, write it back. When
    /// Policy.MirrorFOnCommit is True and the edited profile IS the F profile,
    /// best-effort copy it onto the standard %APPDATA%\YADF\yadf.ini (skipped
    /// when the edited file already IS yadf.ini; a locked/read-only standard
    /// file does not lose the values written to the profile itself).</summary>
    procedure Commit;
    /// <summary>Read options from an arbitrary INI into the grid (YADFSetup's
    /// "Load Settings"). Under Policy.AutoSave the values are immediately
    /// persisted to the profile being edited.</summary>
    procedure LoadOptionsFromFile(const APath: string);
    /// <summary>Write the grid's current values to an arbitrary INI
    /// (YADFSetup's "Save As..."). Does not change which profile is edited.</summary>
    procedure SaveOptionsToFile(const APath: string);
    /// <summary>Reset the grid to DefaultOptions (YADFSetup's "Reset"; any
    /// confirmation prompt is the host's job). Under Policy.AutoSave the
    /// defaults are immediately persisted to the profile being edited.</summary>
    procedure ResetToDefaults;
    /// <summary>Full path of the profile INI currently being edited.</summary>
    property CurrentIniPath: string read FCurrentIni;
    /// <summary>Persistence behavior; assign right after Create, before Load.</summary>
    property Policy: TYadfOptionsPersistPolicy read FPolicy write FPolicy;
    /// <summary>Optional status-line sink; see TYadfIniStatusEvent.</summary>
    property OnIniStatus: TYadfIniStatusEvent read FOnIniStatus write FOnIniStatus;
  end;

const
  /// <summary>YADFSetup.exe: autosave every change; no yadf.ini mirroring
  /// beyond the profile itself.</summary>
  SetupPersistPolicy: TYadfOptionsPersistPolicy =
    (AutoSave: True; MirrorFOnCommit: False);
  /// <summary>IDE Tools > Options page: values persist only on Commit (OK),
  /// which also mirrors the F profile onto the standard yadf.ini.</summary>
  IdePersistPolicy: TYadfOptionsPersistPolicy =
    (AutoSave: False; MirrorFOnCommit: True);

implementation

{ Minimal .dfm resource: TCustomFrame.Create streams a per-class resource via
  InitInheritedComponent(Self, TFrame) and raises EResNotFound when none
  exists -- frames, unlike forms, have no CreateNew to skip streaming.
  YADF.OptionsFrame.dfm supplies a bare streamable root object
  (Left/Top/Width/Height only); the real controls are code-built below. }
{$R *.dfm}

{ ==================== construction ==================== }

constructor TYadfOptionsFrame.Create(AOwner: TComponent);
var
  Splitter: TSplitter;
  LeftHost: TPanel;
begin
  inherited Create(AOwner);
  Width := 900;
  Height:= 520;

  // Debounce timer: coalesces a burst of control changes into one reformat.
  FReformatTmr:= TTimer.Create(Self);
  FReformatTmr.Enabled := False;
  FReformatTmr.Interval:= 200;
  FReformatTmr.OnTimer := ReformatTimer;

  // The LEFT region is a host panel holding the Profiles panel (docked top, so
  // it stays visible) above the scrolling option group-boxes (alClient). A
  // splitter separates it from the Source | Result preview filling the rest.
  LeftHost:= TPanel.Create(Self);
  LeftHost.Parent    := Self;
  LeftHost.Align     := alLeft;
  LeftHost.Width     := 360;
  LeftHost.BevelOuter:= bvNone;

  BuildProfilePanel(LeftHost);   // docks itself alTop within LeftHost

  FScroll:= TScrollBox.Create(Self);
  FScroll.Parent     := LeftHost;
  FScroll.Align      := alClient;   // fills LeftHost below the profiles panel
  FScroll.BorderStyle:= bsNone;

  Splitter:= TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Left   := LeftHost.Left + LeftHost.Width;   // dock right of LeftHost
  Splitter.Align  := alLeft;
  Splitter.Width  := 5;

  BuildControls;
  BuildPreview;
end;

procedure TYadfOptionsFrame.BuildProfilePanel(AHost: TWinControl);
var
  Panel: TPanel;
  Bar  : TPanel;
  Lbl  : TLabel;

  function AddBtn(ALeft: Integer; const ACap: string; AOnClick: TNotifyEvent;
    const AHint: string): TButton;
  begin
    Result:= TButton.Create(Self);
    Result.Parent := Bar;
    Result.Left   := ALeft; Result.Top:= 1; Result.Width:= 62; Result.Height:= 23;
    Result.Caption:= ACap;
    Result.Hint   := AHint; Result.ShowHint:= True;
    Result.OnClick:= AOnClick;
  end;

begin
  // Profiles group docked at the TOP of the left host, above the scrolling
  // options. The list shows every *.ini in %APPDATA%\YADF (except
  // profiles.ini), badged [F]/[R]. Two equivalent ways to act on a row: the
  // button bar, or the keyboard (F / R assigns, Del unassigns). Profile
  // actions save immediately under either policy.
  Panel:= TPanel.Create(Self);
  Panel.Parent    := AHost;
  Panel.Align     := alTop;
  Panel.Height    := 168;
  Panel.BevelOuter:= bvNone;

  Lbl:= TLabel.Create(Self);
  Lbl.Parent := Panel;
  Lbl.Left   := 4; Lbl.Top:= 2;
  Lbl.Caption:= 'Profiles (F = Ctrl+Shift+Alt+F, R = Ctrl+Shift+Alt+R)';

  // Bottom strip: button row + the 'Editing:' line under it.
  Bar:= TPanel.Create(Self);
  Bar.Parent    := Panel;
  Bar.Align     := alBottom;
  Bar.Height    := 44;
  Bar.BevelOuter:= bvNone;
  AddBtn(  2, 'Set F'   , SetFClick      , 'Assign the selected profile to Ctrl+Shift+Alt+F (and the CLI default). Keyboard: F');
  AddBtn( 66, 'Set R'   , SetRClick      , 'Assign the selected profile to Ctrl+Shift+Alt+R. Keyboard: R');
  AddBtn(130, 'Unassign', UnassignClick  , 'Clear the F/R assignment of the selected profile (F resets to yadf.ini). Keyboard: Del');
  AddBtn(194, 'New...'  , NewProfileClick, 'Create a new yadf-<name>.ini seeded with the current settings');

  FEditingLbl:= TLabel.Create(Self);
  FEditingLbl.Parent := Bar;
  FEditingLbl.Left   := 4; FEditingLbl.Top:= 27;
  FEditingLbl.Caption:= 'Editing:';

  // The list fills the space between the label and the bottom strip.
  FProfileList:= TListBox.Create(Self);
  FProfileList.Parent  := Panel;
  FProfileList.Align   := alClient;
  FProfileList.AlignWithMargins:= True;
  FProfileList.Margins.SetBounds(4, 18, 4, 2);
  FProfileList.OnClick  := ProfileListClick;
  FProfileList.OnKeyDown:= ProfileListKeyDown;
end;

procedure TYadfOptionsFrame.BuildControls;
var
  T     : TArray<TOptInfo>;
  i, y  : Integer;
  CurGrp: string;
  gb    : TGroupBox;
  parent: TWinControl;
  yIn   : Integer;
  cb    : TCheckBox;
  se    : TSpinEdit;
  ed    : TEdit;
  cmb   : TComboBox;
  lbl   : TLabel;
begin
  // One TGroupBox per TOptInfo.Group, one control per row keyed by Kind,
  // stored index-aligned in FControls.
  T:= OptionTable;
  SetLength(FControls, Length(T));
  CurGrp:= '';
  gb    := nil;
  parent:= FScroll;
  y     := 4;
  yIn   := 0;
  for i:= 0 to High(T) do
  begin
    if T[i].Group <> CurGrp then
    begin
      CurGrp:= T[i].Group;
      gb:= TGroupBox.Create(Self);
      gb.Parent := FScroll;
      gb.Left   := 4;
      gb.Top    := y;
      gb.Width  := FScroll.ClientWidth - 28;
      gb.Anchors:= [akLeft, akTop, akRight];
      gb.Caption:= CurGrp;
      parent:= gb;
      yIn   := 18;
    end;
    case T[i].Kind of
      okBool:
        begin
          cb:= TCheckBox.Create(Self);
          cb.Parent := parent;
          cb.Left   := 10; cb.Top:= yIn; cb.Width:= gb.Width - 20;
          cb.Caption:= T[i].Caption;
          cb.Hint   := T[i].Hint; cb.ShowHint:= True;
          cb.Tag    := i;
          cb.OnClick:= OptionChanged;
          FControls[i]:= cb;
          Inc(yIn, 24);
        end;
      okInt:
        begin
          lbl:= TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left:= 10; lbl.Top:= yIn + 3;
          lbl.Caption:= T[i].Caption;
          se:= TSpinEdit.Create(Self);
          se.Parent := parent; se.Left:= 240; se.Top:= yIn; se.Width:= 80;
          se.MinValue:= 0; se.MaxValue:= 100000;
          se.Hint   := T[i].Hint; se.ShowHint:= True;
          se.Tag    := i;
          se.OnChange:= OptionChanged;
          FControls[i]:= se;
          Inc(yIn, 28);
        end;
      okString:
        begin
          lbl:= TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left:= 10; lbl.Top:= yIn + 3;
          lbl.Caption:= T[i].Caption;
          ed:= TEdit.Create(Self);
          ed.Parent := parent; ed.Left:= 240; ed.Top:= yIn; ed.Width:= gb.Width - 250;
          ed.Anchors:= [akLeft, akTop, akRight];
          ed.Hint   := T[i].Hint; ed.ShowHint:= True;
          ed.Tag    := i;
          ed.OnChange:= OptionChanged;
          FControls[i]:= ed;
          Inc(yIn, 28);
        end;
      okEnum:
        begin
          lbl:= TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left:= 10; lbl.Top:= yIn + 3;
          lbl.Caption:= T[i].Caption;
          cmb:= TComboBox.Create(Self);
          cmb.Parent := parent; cmb.Left:= 240; cmb.Top:= yIn; cmb.Width:= 110;
          cmb.Style  := csDropDownList;
          // The only okEnum option today is the output encoding, so the value
          // list is hardcoded HERE and nowhere else. A second okEnum option
          // needs a Values column in TOptInfo instead (tracked in TODO.md).
          cmb.Items.Add('ANSI'); cmb.Items.Add('UTF-8'); cmb.Items.Add('UTF-16');
          cmb.Hint   := T[i].Hint; cmb.ShowHint:= True;
          cmb.Tag    := i;
          cmb.OnChange:= OptionChanged;
          FControls[i]:= cmb;
          Inc(yIn, 28);
        end;
    end;
    if gb <> nil then
    begin
      gb.Height:= yIn + 6;
      y:= gb.Top + gb.Height + 6;
    end;
  end;
end;

procedure TYadfOptionsFrame.BuildPreview;
var
  Host   : TPanel;      // fills the area right of the options splitter
  SrcPane: TPanel;      // left half of the preview: source
  ResPane: TPanel;      // right half of the preview: result
  SrcBar : TPanel;      // top strip of SrcPane: [Load .pas...] + filename
  ResBar : TPanel;      // top strip of ResPane: [Copy] + status label
  Btn    : TButton;
  Split  : TSplitter;
begin
  // Host fills whatever is left of the frame after the options + splitter.
  Host:= TPanel.Create(Self);
  Host.Parent    := Self;
  Host.Align     := alClient;
  Host.BevelOuter:= bvNone;

  // --- Source pane (editable input) on the left half ---
  SrcPane:= TPanel.Create(Self);
  SrcPane.Parent    := Host;
  SrcPane.Align     := alLeft;
  SrcPane.Width     := 260;
  SrcPane.BevelOuter:= bvNone;

  SrcBar:= TPanel.Create(Self);
  SrcBar.Parent    := SrcPane;
  SrcBar.Align     := alTop;
  SrcBar.Height    := 26;
  SrcBar.BevelOuter:= bvNone;

  Btn:= TButton.Create(Self);
  Btn.Parent := SrcBar;
  Btn.Left   := 2; Btn.Top:= 1; Btn.Width:= 90; Btn.Height:= 23;
  Btn.Caption:= 'Load .pas...';
  Btn.Hint   := 'Load your own Pascal file into the preview'; Btn.ShowHint:= True;
  Btn.OnClick:= OpenSourceClick;

  FSourceName:= TLabel.Create(Self);
  FSourceName.Parent  := SrcBar;
  FSourceName.Left    := 98; FSourceName.Top:= 5;
  FSourceName.Caption := 'source';

  FSource:= TMemo.Create(Self);
  FSource.Parent    := SrcPane;
  FSource.Align     := alClient;
  FSource.ScrollBars:= ssBoth;
  FSource.WordWrap  := False;
  FSource.Font.Name := 'Consolas';
  FSource.OnChange  := SourceChanged;

  // Splitter between source and result.
  Split:= TSplitter.Create(Self);
  Split.Parent := Host;
  Split.Left   := SrcPane.Left + SrcPane.Width;
  Split.Align  := alLeft;
  Split.Width  := 5;

  // --- Result pane (read-only output) fills the rest ---
  ResPane:= TPanel.Create(Self);
  ResPane.Parent    := Host;
  ResPane.Align     := alClient;
  ResPane.BevelOuter:= bvNone;

  ResBar:= TPanel.Create(Self);
  ResBar.Parent    := ResPane;
  ResBar.Align     := alTop;
  ResBar.Height    := 26;
  ResBar.BevelOuter:= bvNone;

  Btn:= TButton.Create(Self);
  Btn.Parent := ResBar;
  Btn.Left   := 2; Btn.Top:= 1; Btn.Width:= 60; Btn.Height:= 23;
  Btn.Caption:= 'Copy';
  Btn.Hint   := 'Copy the formatted result to the clipboard'; Btn.ShowHint:= True;
  Btn.OnClick:= CopyResultClick;

  FResultStat:= TLabel.Create(Self);
  FResultStat.Parent  := ResBar;
  FResultStat.Left    := 70; FResultStat.Top:= 5;
  FResultStat.Caption := 'result';

  FResult:= TMemo.Create(Self);
  FResult.Parent    := ResPane;
  FResult.Align     := alClient;
  FResult.ScrollBars:= ssBoth;
  FResult.WordWrap  := False;
  FResult.ReadOnly  := True;
  FResult.Font.Name := 'Consolas';

  // Load-your-own-file dialog.
  FOpenDlg:= TOpenDialog.Create(Self);
  FOpenDlg.Filter := 'Pascal files (*.pas;*.dpr;*.inc)|*.pas;*.dpr;*.inc|All files (*.*)|*.*';
  FOpenDlg.Options:= FOpenDlg.Options + [ofFileMustExist];
end;

{ ==================== grid <-> record ==================== }

procedure TYadfOptionsFrame.OptionsToControls;
var
  T: TArray<TOptInfo>;
  i: Integer;
  v: Variant;
begin
  // Setting Checked/Value/Text/ItemIndex fires the control's OnClick/OnChange,
  // i.e. OptionChanged. Suppress it: otherwise each programmatic write would
  // read back the not-yet-updated controls and clobber FOpts mid-loop (which
  // broke Reset and left spin edits stuck at 0 in early YADFSetup builds).
  T:= OptionTable;
  FUpdating:= True;
  try
    for i:= 0 to High(T) do
    begin
      v:= T[i].GetVal(FOpts);
      case T[i].Kind of
        okBool  : TCheckBox(FControls[i]).Checked:= v;
        okInt   : TSpinEdit(FControls[i]).Value  := v;
        okString: TEdit(FControls[i]).Text       := VarToStr(v);
        okEnum  : TComboBox(FControls[i]).ItemIndex:=
                    TComboBox(FControls[i]).Items.IndexOf(VarToStr(v));
      end;
    end;
  finally
    FUpdating:= False;
  end;
end;

procedure TYadfOptionsFrame.ControlsToOptions;
var
  T: TArray<TOptInfo>;
  i: Integer;
begin
  T:= OptionTable;
  for i:= 0 to High(T) do
    case T[i].Kind of
      okBool  : T[i].SetVal(FOpts, TCheckBox(FControls[i]).Checked);
      okInt   : T[i].SetVal(FOpts, TSpinEdit(FControls[i]).Value);
      okString: T[i].SetVal(FOpts, TEdit(FControls[i]).Text);
      okEnum  : T[i].SetVal(FOpts, TComboBox(FControls[i]).Text);
    end;
end;

{ ==================== persistence ==================== }

procedure TYadfOptionsFrame.DoIniStatus(const ASuffix: string);
begin
  if Assigned(FOnIniStatus) then
    FOnIniStatus('INI: ' + FCurrentIni + ASuffix);
end;

procedure TYadfOptionsFrame.SaveCurrentProfile;
begin
  // AutoSave write of the edited profile. A failed write (locked/read-only
  // file) must not raise into a VCL event handler; report it via the status
  // line instead.
  try
    SaveOptionsToIni(FOpts, FCurrentIni);
    DoIniStatus('  (saved)');
  except
    on E: Exception do
      DoIniStatus('  (save failed: ' + E.Message + ')');
  end;
end;

procedure TYadfOptionsFrame.OptionChanged(Sender: TObject);
var
  T  : TArray<TOptInfo>;
  idx: Integer;
begin
  // A control changed. Ignore programmatic population (OptionsToControls sets
  // FUpdating), otherwise each of ~40 writes would pull+reformat. Pull the
  // live control values into FOpts, persist if the policy autosaves, and
  // refresh the preview (debounced) -- unless the changed option cannot alter
  // the preview (AffectsPreview=False -> output would be byte-identical).
  if FUpdating then Exit;
  ControlsToOptions;
  if FPolicy.AutoSave then SaveCurrentProfile;
  T  := OptionTable;
  idx:= TControl(Sender).Tag;
  if (idx >= 0) and (idx <= High(T)) and not T[idx].AffectsPreview then Exit;
  FReformatTmr.Enabled:= False;   // debounce
  FReformatTmr.Enabled:= True;
end;

procedure TYadfOptionsFrame.Commit;
var
  Shared: string;
begin
  // Read-modify-write the profile CURRENTLY being edited: re-read the record
  // fresh so any field NOT surfaced as a control survives, apply this frame's
  // controls, and write it back through the shared OptionTable serializer
  // (comments in the template are preserved).
  FOpts:= LoadOptionsFromIni(FCurrentIni);
  ControlsToOptions;
  SaveOptionsToIni(FOpts, FCurrentIni);
  DoIniStatus('  (saved)');

  // Mirror onto the standard %APPDATA%\YADF\yadf.ini ONLY when the policy asks
  // for it AND the profile being edited IS the F profile, so the F shortcut /
  // CLI default (which read the standard file) reflect these values even if F
  // points at a custom-named file. When editing R (or any non-F profile), do
  // NOT mirror -- that would clobber the F/standard file with R's values.
  // Skip when the edited file already IS the standard file (copying a file
  // onto itself raises). Best-effort: a copy failure must not lose the values
  // already written to FCurrentIni.
  if not FPolicy.MirrorFOnCommit then Exit;
  if not SameFileName(TPath.GetFullPath(FCurrentIni),
                      TPath.GetFullPath(ResolveProfileIniPath(FProfiles.F))) then
    Exit;   // editing a non-F profile -> nothing to mirror
  Shared:= SharedAppDataIniPath;
  if not SameFileName(TPath.GetFullPath(FCurrentIni), TPath.GetFullPath(Shared)) then
    try
      TFile.Copy(FCurrentIni, Shared, True);
    except
      // A read-only or locked standard file is non-fatal: the F profile itself
      // is saved (FCurrentIni), so the next open and any profile-F consumer
      // still read the correct values.
    end;
end;

procedure TYadfOptionsFrame.LoadOptionsFromFile(const APath: string);
begin
  FOpts:= LoadOptionsFromIni(APath);
  OptionsToControls;
  if FPolicy.AutoSave then SaveCurrentProfile;
  Reformat;
end;

procedure TYadfOptionsFrame.SaveOptionsToFile(const APath: string);
begin
  ControlsToOptions;
  SaveOptionsToIni(FOpts, APath);
end;

procedure TYadfOptionsFrame.ResetToDefaults;
begin
  FOpts:= DefaultOptions;
  OptionsToControls;
  if FPolicy.AutoSave then SaveCurrentProfile;
  Reformat;
end;

{ ==================== profiles panel ==================== }

// Returns the file name of the selected profile row, or '' if none is selected.
function SelectedProfile(AList: TListBox; const AFiles: TArray<string>): string;
var
  i: Integer;
begin
  Result:= '';
  i:= AList.ItemIndex;
  if (i >= 0) and (i <= High(AFiles)) then Result:= AFiles[i];
end;

procedure TYadfOptionsFrame.RefreshProfileList;
var
  Files     : TArray<string>;
  Dir, Name : string;
  Badge, Cur: string;
  i, Sel    : Integer;
begin
  // Enumerate ProfilesDir\*.ini (skip the profiles.ini mapping file), badge
  // the F/R rows, rebuild the index-aligned FProfileFiles, and re-select the
  // row matching the profile now being edited.
  Dir:= ProfilesDir;
  if not DirectoryExists(Dir) then ForceDirectories(Dir);
  Files:= TDirectory.GetFiles(Dir, '*.ini', TSearchOption.soTopDirectoryOnly);
  SetLength(FProfileFiles, 0);
  Cur:= ExtractFileName(FCurrentIni);
  Sel:= -1;
  FProfileList.Items.BeginUpdate;
  try
    FProfileList.Items.Clear;
    for i:= 0 to High(Files) do
    begin
      Name:= ExtractFileName(Files[i]);
      if SameText(Name, 'profiles.ini') then Continue;   // mapping file, not a profile
      if      SameText(Name, FProfiles.F) then Badge:= '[F]  '
      else if SameText(Name, FProfiles.R) then Badge:= '[R]  '
      else                                      Badge:= '      ';
      FProfileList.Items.Add(Badge + Name);
      SetLength(FProfileFiles, Length(FProfileFiles) + 1);
      FProfileFiles[High(FProfileFiles)]:= Name;
      if SameText(Name, Cur) then Sel:= High(FProfileFiles);
    end;
  finally
    FProfileList.Items.EndUpdate;
  end;
  if Sel >= 0 then FProfileList.ItemIndex:= Sel;
  FEditingLbl.Caption:= 'Editing: ' + Cur;
end;

procedure TYadfOptionsFrame.SwitchEditTo(const AIniFile: string);
var
  Path: string;
begin
  // Switch which profile the option controls edit. FLUSH the current profile's
  // values first so clicking another row never silently discards edits: under
  // AutoSave this rewrites the bytes already on disk (harmless); under the
  // OK-commit policy it is the documented profile-actions-are-live semantic.
  Path:= ResolveProfileIniPath(AIniFile);
  if (Path = '') or SameFileName(Path, FCurrentIni) then Exit;
  ControlsToOptions;
  SaveOptionsToIni(FOpts, FCurrentIni);   // flush current profile before leaving
  FCurrentIni:= Path;
  EnsureIniExists(FCurrentIni);
  FOpts:= LoadOptionsFromIni(FCurrentIni);
  OptionsToControls;
  FEditingLbl.Caption:= 'Editing: ' + ExtractFileName(FCurrentIni);
  DoIniStatus('');
  Reformat;
end;

procedure TYadfOptionsFrame.ProfileListClick(Sender: TObject);
var
  Name: string;
begin
  // Single-click a row -> edit THAT profile (SwitchEditTo flushes the current
  // one first). No-op when the row is already the one being edited.
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name <> '' then SwitchEditTo(Name);
end;

procedure TYadfOptionsFrame.AssignShortcut(AWhich: Char);
var
  Name: string;
begin
  // Assign the selected profile to F or R. Saved immediately; under the IDE's
  // OK-commit policy the dialog OK/Cancel governs only the option VALUES, not
  // the F/R mapping (documented in the page remarks).
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name = '' then Exit;
  if AWhich = 'F' then FProfiles.F:= Name
  else                 FProfiles.R:= Name;
  SaveProfiles(FProfiles);
  RefreshProfileList;
end;

procedure TYadfOptionsFrame.UnassignSelected;
var
  Name: string;
begin
  // Clear the selected profile's F/R assignment. F must always resolve to a
  // file (the CLI + shortcut need one), so unassigning F resets it to the
  // default 'yadf.ini' rather than leaving it blank; R may be cleared outright.
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name = '' then Exit;
  if      SameText(FProfiles.R, Name) then FProfiles.R:= ''
  else if SameText(FProfiles.F, Name) then FProfiles.F:= 'yadf.ini';
  SaveProfiles(FProfiles);
  RefreshProfileList;
end;

procedure TYadfOptionsFrame.SetFClick(Sender: TObject);
begin
  AssignShortcut('F');
end;

procedure TYadfOptionsFrame.SetRClick(Sender: TObject);
begin
  AssignShortcut('R');
end;

procedure TYadfOptionsFrame.UnassignClick(Sender: TObject);
begin
  UnassignSelected;
end;

procedure TYadfOptionsFrame.ProfileListKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  // Keyboard mirror of the button bar: highlight a row, press F / R to assign
  // the shortcut, Del to unassign.
  case Key of
    Ord('F') : begin AssignShortcut('F'); Key:= 0; end;
    Ord('R') : begin AssignShortcut('R'); Key:= 0; end;
    VK_DELETE: begin UnassignSelected;    Key:= 0; end;
  end;
end;

procedure TYadfOptionsFrame.NewProfileClick(Sender: TObject);
var
  Nm, FileName, Path: string;
  k: Integer;
begin
  // Create a new yadf-<name>.ini seeded with the CURRENT settings, then switch
  // to editing it. Sanitise the name so it is a legal single-segment file name.
  Nm:= '';
  if not InputQuery('New profile', 'Profile name (creates yadf-<name>.ini):', Nm) then Exit;
  Nm:= Trim(Nm);
  if Nm = '' then Exit;
  for k:= 1 to Length(Nm) do
    if CharInSet(Nm[k], ['\', '/', ':', '*', '?', '"', '<', '>', '|', ' ']) then Nm[k]:= '-';
  FileName:= 'yadf-' + Nm + '.ini';
  Path:= ResolveProfileIniPath(FileName);
  if FileExists(Path) then
  begin
    if MessageDlg(FileName + ' already exists. Edit it instead?',
         mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  end
  else
  begin
    ControlsToOptions;
    SaveOptionsToIni(FOpts, Path);   // seed the new profile with current settings
  end;
  SwitchEditTo(FileName);
  RefreshProfileList;
end;

{ ==================== preview ==================== }

procedure TYadfOptionsFrame.Reformat;
begin
  // Render the result memo from the current source + FOpts. A malformed paste
  // can raise inside FormatSource (DelphiAST lexer/parser); show it in the
  // result memo rather than letting it escape into the host dialog.
  if FResult = nil then Exit;
  try
    FResult.Text:= FormatSource(FSource.Text, FOpts);
    FResultStat.Caption:= 'OK';
  except
    on E: Exception do
    begin
      FResult.Text:= '[Format error] ' + E.ClassName + ': ' + E.Message;
      FResultStat.Caption:= 'error';
    end;
  end;
end;

procedure TYadfOptionsFrame.SourceChanged(Sender: TObject);
begin
  FReformatTmr.Enabled:= False;   // debounce
  FReformatTmr.Enabled:= True;
end;

procedure TYadfOptionsFrame.ReformatTimer(Sender: TObject);
begin
  FReformatTmr.Enabled:= False;
  Reformat;
end;

procedure TYadfOptionsFrame.OpenSourceClick(Sender: TObject);
begin
  if FOpenDlg.Execute then
  begin
    FSource.Lines.LoadFromFile(FOpenDlg.FileName);
    FSourceName.Caption:= 'file: ' + ExtractFileName(FOpenDlg.FileName);
    Reformat;
  end;
end;

procedure TYadfOptionsFrame.CopyResultClick(Sender: TObject);
begin
  Clipboard.AsText:= FResult.Text;
end;

procedure TYadfOptionsFrame.LoadSample;
const
  // Built-in fallback so the preview always shows something even when no
  // Sample.pas is found next to the host module. Deliberately "ugly" so the
  // formatter has visible work to do.
  FALLBACK =
    'unit Sample;'#13#10 +
    'interface'#13#10 +
    'type TFoo=record A:Integer;B:string; end;'#13#10 +
    'const K=1;LongName=2;'#13#10 +
    'procedure Go(X:Integer);'#13#10 +
    'implementation'#13#10 +
    'procedure Go(X:Integer);begin if X>0 then Inc(X) else Dec(X); end;'#13#10 +
    'end.'#13#10;
var
  Base: string;
  Cand: TArray<string>;
  i   : Integer;
begin
  // Try a bundled Demo\Sample.pas relative to a few plausible roots -- the
  // host module's dir (YADFSetup.exe or YADFOT.bpl) and its build-tree
  // parents. If none is present, fall back to the built-in snippet above.
  Base:= ExtractFilePath(GetModuleName(HInstance));
  Cand:= [
    Base + 'Sample.pas',
    Base + 'Demo\Sample.pas',
    Base + '..\..\..\Demo\Sample.pas'
  ];
  for i:= 0 to High(Cand) do
    if TFile.Exists(Cand[i]) then
    begin
      FSource.Lines.LoadFromFile(Cand[i]);
      FSourceName.Caption:= 'file: ' + ExtractFileName(Cand[i]);
      Exit;
    end;
  FSource.Text:= FALLBACK;
  FSourceName.Caption:= 'sample (built-in)';
end;

{ ==================== lifecycle ==================== }

procedure TYadfOptionsFrame.Load;
begin
  // Start editing the F profile (the file YADFSetup + the F shortcut + the CLI
  // default all resolve). Then populate the profiles list so the user can see
  // F/R and switch to any other profile.
  FProfiles  := LoadProfiles;
  FCurrentIni:= ResolveProfileIniPath(FProfiles.F);
  if FCurrentIni = '' then FCurrentIni:= SharedAppDataIniPath;
  EnsureIniExists(FCurrentIni);
  FOpts:= LoadOptionsFromIni(FCurrentIni);
  OptionsToControls;    // FUpdating guards the ~40 OnChange fires here
  RefreshProfileList;   // list all profiles, badge F/R, select the current one
  LoadSample;           // populate the source memo
  Reformat;             // render the first before/after view
  DoIniStatus('');
end;

end.
