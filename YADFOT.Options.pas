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
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Samples.Spin
  , ToolsAPI
  , YADF.Options
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
  /// (read-modify-write, so a future page split cannot clobber other fields).</summary>
  /// <remarks>Not thread-safe; the IDE drives Load/Save on the main thread.
  /// FControls is index-aligned to OptionTable. The page is inert until OK
  /// (no live autosave, unlike YADFSetup).</remarks>
  TYadfOptionsFrame = class(TFrame)
  private
    FOpts    : TYadfOptions;
    FScroll  : TScrollBox;
    FControls: array of TControl;   // index-aligned to OptionTable
    FUpdating: Boolean;             // True while pushing FOpts -> controls
    procedure BuildControls;
    procedure OptionsToControls;
    procedure ControlsToOptions;
    function  IniPath: string;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Read the shared yadf.ini into FOpts and populate the controls.</summary>
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
begin
  inherited Create(AOwner);
  Width := 520;
  Height:= 460;
  FScroll:= TScrollBox.Create(Self);
  FScroll.Parent  := Self;
  FScroll.Align   := alClient;
  FScroll.BorderStyle:= bsNone;
  BuildControls;
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

procedure TYadfOptionsFrame.Load;
var
  P: string;
begin
  P:= IniPath;
  EnsureIniExists(P);
  FOpts:= LoadOptionsFromIni(P);
  OptionsToControls;
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