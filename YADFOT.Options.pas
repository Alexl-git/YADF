{
  YADFOT.Options -- Tools > Options > Third Party > YADF page for YADFOT.

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  A native IDE Options page with FULL YADFSetup parity -- because since the
  shared-frame extraction it literally IS the same UI: the page hosts
  YADF.OptionsFrame.TYadfOptionsFrame (Profiles panel + option grid built from
  the shared YADF.Options.OptionTable + live preview), the identical frame
  YADFSetup.exe embeds. This unit contributes only the Open Tools API plumbing:
  the INTAAddInOptions page that creates the frame under IdePersistPolicy
  (option values commit on OK; committing the F profile mirrors it onto the
  standard yadf.ini) and the register/unregister pair.

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
  , Vcl.Forms
  , ToolsAPI
  , YADF.OptionsFrame
  ;

type
  /// <summary>INTAAddInOptions page carrying the shared TYadfOptionsFrame.
  /// GetArea returns '' so the page lands under the "Third Party" branch; a
  /// dotted caption would nest sub-pages under a 'YADF' node. One instance per
  /// page; parameterized (ACaption, AFrameClass) so a later N-page split is a
  /// one-line change.</summary>
  /// <remarks>FrameCreated assigns IdePersistPolicy before Load: the preview
  /// is LIVE, and PROFILE actions (assign F/R, unassign, new, switch) save
  /// immediately like YADFSetup -- but the edited profile's option VALUES are
  /// written only on OK (DialogClosed(Accepted) -> frame.Commit); switching
  /// profiles flushes the current one first so no edits are lost.</remarks>
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
    FFrame.Policy:= IdePersistPolicy;   // commit-on-OK + F -> yadf.ini mirror
    FFrame.Load;
  end;
end;

procedure TYadfOptionsPage.DialogClosed(Accepted: Boolean);
begin
  // Commit on OK (IDE convention); discard on Cancel. Nil the ref either way --
  // the IDE may destroy/recreate the frame between dialog opens.
  if Accepted and Assigned(FFrame) then FFrame.Commit;
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
