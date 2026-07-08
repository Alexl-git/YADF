{
  YADFOT.Options -- Tools > Options > Third Party > YADF page for YADFOT.

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  A native IDE Options page that edits the shared per-user
  %APPDATA%\YADF\yadf.ini through the SAME YADF.Options descriptor table
  (OptionTable) as YADFSetup.exe and the CLI, so all three converge on one
  file with no duplicated schema. The page is a single generic TFrame whose
  controls are built by iterating OptionTable -- adding a field to
  TYadfOptions/OptionTable makes it appear here automatically.

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
  /// Load reads the shared yadf.ini into the controls; Save writes them back
  /// (read-modify-write, so a future page split cannot clobber other fields).
  /// A Source | Result preview pair to the right of the options re-runs
  /// FormatSource live as you toggle a control or edit the source, so you can
  /// see the effect of each option (and load your own .pas to preview).</summary>
  /// <remarks>Not thread-safe; the IDE drives Load/Save on the main thread.
  /// FControls is index-aligned to OptionTable. The preview is LIVE, but the
  /// yadf.ini is only written on OK (DialogClosed(Accepted)) -- toggling does
  /// not autosave (unlike the standalone YADFSetup).</remarks>
  TYadfOptionsFrame = class(TFrame)
  private
    FOpts    : TYadfOptions;
    FScroll  : TScrollBox;
    FControls: array of TControl;   // index-aligned to OptionTable
    FUpdating: Boolean;             // True while pushing FOpts -> controls
    // --- live before/after preview (mirrors YADFSetup's Source|Result) ---
    FSource     : TMemo;            // editable sample source (input)
    FResult     : TMemo;            // formatted output (read-only)
    FSourceName : TLabel;          // "file: <name>" for the loaded sample
    FResultStat : TLabel;          // "OK" / "error"
    FOpenDlg    : TOpenDialog;      // load-your-own-.pas dialog
    FReformatTmr: TTimer;          // debounce reformat on rapid changes
    procedure BuildControls;
    procedure BuildPreview;
    procedure OptionsToControls;
    procedure ControlsToOptions;
    function  IniPath: string;
    procedure Reformat;
    procedure LoadSample;
    // event handlers
    procedure OptionChanged(Sender: TObject);
    procedure SourceChanged(Sender: TObject);
    procedure ReformatTimer(Sender: TObject);
    procedure OpenSourceClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Read the shared yadf.ini into FOpts, populate the controls, load
    /// a sample into the source memo, and render the first preview.</summary>
    procedure Load;
    /// <summary>Re-read the record fresh, apply this frame's controls, write it back.</summary>
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
  Splitter: TSplitter;
begin
  inherited Create(AOwner);
  Width := 900;
  Height:= 520;

  // Debounce timer: coalesces a burst of control changes into one reformat.
  FReformatTmr:= TTimer.Create(Self);
  FReformatTmr.Enabled := False;
  FReformatTmr.Interval:= 200;
  FReformatTmr.OnTimer := ReformatTimer;

  // Options on the LEFT (scrolling group-boxes), a splitter, then the
  // Source | Result preview filling the rest -- same left-to-right order as
  // YADFSetup (Settings | Source | Result).
  FScroll:= TScrollBox.Create(Self);
  FScroll.Parent  := Self;
  FScroll.Align   := alLeft;
  FScroll.Width   := 360;
  FScroll.BorderStyle:= bsNone;

  Splitter:= TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Left   := FScroll.Left + FScroll.Width;   // dock right of FScroll
  Splitter.Align  := alLeft;
  Splitter.Width  := 5;

  BuildControls;
  BuildPreview;
end;

function TYadfOptionsFrame.IniPath: string;
begin
  // The IDE options page always edits the shared per-user profile -- the same
  // file YADFSetup edits by default and tier 4 of the wizard's resolution.
  Result:= SharedAppDataIniPath;
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
var
  P: string;
begin
  P:= IniPath;
  EnsureIniExists(P);
  FOpts:= LoadOptionsFromIni(P);
  OptionsToControls;    // FUpdating guards the ~40 OnChange fires here
  LoadSample;           // populate the source memo
  Reformat;             // render the first before/after view
end;

procedure TYadfOptionsFrame.Save;
var
  P: string;
begin
  // Read-modify-write: re-read the record fresh so any field NOT surfaced as a
  // control survives (none today; a guard for a future page split), then apply
  // this frame's controls and write the whole record back through the shared
  // OptionTable serializer (comments in the template are preserved).
  P:= IniPath;
  FOpts:= LoadOptionsFromIni(P);
  ControlsToOptions;
  SaveOptionsToIni(FOpts, P);
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