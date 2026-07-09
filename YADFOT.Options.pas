{
  YADFOT.Options -- Tools > Options > Third Party > YADF page for YADFOT.

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  A native IDE Options page with FULL YADFSetup parity: it manages the per-user
  formatting profiles (%APPDATA%\YADF\profiles.ini) AND edits their option
  values through the SAME YADF.Options descriptor table (OptionTable) as
  YADFSetup.exe and the CLI, so all four surfaces converge with no duplicated
  schema. A Profiles panel lists every %APPDATA%\YADF\*.ini, badges the F/R
  ones, and lets you switch which profile you edit, assign F/R, unassign, or
  create a new profile -- exactly like YADFSetup's Profiles list, and using the
  same shared primitives (LoadProfiles/SaveProfiles/ResolveProfileIniPath/...).
  The page opens on the F profile. The option controls are built by iterating
  OptionTable -- adding a field to TYadfOptions/OptionTable makes it appear here
  automatically.

  Teardown: RegisterYADFOptions runs from YADFOT.Wizard.Register on package
  load; UnregisterYADFOptions runs from the wizard's Destroyed method (the
  primary hook, before the BPL code segment is dropped) AND from this unit's
  finalization (secondary net). Both are idempotent.
}

unit YADFOT.Options;

interface

/// <summary>Register the "Third Party > YADF" page with the IDE's environment
/// options service. Called from YADFOT.Wizard.Register on package load.
/// Idempotent-safe: re-registering after an unregister re-adds the page.</summary>
procedure RegisterYADFOptions;

/// <summary>Unregister the YADF options page(s). Called from the wizard's
/// Destroyed method (primary) and this unit's finalization (secondary).
/// Idempotent: guarded on an empty ref array, and clears the array after,
/// so a second call is a safe no-op.</summary>
procedure UnregisterYADFOptions;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Variants
  , System.IOUtils
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Dialogs
  , Vcl.Samples.Spin
  , ToolsAPI
  , YADF.Options
  , YADF.Layout
  ;

{ Minimal .dfm resource for TYadfOptionsFrame. TCustomFrame.Create streams a
  per-class resource via InitInheritedComponent(Self, TFrame) and raises
  EResNotFound ("TYadfOptionsFrame not found") when none exists -- frames,
  unlike forms, have no CreateNew to skip streaming. YADFOT.Options.dfm supplies
  a bare streamable root object (Left/Top/Width/Height only); the real controls
  are still code-built in BuildControls. }
{$R *.dfm}

type
  /// <summary>The generic Tools > Options frame. Controls are code-built by
  /// iterating YADF.Options.OptionTable, grouped by TOptInfo.Group into
  /// TGroupBoxes inside a scrolling host -- the same layout YADFSetup uses.
  /// A Profiles panel atop the options (full YADFSetup parity) lists every
  /// %APPDATA%\YADF\*.ini profile, badges the F/R ones, and lets you switch
  /// which profile you edit, assign F/R, unassign, or create a new profile.
  /// Load starts on the F profile; Save writes whichever profile is currently
  /// selected (FCurrentIni), read-modify-write so unrelated fields survive.
  /// A Source | Result preview pair to the right of the options re-runs
  /// FormatSource live as you toggle a control or edit the source, so you can
  /// see the effect of each option (and load your own .pas to preview).</summary>
  /// <remarks>Not thread-safe; the IDE drives Load/Save on the main thread.
  /// FControls is index-aligned to OptionTable; FProfileFiles to the list rows.
  /// The preview is LIVE, and PROFILE actions (assign F/R, unassign, new,
  /// switch) save immediately like YADFSetup -- but the edited profile's option
  /// VALUES are written only on OK (DialogClosed(Accepted)); switching profiles
  /// auto-saves the current one first so no edits are lost.</remarks>
  TYadfOptionsFrame = class(TFrame)
  private
    FOpts    : TYadfOptions;
    FScroll  : TScrollBox;
    FControls: array of TControl;   // index-aligned to OptionTable
    FUpdating: Boolean;             // True while pushing FOpts -> controls
    // --- profiles panel (mirrors YADFSetup's Profiles list) ---
    FProfiles    : TYadfProfiles;      // current F/R mapping from profiles.ini
    FProfileFiles: TArray<string>;     // file names, index-aligned to list rows
    FCurrentIni  : string;             // full path of the profile being edited
    FProfileList : TListBox;           // the profiles list control
    // --- live before/after preview (mirrors YADFSetup's Source|Result) ---
    FSource     : TMemo;            // editable sample source (input)
    FResult     : TMemo;            // formatted output (read-only)
    FSourceName : TLabel;          // "file: <name>" for the loaded sample
    FResultStat : TLabel;          // "OK" / "error"
    FOpenDlg    : TOpenDialog;      // load-your-own-.pas dialog
    FReformatTmr: TTimer;          // debounce reformat on rapid changes
    procedure BuildProfilePanel(AHost: TWinControl);
    procedure BuildControls;
    procedure BuildPreview;
    procedure OptionsToControls;
    procedure ControlsToOptions;
    procedure RefreshProfileList;
    procedure SwitchEditTo(const AIniFile: string);
    procedure Reformat;
    procedure LoadSample;
    // event handlers
    procedure OptionChanged(Sender: TObject);
    procedure SourceChanged(Sender: TObject);
    procedure ReformatTimer(Sender: TObject);
    procedure OpenSourceClick(Sender: TObject);
    procedure ProfileListClick(Sender: TObject);
    procedure SetFClick(Sender: TObject);
    procedure SetRClick(Sender: TObject);
    procedure UnassignClick(Sender: TObject);
    procedure NewProfileClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Read the shared yadf.ini into FOpts, populate the controls, load
    /// a sample into the source memo, and render the first preview.</summary>
    procedure Load;
    /// <summary>Re-read the record fresh, apply this frame's controls, write it
    /// back to the profile CURRENTLY being edited (FCurrentIni). When that
    /// profile is the F profile, also mirror it onto the standard
    /// %APPDATA%\YADF\yadf.ini so the F shortcut / CLI default reflect the
    /// values even if F is a custom-named file; when editing R (or any non-F
    /// profile) the mirror is skipped so it cannot clobber the F file. The
    /// mirror is also skipped when the edited file already IS yadf.ini, and is
    /// best-effort (a locked/read-only standard file does not lose the values).
    /// </summary>
    procedure Save;
  end;

  TYadfOptionsFrameClass = class of TYadfOptionsFrame;

  /// <summary>INTAAddInOptions page carrying one YADF frame class. GetArea
  /// returns '' so the page lands under the "Third Party" branch; a dotted
  /// caption would nest sub-pages under a 'YADF' node. One instance per page;
  /// parameterized (ACaption, AFrameClass) so a later N-page split is a
  /// one-line change.</summary>
  TYadfOptionsPage = class(TInterfacedObject, INTAAddInOptions)
  private
    FCaption   : string;
    FFrameClass: TCustomFrameClass;
    FFrame     : TYadfOptionsFrame;
  public
    constructor Create(const ACaption: string; AFrameClass: TCustomFrameClass);
    { INTAAddInOptions }
    function  GetArea         : string;
    function  GetCaption      : string;
    function  GetFrameClass   : TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function  ValidateContents   : Boolean;
    function  GetHelpContext     : Integer;
    function  IncludeInIDEInsight: Boolean;
  end;

{ ==================== TYadfOptionsFrame ==================== }

constructor TYadfOptionsFrame.Create(AOwner: TComponent);
var
  Splitter : TSplitter;
  LeftHost : TPanel;
begin
  inherited Create(AOwner);
  Width := 900;
  Height:= 520;

  // Debounce timer: coalesces a burst of control changes into one reformat.
  FReformatTmr:= TTimer.Create(Self);
  FReformatTmr.Enabled := False;
  FReformatTmr.Interval:= 200;
  FReformatTmr.OnTimer := ReformatTimer;

  // The LEFT region is a host panel holding the Profiles panel (docked top, so it
  // stays visible) above the scrolling option group-boxes (alClient). A splitter
  // separates it from the Source | Result preview that fills the rest -- same
  // left-to-right order as YADFSetup (Profiles + Settings | Source | Result).
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
  // options -- mirrors YADFSetup's Profiles list. The list shows every *.ini in
  // %APPDATA%\YADF (except profiles.ini), badged [F]/[R]; the button row assigns
  // F/R, unassigns, or creates a new profile. Actions save immediately (like
  // YADFSetup), independent of the dialog's OK/Cancel.
  Panel:= TPanel.Create(Self);
  Panel.Parent    := AHost;
  Panel.Align     := alTop;
  Panel.Height    := 150;
  Panel.BevelOuter:= bvNone;

  Lbl:= TLabel.Create(Self);
  Lbl.Parent := Panel;
  Lbl.Left   := 4; Lbl.Top:= 2;
  Lbl.Caption:= 'Profiles (F = Ctrl+Shift+Alt+F, R = Ctrl+Shift+Alt+R)';

  // Button row at the bottom of the panel.
  Bar:= TPanel.Create(Self);
  Bar.Parent    := Panel;
  Bar.Align     := alBottom;
  Bar.Height    := 26;
  Bar.BevelOuter:= bvNone;
  AddBtn(  2, 'Set F'   , SetFClick     , 'Assign the selected profile to Ctrl+Shift+Alt+F (and the CLI default)');
  AddBtn( 66, 'Set R'   , SetRClick     , 'Assign the selected profile to Ctrl+Shift+Alt+R');
  AddBtn(130, 'Unassign', UnassignClick , 'Clear the F/R assignment of the selected profile (F resets to yadf.ini)');
  AddBtn(194, 'New...'  , NewProfileClick, 'Create a new yadf-<name>.ini seeded with the current settings');

  // The list fills the space between the label and the button row.
  FProfileList:= TListBox.Create(Self);
  FProfileList.Parent  := Panel;
  FProfileList.Align   := alClient;
  FProfileList.AlignWithMargins:= True;
  FProfileList.Margins.SetBounds(4, 18, 4, 2);
  FProfileList.OnClick := ProfileListClick;
end;

procedure TYadfOptionsFrame.RefreshProfileList;
var
  Files     : TArray<string>;
  Dir, Name : string;
  Badge, Cur: string;
  i, Sel    : Integer;
begin
  // Ports YADFSetup.RefreshProfileList: enumerate ProfilesDir\*.ini (skip the
  // profiles.ini mapping file), badge the F/R rows, rebuild the index-aligned
  // FProfileFiles, and re-select the row matching the profile now being edited.
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
end;

procedure TYadfOptionsFrame.SwitchEditTo(const AIniFile: string);
var
  Path: string;
begin
  // Switch which profile the option controls edit. AUTO-SAVE the current
  // profile's values first (profile actions are live on this page), so clicking
  // another row never silently discards edits. Then load the target into the
  // controls and refresh the preview.
  Path:= ResolveProfileIniPath(AIniFile);
  if (Path = '') or SameFileName(Path, FCurrentIni) then Exit;
  ControlsToOptions;
  SaveOptionsToIni(FOpts, FCurrentIni);   // flush current profile before leaving
  FCurrentIni:= Path;
  EnsureIniExists(FCurrentIni);
  FOpts:= LoadOptionsFromIni(FCurrentIni);
  OptionsToControls;
  Reformat;
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
  // Adapts YADFSetup.BuildOptionControls: one TGroupBox per TOptInfo.Group,
  // one control per row keyed by Kind, stored index-aligned in FControls.
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
  ResBar : TPanel;      // top strip of ResPane: status label
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

  FResultStat:= TLabel.Create(Self);
  FResultStat.Parent  := ResBar;
  FResultStat.Left    := 2; FResultStat.Top:= 5;
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

procedure TYadfOptionsFrame.OptionsToControls;
var
  T: TArray<TOptInfo>;
  i: Integer;
  v: Variant;
begin
  // Programmatic writes fire OnClick/OnChange, but no handlers are wired on
  // this inert page; FUpdating is kept only to match YADFSetup's shape.
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

procedure TYadfOptionsFrame.Reformat;
begin
  // Render the result memo from the current source + FOpts. A malformed paste
  // can raise inside FormatSource (DelphiAST lexer/parser); show it in the
  // result memo rather than letting it escape into the Options dialog.
  if FResult = nil then Exit;
  try
    FResult.Text:= FormatSource(FSource.Text, FOpts);
    FResultStat.Caption:= 'result: OK';
  except
    on E: Exception do
    begin
      FResult.Text:= '[Format error] ' + E.ClassName + ': ' + E.Message;
      FResultStat.Caption:= 'result: error';
    end;
  end;
end;

procedure TYadfOptionsFrame.OptionChanged(Sender: TObject);
begin
  // A control changed. Ignore programmatic population (OptionsToControls sets
  // FUpdating), otherwise each of ~40 writes would pull+reformat. Pull the live
  // control values into FOpts and refresh the preview (debounced). We do NOT
  // write yadf.ini here -- persistence happens only on OK (Save).
  if FUpdating then Exit;
  ControlsToOptions;
  FReformatTmr.Enabled:= False;   // debounce
  FReformatTmr.Enabled:= True;
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

// Returns the file name of the selected profile row, or '' if none is selected.
function SelectedProfile(AList: TListBox; const AFiles: TArray<string>): string;
var
  i: Integer;
begin
  Result:= '';
  i:= AList.ItemIndex;
  if (i >= 0) and (i <= High(AFiles)) then Result:= AFiles[i];
end;

procedure TYadfOptionsFrame.ProfileListClick(Sender: TObject);
var
  Name: string;
begin
  // Single-click a row -> edit THAT profile (SwitchEditTo auto-saves the
  // current one first). No-op when the row is already the one being edited.
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name <> '' then SwitchEditTo(Name);
end;

procedure TYadfOptionsFrame.SetFClick(Sender: TObject);
var
  Name: string;
begin
  // Assign the selected profile to F. Saved immediately (like YADFSetup); the
  // dialog OK/Cancel governs only the option VALUES, not the F/R mapping.
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name = '' then Exit;
  FProfiles.F:= Name;
  SaveProfiles(FProfiles);
  RefreshProfileList;
end;

procedure TYadfOptionsFrame.SetRClick(Sender: TObject);
var
  Name: string;
begin
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name = '' then Exit;
  FProfiles.R:= Name;
  SaveProfiles(FProfiles);
  RefreshProfileList;
end;

procedure TYadfOptionsFrame.UnassignClick(Sender: TObject);
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

procedure TYadfOptionsFrame.NewProfileClick(Sender: TObject);
var
  Nm, FileName, Path: string;
  k: Integer;
begin
  // Create a new yadf-<name>.ini seeded with the CURRENT settings, then switch
  // to editing it (ports YADFSetup.btnNewProfileClick). Sanitise the name so it
  // is a legal single-segment file name.
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

procedure TYadfOptionsFrame.LoadSample;
const
  // Built-in fallback so the preview always shows something even when no
  // Sample.pas is found next to the (design-time) package. Deliberately
  // "ugly" so the formatter has visible work to do.
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
  // Try a bundled Demo\Sample.pas relative to a few plausible roots (the BPL
  // dir, and its build-tree parents). If none is present, fall back to the
  // built-in snippet above.
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
end;

procedure TYadfOptionsFrame.Save;
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

  // Mirror onto the standard %APPDATA%\YADF\yadf.ini ONLY when the profile being
  // edited IS the F profile, so the F shortcut / CLI default (which read the
  // standard file) reflect these values even if F points at a custom-named file.
  // When editing R (or any non-F profile), do NOT mirror -- that would clobber
  // the F/standard file with R's values. Skip when the edited file already IS
  // the standard file (copying a file onto itself raises). Best-effort: a copy
  // failure must not lose the values already written to FCurrentIni.
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

{ ==================== TYadfOptionsPage ==================== }

constructor TYadfOptionsPage.Create(const ACaption: string; AFrameClass: TCustomFrameClass);
begin
  inherited Create;
  FCaption   := ACaption;
  FFrameClass:= AFrameClass;
end;

function TYadfOptionsPage.GetArea: string;
begin
  // Empty area = "Third Party" branch in the Options left tree.
  Result:= '';
end;

function TYadfOptionsPage.GetCaption: string;
begin
  Result:= FCaption;
end;

function TYadfOptionsPage.GetFrameClass: TCustomFrameClass;
begin
  Result:= FFrameClass;
end;

procedure TYadfOptionsPage.FrameCreated(AFrame: TCustomFrame);
begin
  if AFrame is TYadfOptionsFrame then
  begin
    FFrame:= TYadfOptionsFrame(AFrame);
    FFrame.Load;
  end;
end;

procedure TYadfOptionsPage.DialogClosed(Accepted: Boolean);
begin
  // Commit on OK (IDE convention); discard on Cancel. Nil the ref either way --
  // the IDE may destroy/recreate the frame between dialog opens.
  if Accepted and Assigned(FFrame) then FFrame.Save;
  FFrame:= nil;
end;

function TYadfOptionsPage.ValidateContents: Boolean;
begin
  Result:= True;
end;

function TYadfOptionsPage.GetHelpContext: Integer;
begin
  Result:= 0;
end;

function TYadfOptionsPage.IncludeInIDEInsight: Boolean;
begin
  Result:= True;
end;

{ ==================== register / unregister ==================== }

var
  // Kept so Unregister hands back the EXACT instances we registered.
  GOptions: array of INTAAddInOptions;

procedure RegisterYADFOptions;
var
  Svc: INTAEnvironmentOptionsServices;

  procedure Add(const ACap: string; AFC: TCustomFrameClass);
  var
    O: INTAAddInOptions;
  begin
    O:= TYadfOptionsPage.Create(ACap, AFC);
    Svc.RegisterAddInOptions(O);
    GOptions:= GOptions + [O];
  end;

begin
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then Exit;
  Add('YADF', TYadfOptionsFrame);   // single page; add more Add(...) to split later
end;

procedure UnregisterYADFOptions;
var
  Svc: INTAEnvironmentOptionsServices;
  O  : INTAAddInOptions;
begin
  if Length(GOptions) = 0 then Exit;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then
    for O in GOptions do
      try Svc.UnregisterAddInOptions(O); except end;
  SetLength(GOptions, 0);
end;

initialization

finalization
  UnregisterYADFOptions;   // secondary net; wizard's Destroyed is primary

end.