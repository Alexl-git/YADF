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

unit YADF.OptionsFrame;   // dl:shared YADFOT, YADFSetup

interface

uses
  Winapi.Windows
  , System.SysUtils
  , System.Classes
  , System.Variants
  , System.IOUtils
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Dialogs
  , Vcl.Samples.Spin
  , Vcl.Clipbrd
  , YADF.Options
  , YADF.Layout
  ;

type
  /// <summary>Per-host persistence behavior of TYadfOptionsFrame. Assign one
  /// of the ready-made SetupPersistPolicy / IdePersistPolicy constants to the
  /// frame's Policy property right after Create (default: both False -- the
  /// frame is inert until told otherwise).</summary>
  /// <remarks>
  /// AutoSave: persist the edited profile INI on every option change
  /// (YADFSetup model; no OK/Cancel), debounced onto the preview timer so
  /// per-keystroke spin-edit transients never hit the disk. MirrorF: when the
  /// F profile's values are persisted, best-effort copy the file onto the
  /// standard %APPDATA%\YADF\yadf.ini so the F shortcut / CLI default stay in
  /// sync even when F points at a custom-named file; under a commit-on-OK
  /// policy the mirror runs only on Commit (a profile-row click must not
  /// propagate edits Cancel cannot undo), and it never overwrites a file that
  /// is itself assigned as the R profile. Both shipping hosts set
  /// MirrorF=True -- the two UIs must never disagree about yadf.ini.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (YADF.OptionsFrame.pas)
  /// Used in units: YADF.OptionsFrame
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TYadfOptionsPersistPolicy = record
    AutoSave: Boolean;
    MirrorF : Boolean;
  end;

  /// <summary>Fired whenever the frame loads, saves, or switches the edited
  /// INI, with a ready-to-display line such as 'INI: C:\...\yadf.ini (saved)'.
  /// Hosts with a status label (YADFSetup) subscribe; others ignore it.</summary>
  /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (YADF.OptionsFrame.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TYadfIniStatusEvent = procedure(const AText: string) of object;

  /// <summary>The shared YADF settings frame: Profiles panel + option grid +
  /// live before/after preview. Controls are code-built by iterating
  /// YADF.Options.OptionTable (adding a field to TYadfOptions/OptionTable makes
  /// it appear in every host automatically); the .dfm resource is a bare
  /// streamable root only -- required because TCustomFrame.Create streams a
  /// per-class resource and raises EResNotFound when none exists.</summary>
  /// <remarks>
  /// Not thread-safe; both hosts drive it on the main VCL thread.
  /// FControls is index-aligned to OptionTable; FProfileFiles to the profile
  /// list rows. Call sequence for hosts: Create -> Policy := ... ->
  /// [OnIniStatus := ...] -> Load. IDE host additionally calls Commit on OK.
  /// The preview is LIVE (debounced); reformat is skipped for options whose
  /// TOptInfo.AffectsPreview is False (their output would be identical).
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (YADFOT.Options.pas), YADFOT.Options.TYadfOptionsPage.FrameCreated (YADFOT.Options.pas), YADFOT.Options.RegisterYADFOptions (YADFOT.Options.pas), declaration (uYADFSetupMain.pas), uYADFSetupMain.TfrmMain.FormCreate (uYADFSetupMain.pas)
  /// Used in units: uYADFSetupMain, YADFOT.Options
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TYadfOptionsFrame = class(TFrame)  // dl:ok god-class@eeb0, high-response@eeb0
    private
      FOpts           : TYadfOptions             ;
      FPolicy         : TYadfOptionsPersistPolicy;
      FOnIniStatus    : TYadfIniStatusEvent      ;
      FPendingSave    : Boolean                  ; // a debounced autosave is queued on the timer
      FPendingReformat: Boolean                  ; // a debounced preview refresh is queued
      FScroll         : TScrollBox               ;
      FControls       : array of TControl        ; // index-aligned to OptionTable
      FUpdating       : Boolean                  ; // True while pushing FOpts -> controls;
      // suppresses OptionChanged so programmatic
      // writes don't clobber FOpts mid-loop
      // --- profiles panel ---
      FProfiles    : TYadfProfiles ; // current F/R mapping from profiles.ini
      FProfileFiles: TArray<string>; // file names, index-aligned to list rows
      FCurrentIni  : string        ; // full path of the profile being edited
      FProfileList : TListBox      ; // the profiles list control
      FEditingLbl  : TLabel        ; // 'Editing: <file>'
      // --- live before/after preview ---
      FSource     : TMemo      ; // editable sample source (input)
      FResult     : TMemo      ; // formatted output (read-only)
      FSourceName : TLabel     ; // 'file: <name>' for the loaded sample
      FResultStat : TLabel     ; // 'OK' / 'error'
      FOpenDlg    : TOpenDialog; // load-your-own-.pas dialog
      FReformatTmr: TTimer     ; // debounce reformat on rapid changes
      /// <param name="AHost"><!-- drag-lint:auto type -->TWinControl</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Create (YADF.OptionsFrame.pas)
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel.AddBtn
      /// Reads: FEditingLbl, FProfileList   Writes: FEditingLbl, FProfileList
      /// UI thread only -- touches AHost
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel.AddBtn"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BuildProfilePanel(AHost: TWinControl);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Create (YADF.OptionsFrame.pas)
      /// Calls: YADF.Options.OptionHint
      /// Reads: FControls, FScroll
      /// UI thread only -- touches Parent
      /// Pure
      /// <seealso cref="YADF.Options.OptionHint"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BuildControls;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Create (YADF.OptionsFrame.pas)
      /// Reads: FSourceName, FSource, FResultStat, FResult, FOpenDlg   Writes: FSourceName, FSource, FResultStat, FResult, FOpenDlg
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure BuildPreview;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.LoadOptionsFromFile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.ResetToDefaults (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas)
      /// Calls: TCheckBox, TComboBox, TEdit, TSpinEdit, VarToStr
      /// Reads: FOpts, FControls   Writes: FUpdating
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure OptionsToControls;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Commit (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.NewProfileClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.OptionChanged (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SaveOptionsToFile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas)
      /// Calls: TCheckBox, TComboBox, TEdit, TSpinEdit
      /// Reads: FOpts, FControls
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ControlsToOptions;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.NewProfileClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.UnassignSelected (YADF.OptionsFrame.pas)
      /// Calls: DirectoryExists, ExtractFileName, ForceDirectories, SameText
      /// Reads: FProfileFiles, FCurrentIni, FProfileList, FProfiles, FEditingLbl
      /// Touches: file system
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure RefreshProfileList;
      /// <param name="AIniFile"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.NewProfileClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.ProfileListClick (YADF.OptionsFrame.pas)
      /// Calls: ExtractFileName, SameFileName, YADF.Options.EnsureIniExists, YADF.Options.LoadOptionsFromIni, YADF.Options.ResolveProfileIniPath, YADF.Options.SaveOptionsToIni, YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions, YADF.OptionsFrame.TYadfOptionsFrame.DoIniStatus, YADF.OptionsFrame.TYadfOptionsFrame.MirrorFProfile, YADF.OptionsFrame.TYadfOptionsFrame.OptionsToControls, YADF.OptionsFrame.TYadfOptionsFrame.Reformat
      /// Reads: FCurrentIni, FOpts, FPolicy, FEditingLbl   Writes: FPendingSave, FCurrentIni, FOpts
      /// <seealso cref="YADF.Options.EnsureIniExists"/>
      /// <seealso cref="YADF.Options.LoadOptionsFromIni"/>
      /// <seealso cref="YADF.Options.ResolveProfileIniPath"/>
      /// <seealso cref="YADF.Options.SaveOptionsToIni"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SwitchEditTo(const AIniFile: string);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.LoadOptionsFromFile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.OpenSourceClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.ReformatTimer (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.ResetToDefaults (YADF.OptionsFrame.pas) (+1 more)
      /// Calls: YADF.Layout.FormatSource/2
      /// Reads: FResult, FSource, FOpts, FResultStat
      /// Pure
      /// <seealso cref="YADF.Layout.FormatSource"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Reformat;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas)
      /// Calls: ExtractFileName, ExtractFilePath, GetModuleName
      /// Reads: FSource, FSourceName
      /// Touches: file system
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LoadSample;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Destroy (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.LoadOptionsFromFile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.ReformatTimer (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.ResetToDefaults (YADF.OptionsFrame.pas)
      /// Calls: YADF.Options.SaveOptionsToIni, YADF.OptionsFrame.TYadfOptionsFrame.DoIniStatus, YADF.OptionsFrame.TYadfOptionsFrame.MirrorFProfile
      /// Reads: FOpts, FCurrentIni
      /// Pure
      /// <seealso cref="YADF.Options.SaveOptionsToIni"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.DoIniStatus"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.MirrorFProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SaveCurrentProfile;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Commit (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas)
      /// Calls: SameFileName, YADF.Options.ResolveProfileIniPath
      /// Reads: FPolicy, FCurrentIni, FProfiles
      /// Touches: file system
      /// <seealso cref="YADF.Options.ResolveProfileIniPath"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure MirrorFProfile;
      /// <param name="ASuffix"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.Commit (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.Load (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo (YADF.OptionsFrame.pas)
      /// Calls: FOnIniStatus
      /// Reads: FOnIniStatus, FCurrentIni
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoIniStatus(const ASuffix: string);
      /// <param name="AWhich"><!-- drag-lint:auto type -->Char</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.ProfileListKeyDown (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SetFClick (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.SetRClick (YADF.OptionsFrame.pas)
      /// Calls: YADF.Options.SaveProfiles, YADF.OptionsFrame.SelectedProfile, YADF.OptionsFrame.TYadfOptionsFrame.RefreshProfileList
      /// Reads: FProfileList, FProfileFiles, FProfiles
      /// Pure
      /// <seealso cref="YADF.Options.SaveProfiles"/>
      /// <seealso cref="YADF.OptionsFrame.SelectedProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.RefreshProfileList"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AssignShortcut(AWhich: Char);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADF.OptionsFrame.TYadfOptionsFrame.ProfileListKeyDown (YADF.OptionsFrame.pas), YADF.OptionsFrame.TYadfOptionsFrame.UnassignClick (YADF.OptionsFrame.pas)
      /// Calls: SameText, YADF.Options.SaveProfiles, YADF.OptionsFrame.SelectedProfile, YADF.OptionsFrame.TYadfOptionsFrame.RefreshProfileList
      /// Reads: FProfileList, FProfileFiles, FProfiles
      /// Pure
      /// <seealso cref="YADF.Options.SaveProfiles"/>
      /// <seealso cref="YADF.OptionsFrame.SelectedProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.RefreshProfileList"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure UnassignSelected;
      // event handlers
      /// <summary><!-- drag-lint:auto -->event handlers</summary>
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: TControl, YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions
      /// Reads: FUpdating, FPolicy, FPendingSave, FPendingReformat, FReformatTmr   Writes: FPendingSave, FPendingReformat
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure OptionChanged   (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Reads: FReformatTmr   Writes: FPendingReformat
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SourceChanged   (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.Reformat, YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile
      /// Reads: FReformatTmr, FPendingSave, FPendingReformat   Writes: FPendingSave, FPendingReformat
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Reformat"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ReformatTimer   (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: ExtractFileName, YADF.OptionsFrame.TYadfOptionsFrame.Reformat
      /// Reads: FOpenDlg, FSource, FSourceName
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Reformat"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure OpenSourceClick (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Reads: FResult
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CopyResultClick (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.SelectedProfile, YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo
      /// Reads: FProfileList, FProfileFiles
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.SelectedProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ProfileListClick(Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="Key"><!-- drag-lint:auto type -->var Word</param>
      /// <param name="Shift"><!-- drag-lint:auto type -->TShiftState</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut, YADF.OptionsFrame.TYadfOptionsFrame.UnassignSelected
      /// Mutates: Key (var)
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.UnassignSelected"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ProfileListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetFClick      (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetRClick      (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.UnassignSelected
      /// Pure
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.UnassignSelected"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure UnassignClick  (Sender: TObject);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: CharInSet, FileExists, InputQuery, MessageDlg, Trim, YADF.Options.ResolveProfileIniPath, YADF.Options.SaveOptionsToIni, YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions, YADF.OptionsFrame.TYadfOptionsFrame.RefreshProfileList, YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo
      /// Reads: FOpts
      /// Pure
      /// <seealso cref="YADF.Options.ResolveProfileIniPath"/>
      /// <seealso cref="YADF.Options.SaveOptionsToIni"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.RefreshProfileList"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.SwitchEditTo"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure NewProfileClick(Sender: TObject);
    public
      /// <summary>Builds the complete control tree in code -- profiles panel,
      /// option grid host, splitter, preview panes, debounce timer; the .dfm
      /// resource supplies only the bare streamable root. Host call sequence:
      /// Create -> Policy := ... -> [OnIniStatus := ...] -> Load.</summary>
      /// <param name="AOwner"><!-- drag-lint:auto type -->TComponent</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.BuildControls, YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview, YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel
      /// constructor
      /// Reads: FReformatTmr, FScroll   Writes: FReformatTmr, FScroll
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Commit"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(AOwner: TComponent); override;
      /// <summary>Flushes a still-pending debounced autosave so closing the
      /// host right after an option click cannot lose the edit.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile
      /// Reads: FPendingSave   Writes: FOnIniStatus, FPendingSave
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildProfilePanel"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <summary>Start editing the F profile (the file the F shortcut, the CLI
      /// default and YADFSetup all resolve): read it into FOpts, populate the
      /// controls and the profiles list, load a sample and render the first
      /// preview. Call once, after assigning Policy.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADFOT.Options.TYadfOptionsPage.FrameCreated (YADFOT.Options.pas), declaration (Loader2019.dxSettings.pas) ?
      /// Calls: YADF.Options.EnsureIniExists, YADF.Options.LoadOptionsFromIni, YADF.Options.ResolveProfileIniPath, YADF.OptionsFrame.TYadfOptionsFrame.DoIniStatus, YADF.OptionsFrame.TYadfOptionsFrame.LoadSample, YADF.OptionsFrame.TYadfOptionsFrame.OptionsToControls, YADF.OptionsFrame.TYadfOptionsFrame.Reformat, YADF.OptionsFrame.TYadfOptionsFrame.RefreshProfileList
      /// Reads: FProfiles, FCurrentIni   Writes: FProfiles, FCurrentIni, FOpts
      /// <seealso cref="YADF.Options.EnsureIniExists"/>
      /// <seealso cref="YADF.Options.LoadOptionsFromIni"/>
      /// <seealso cref="YADF.Options.ResolveProfileIniPath"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.DoIniStatus"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.LoadSample"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Load;
      /// <summary>Persist the edited values on the host's explicit save point
      /// (the IDE dialog's OK). Read-modify-write of the profile CURRENTLY being
      /// edited: re-read the record fresh so any field not surfaced as a control
      /// survives, apply this frame's controls, write it back. When
      /// Policy.MirrorF is True and the edited profile IS the F profile,
      /// best-effort copy it onto the standard %APPDATA%\YADF\yadf.ini (skipped
      /// when the edited file already IS yadf.ini; a locked/read-only standard
      /// file does not lose the values written to the profile itself).</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: YADFOT.Options.TYadfOptionsPage.DialogClosed (YADFOT.Options.pas), uAREAOFINTEREST_SERVER.TDataService_AREAOFINTEREST_SERVER.Load (uAREAOFINTEREST_SERVER.PAS) ?, uAREAOFINTEREST_SERVER.TDataService_AREAOFINTEREST_SERVER.Save (uAREAOFINTEREST_SERVER.PAS) ?, uAREAOFINTEREST_SERVER.TDataService_AREAOFINTEREST_SERVER.NextID (uAREAOFINTEREST_SERVER.PAS) ?, uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.Load (uCAUSFAIL_SERVER.PAS) ? (+519 more)
      /// Calls: YADF.Options.LoadOptionsFromIni, YADF.Options.SaveOptionsToIni, YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions, YADF.OptionsFrame.TYadfOptionsFrame.DoIniStatus, YADF.OptionsFrame.TYadfOptionsFrame.MirrorFProfile
      /// Reads: FCurrentIni, FOpts   Writes: FOpts
      /// <seealso cref="YADF.Options.LoadOptionsFromIni"/>
      /// <seealso cref="YADF.Options.SaveOptionsToIni"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.DoIniStatus"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.MirrorFProfile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Commit;
      /// <summary>Read options from an arbitrary INI into the grid (YADFSetup's
      /// "Load Settings"). Under Policy.AutoSave the values are immediately
      /// persisted to the profile being edited.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.Options.LoadOptionsFromIni, YADF.OptionsFrame.TYadfOptionsFrame.OptionsToControls, YADF.OptionsFrame.TYadfOptionsFrame.Reformat, YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile
      /// Reads: FPolicy   Writes: FOpts
      /// <seealso cref="YADF.Options.LoadOptionsFromIni"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.OptionsToControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Reformat"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LoadOptionsFromFile(const APath: string);
      /// <summary>Write the grid's current values to an arbitrary INI
      /// (YADFSetup's "Save As..."). Does not change which profile is edited.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.Options.SaveOptionsToIni, YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions
      /// Reads: FOpts
      /// Pure
      /// <seealso cref="YADF.Options.SaveOptionsToIni"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.ControlsToOptions"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildPreview"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SaveOptionsToFile(const APath: string);
      /// <summary>Reset the grid to DefaultOptions (YADFSetup's "Reset"; any
      /// confirmation prompt is the host's job). Under Policy.AutoSave the
      /// defaults are immediately persisted to the profile being edited.</summary>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: YADF.OptionsFrame.TYadfOptionsFrame.OptionsToControls, YADF.OptionsFrame.TYadfOptionsFrame.Reformat, YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile
      /// Reads: FPolicy   Writes: FOpts
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.OptionsToControls"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.Reformat"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.SaveCurrentProfile"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.AssignShortcut"/>
      /// <seealso cref="YADF.OptionsFrame.TYadfOptionsFrame.BuildControls"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ResetToDefaults;
      /// <summary>Full path of the profile INI currently being edited.</summary>
      property CurrentIniPath: string read FCurrentIni;
      /// <summary>Persistence behavior; assign right after Create, before Load.</summary>
      property Policy: TYadfOptionsPersistPolicy read FPolicy write FPolicy;
      /// <summary>Optional status-line sink; see TYadfIniStatusEvent.</summary>
      property OnIniStatus: TYadfIniStatusEvent read FOnIniStatus write FOnIniStatus;
  end;

const
  /// <summary>YADFSetup.exe: autosave every change; every persist of the F
  /// profile mirrors onto the standard yadf.ini.</summary>
  SetupPersistPolicy: TYadfOptionsPersistPolicy = (AutoSave: True; MirrorF: True);
  /// <summary>IDE Tools > Options page: values persist only on Commit (OK) or
  /// a profile switch; every persist of the F profile mirrors onto the
  /// standard yadf.ini.</summary>
  IdePersistPolicy: TYadfOptionsPersistPolicy = (AutoSave: False; MirrorF: True);

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
  LeftHost: TPanel   ;
begin
  inherited Create(AOwner);
  Width := 900;  // dl:ok large-magic-number@7f52
  Height:= 520;  // dl:ok large-magic-number@2a90

  // Debounce timer: coalesces a burst of control changes into one reformat.
  FReformatTmr:= TTimer.Create(Self);
  FReformatTmr.Enabled := False;
  FReformatTmr.Interval:= 200;  // dl:ok large-magic-number@c5ec
  FReformatTmr.OnTimer := ReformatTimer;

  // The LEFT region is a host panel holding the Profiles panel (docked top, so
  // it stays visible) above the scrolling option group-boxes (alClient). A
  // splitter separates it from the Source | Result preview filling the rest.
  LeftHost:= TPanel.Create(Self);
  LeftHost.Parent    := Self;
  LeftHost.Align     := alLeft;
  LeftHost.Width     := 360;
  LeftHost.BevelOuter:= bvNone;

  BuildProfilePanel(LeftHost); // docks itself alTop within LeftHost

  FScroll:= TScrollBox.Create(Self);
  FScroll.Parent     := LeftHost;
  FScroll.Align      := alClient; // fills LeftHost below the profiles panel
  FScroll.BorderStyle:= bsNone;

  Splitter:= TSplitter.Create(Self);
  Splitter.Parent:= Self;
  Splitter.Left:= LeftHost.Left + LeftHost.Width; // dock right of LeftHost
  Splitter.Align:= alLeft;
  Splitter.Width:= 5;

  BuildControls;
  BuildPreview;
end; // constructor

destructor TYadfOptionsFrame.Destroy;
begin
  // A debounced autosave may still be queued; FOpts already holds the edited
  // values (ControlsToOptions ran at change time), so flushing here touches
  // no child controls. Drop the status sink first -- the host's label may be
  // mid-destruction.
  FOnIniStatus:= nil;
  if FPendingSave then
  begin
    FPendingSave:= False;
    SaveCurrentProfile;
  end;
  inherited;  // dl:ok inherited-bare@246d
end; // destructor

procedure TYadfOptionsFrame.BuildProfilePanel(AHost: TWinControl);
var
  Panel: TPanel;
  Bar  : TPanel;
  Lbl  : TLabel;

  function AddBtn(ALeft: Integer; const ACap: string; AOnClick: TNotifyEvent; const AHint: string): TButton;
  begin
    Result:= TButton.Create(Self);
    Result.Parent:= Bar;
    Result.Left:= ALeft; Result.Top:= 1; Result.Width:= 62; Result.Height:= 23;  // dl:ok large-magic-number@caa7
    Result.Caption:= ACap;
    Result.Hint:= AHint; Result.ShowHint:= True;
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
  Panel.Height    := 168;  // dl:ok large-magic-number@7b14
  Panel.BevelOuter:= bvNone;

  Lbl:= TLabel.Create(Self);
  Lbl.Parent:= Panel;
  Lbl.Left:= 4; Lbl.Top:= 2;
  Lbl.Caption:= 'Profiles (F = Ctrl+Shift+Alt+F, R = Ctrl+Shift+Alt+R)';

  // Bottom strip: button row + the 'Editing:' line under it.
  Bar:= TPanel.Create(Self);
  Bar.Parent    := Panel;
  Bar.Align     := alBottom;
  Bar.Height    := 44;  // dl:ok large-magic-number@5f66
  Bar.BevelOuter:= bvNone;
  AddBtn( 2 , 'Set F'   , SetFClick      , 'Assign the selected profile to Ctrl+Shift+Alt+F (and the CLI default). Keyboard: F'    );
  AddBtn( 66, 'Set R'   , SetRClick      , 'Assign the selected profile to Ctrl+Shift+Alt+R. Keyboard: R'                          );  // dl:ok large-magic-number@4117
  AddBtn(130, 'Unassign', UnassignClick  , 'Clear the F/R assignment of the selected profile (F resets to yadf.ini). Keyboard: Del');  // dl:ok large-magic-number@ca31
  AddBtn(194, 'New...'  , NewProfileClick, 'Create a new yadf-<name>.ini seeded with the current settings'                         );  // dl:ok large-magic-number@66a8

  FEditingLbl:= TLabel.Create(Self);
  FEditingLbl.Parent:= Bar;
  FEditingLbl.Left:= 4; FEditingLbl.Top:= 27;  // dl:ok large-magic-number@b7e5
  FEditingLbl.Caption:= 'Editing:';

  // The list fills the space between the label and the bottom strip.
  FProfileList:= TListBox.Create(Self);
  FProfileList.Parent          := Panel;
  FProfileList.Align           := alClient;
  FProfileList.AlignWithMargins:= True;
  FProfileList.Margins.SetBounds(4, 18, 4, 2);  // dl:ok large-magic-number@d259
  FProfileList.OnClick  := ProfileListClick;
  FProfileList.OnKeyDown:= ProfileListKeyDown;
end; // begin

procedure TYadfOptionsFrame.BuildControls;
var
  T     : TArray<TOptInfo>;
  i     : Integer         ;
  y     : Integer         ;
  CurGrp: string          ;
  gb    : TGroupBox       ;
  Parent: TWinControl     ;
  yIn   : Integer         ;
  cb    : TCheckBox       ;
  se    : TSpinEdit       ;
  ed    : TEdit           ;
  cmb   : TComboBox       ;
  Lbl   : TLabel          ;
begin
  // One TGroupBox per TOptInfo.Group, one control per row keyed by Kind,
  // stored index-aligned in FControls.
  T:= OptionTable;
  SetLength(FControls, Length(T));
  CurGrp:= '';
  gb:= nil;
  Parent:= FScroll;
  y     := 4;
  yIn   := 0;
  for i:= 0 to High(T) do
  begin
    if T[i].Group <> CurGrp then
    begin
      CurGrp:= T[i].Group;
      gb:= TGroupBox.Create(Self);
      gb.Parent:= FScroll;
      gb.Left  := 4;
      gb.Top   := y;
      gb.Width:= FScroll.ClientWidth - 28;  // dl:ok large-magic-number@ffcb
      gb.Anchors:= [akLeft, akTop, akRight];
      gb.Caption:= CurGrp;
      Parent:= gb;
      yIn   := 18;  // dl:ok large-magic-number@dce8
    end; // if
    case T[i].Kind of
      okBool:
      begin
        cb:= TCheckBox.Create(Self);
        cb.Parent:= Parent;
        cb.Left:= 10; cb.Top:= yIn; cb.Width:= gb.Width - 20;
        cb.Caption:= T[i].Caption;
        cb.Hint:= OptionHint(T[i]); cb.ShowHint:= True;
        cb.Tag    := i;
        cb.OnClick:= OptionChanged;
        FControls[i]:= cb;
        Inc(yIn, 24);
      end; // case
      okInt:
      begin
        Lbl:= TLabel.Create(Self);
        Lbl.Parent:= Parent; Lbl.Left:= 10; Lbl.Top:= yIn + 3;
        Lbl.Caption:= T[i].Caption;
        se:= TSpinEdit.Create(Self);
        se.Parent:= Parent; se.Left:= 240; se.Top:= yIn; se.Width:= 80;  // dl:ok large-magic-number@f1d9
        se.MinValue:= 0; se.MaxValue:= 100000;  // dl:ok large-magic-number@8d21
        se.Hint:= OptionHint(T[i]); se.ShowHint:= True;
        se.Tag     := i;
        se.OnChange:= OptionChanged;
        FControls[i]:= se;
        Inc(yIn, 28);  // dl:ok large-magic-number@ce48
      end; // begin
      okString:
      begin
        Lbl:= TLabel.Create(Self);
        Lbl.Parent:= Parent; Lbl.Left:= 10; Lbl.Top:= yIn + 3;
        Lbl.Caption:= T[i].Caption;
        ed:= TEdit.Create(Self);
        ed.Parent:= Parent; ed.Left:= 240; ed.Top:= yIn; ed.Width:= gb.Width - 250;  // dl:ok large-magic-number@2eb3
        ed.Anchors:= [akLeft, akTop, akRight];
        ed.Hint:= OptionHint(T[i]); ed.ShowHint:= True;
        ed.Tag     := i;
        ed.OnChange:= OptionChanged;
        FControls[i]:= ed;
        Inc(yIn, 28);  // dl:ok large-magic-number@ce48
      end; // begin
      okEnum:
      begin
        Lbl:= TLabel.Create(Self);
        Lbl.Parent:= Parent; Lbl.Left:= 10; Lbl.Top:= yIn + 3;
        Lbl.Caption:= T[i].Caption;
        cmb:= TComboBox.Create(Self);
        cmb.Parent:= Parent; cmb.Left:= 240; cmb.Top:= yIn; cmb.Width:= 110;  // dl:ok large-magic-number@292a
        cmb.Style:= csDropDownList;
        for var V in T[i].EnumValues do // value list lives in the descriptor
          cmb.Items.Add(V);
        cmb.Hint:= OptionHint(T[i]); cmb.ShowHint:= True;
        cmb.Tag     := i;
        cmb.OnChange:= OptionChanged;
        FControls[i]:= cmb;
        Inc(yIn, 28);  // dl:ok large-magic-number@ce48
      end; // begin
    end; // case
    if gb <> nil then
    begin
      gb.Height:= yIn + 6;
      y:= gb.Top + gb.Height + 6;
    end;
  end; // for
end; // procedure

procedure TYadfOptionsFrame.BuildPreview;
var
  Host   : TPanel   ; // fills the area right of the options splitter
  SrcPane: TPanel   ; // left half of the preview: source
  ResPane: TPanel   ; // right half of the preview: result
  SrcBar : TPanel   ; // top strip of SrcPane: [Load .pas...] + filename
  ResBar : TPanel   ; // top strip of ResPane: [Copy] + status label
  Btn    : TButton  ;
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
  SrcPane.Width     := 260;  // dl:ok large-magic-number@2371
  SrcPane.BevelOuter:= bvNone;

  SrcBar:= TPanel.Create(Self);
  SrcBar.Parent    := SrcPane;
  SrcBar.Align     := alTop;
  SrcBar.Height    := 26;  // dl:ok large-magic-number@6dcb
  SrcBar.BevelOuter:= bvNone;

  Btn:= TButton.Create(Self);
  Btn.Parent:= SrcBar;
  Btn.Left:= 2; Btn.Top:= 1; Btn.Width:= 90; Btn.Height:= 23;  // dl:ok large-magic-number@0e62
  Btn.Caption:= 'Load .pas...';
  Btn.Hint:= 'Load your own Pascal file into the preview'; Btn.ShowHint:= True;
  Btn.OnClick:= OpenSourceClick;

  FSourceName:= TLabel.Create(Self);
  FSourceName.Parent:= SrcBar;
  FSourceName.Left:= 98; FSourceName.Top:= 5;  // dl:ok large-magic-number@cb79
  FSourceName.Caption:= 'source';

  FSource:= TMemo.Create(Self);
  FSource.Parent    := SrcPane;
  FSource.Align     := alClient;
  FSource.ScrollBars:= ssBoth;
  FSource.WordWrap  := False;
  FSource.Font.Name:= 'Consolas';
  FSource.OnChange:= SourceChanged;

  // Splitter between source and result.
  Split:= TSplitter.Create(Self);
  Split.Parent:= Host;
  Split.Left:= SrcPane.Left + SrcPane.Width;
  Split.Align:= alLeft;
  Split.Width:= 5;

  // --- Result pane (read-only output) fills the rest ---
  ResPane:= TPanel.Create(Self);
  ResPane.Parent    := Host;
  ResPane.Align     := alClient;
  ResPane.BevelOuter:= bvNone;

  ResBar:= TPanel.Create(Self);
  ResBar.Parent    := ResPane;
  ResBar.Align     := alTop;
  ResBar.Height    := 26;  // dl:ok large-magic-number@96ca
  ResBar.BevelOuter:= bvNone;

  Btn:= TButton.Create(Self);
  Btn.Parent:= ResBar;
  Btn.Left:= 2; Btn.Top:= 1; Btn.Width:= 60; Btn.Height:= 23;  // dl:ok large-magic-number@16f4
  Btn.Caption:= 'Copy';
  Btn.Hint:= 'Copy the formatted result to the clipboard'; Btn.ShowHint:= True;
  Btn.OnClick:= CopyResultClick;

  FResultStat:= TLabel.Create(Self);
  FResultStat.Parent:= ResBar;
  FResultStat.Left:= 70; FResultStat.Top:= 5;  // dl:ok large-magic-number@9ebe
  FResultStat.Caption:= 'result';

  FResult:= TMemo.Create(Self);
  FResult.Parent    := ResPane;
  FResult.Align     := alClient;
  FResult.ScrollBars:= ssBoth;
  FResult.WordWrap  := False;
  FResult.ReadOnly  := True;
  FResult.Font.Name:= 'Consolas';

  // Load-your-own-file dialog.
  FOpenDlg:= TOpenDialog.Create(Self);
  FOpenDlg.Filter:= 'Pascal files (*.pas;*.dpr;*.inc)|*.pas;*.dpr;*.inc|All files (*.*)|*.*';
  FOpenDlg.Options:= FOpenDlg.Options + [ofFileMustExist];
end; // procedure

{ ==================== grid <-> record ==================== }

procedure TYadfOptionsFrame.OptionsToControls;
var
  T: TArray<TOptInfo>;
  i: Integer         ;
  V: Variant         ;
begin
  // Setting Checked/Value/Text/ItemIndex fires the control's OnClick/OnChange,
  // i.e. OptionChanged. Suppress it: otherwise each programmatic write would
  // read back the not-yet-updated controls and clobber FOpts mid-loop (which
  // broke Reset and left spin edits stuck at 0 in early YADFSetup builds).
  T        := OptionTable;
  FUpdating:= True;
  try
    for i:= 0 to High(T) do
    begin
      V:= T[i].GetVal(FOpts);
      case T[i].Kind of
        okBool : TCheckBox(FControls[i]).Checked:= V;
        okInt  : TSpinEdit(FControls[i]).Value  := V;
        okString: TEdit(FControls[i]).Text:= VarToStr(V)                                                ;
        okEnum  : TComboBox(FControls[i]).ItemIndex:= TComboBox(FControls[i]).Items.IndexOf(VarToStr(V));
      end;
    end;
  finally
    FUpdating:= False;
  end; // try
end; // procedure

procedure TYadfOptionsFrame.ControlsToOptions;
var
  T: TArray<TOptInfo>;
  i: Integer         ;
begin
  T:= OptionTable;
  for i:= 0 to High(T) do
  case T[i].Kind of
    okBool  : T[i].SetVal(FOpts, TCheckBox(FControls[i]).Checked);
    okInt   : T[i].SetVal(FOpts, TSpinEdit(FControls[i]).Value)  ;
    okString: T[i].SetVal(FOpts, TEdit(FControls[i]).Text)       ;
    okEnum  : T[i].SetVal(FOpts, TComboBox(FControls[i]).Text)   ;
  end;
end;

{ ==================== persistence ==================== }

procedure TYadfOptionsFrame.DoIniStatus(const ASuffix: string);
begin
  if Assigned(FOnIniStatus) then
    FOnIniStatus('INI: ' + FCurrentIni + ASuffix);
end;

procedure TYadfOptionsFrame.MirrorFProfile;
var
  Shared: string;
begin
  // Mirror the edited file onto the standard %APPDATA%\YADF\yadf.ini ONLY when
  // the policy asks for it AND the profile being edited IS the F profile, so
  // the F shortcut / CLI default (which read the standard file) reflect these
  // values even if F points at a custom-named file. When editing R (or any
  // non-F profile), do NOT mirror -- that would clobber the F/standard file
  // with R's values. Skip when the edited file already IS the standard file
  // (copying a file onto itself raises). Best-effort: a copy failure must not
  // lose the values already written to FCurrentIni.
  if not FPolicy.MirrorF then
    Exit;
  if not SameFileName(TPath.GetFullPath(FCurrentIni), TPath.GetFullPath(ResolveProfileIniPath(FProfiles.F))) then
    Exit; // editing a non-F profile -> nothing to mirror
  Shared:= SharedAppDataIniPath;
  // Never clobber ANOTHER profile: with F pointing at a custom file and R
  // assigned to yadf.ini itself, mirroring F onto the standard file would
  // silently overwrite R's saved values. The R shortcut reads that file
  // directly, so it must win over the convenience mirror.
  if (FProfiles.R <> '') and SameFileName(TPath.GetFullPath(Shared), TPath.GetFullPath(ResolveProfileIniPath(FProfiles.R))) then
    Exit;
  if not SameFileName(TPath.GetFullPath(FCurrentIni), TPath.GetFullPath(Shared)) then
  try
    TFile.Copy(FCurrentIni, Shared, True);
  except
    // A read-only or locked standard file is non-fatal: the F profile itself
    // is saved (FCurrentIni), so the next open and any profile-F consumer
    // still read the correct values.
  end;
end; // procedure

procedure TYadfOptionsFrame.SaveCurrentProfile;
begin
  // AutoSave write of the edited profile. A failed write (locked/read-only
  // file) must not raise into a VCL event handler; report it via the status
  // line instead.
  try
    SaveOptionsToIni(FOpts, FCurrentIni);
    MirrorFProfile;
    DoIniStatus('  (saved)');
  except
    on E: Exception do
      DoIniStatus('  (save failed: ' + E.Message + ')');
  end;
end; // procedure

procedure TYadfOptionsFrame.OptionChanged(Sender: TObject);
var
  T  : TArray<TOptInfo>;
  idx: Integer         ;
begin
  // A control changed. Ignore programmatic population (OptionsToControls sets
  // FUpdating), otherwise each of ~40 writes would pull+reformat. Pull the
  // live control values into FOpts and queue the DEBOUNCED work: the autosave
  // (if the policy autosaves) and the preview refresh -- unless the changed
  // option cannot alter the preview (AffectsPreview=False). Debouncing the
  // save matters twice over: a TSpinEdit fires OnChange per keystroke, so an
  // immediate save would persist the transient mid-edit value (deleting "180"
  // to type "120" briefly reads 0 -> MaxLen=0 on disk) AND write+mirror the
  // INI three times for one number.
  if FUpdating then
    Exit;
  ControlsToOptions;
  if FPolicy.AutoSave then
    FPendingSave:= True;
  T             := OptionTable;
  idx:= TControl(Sender).Tag;
  if not ((idx >= 0) and (idx <= High(T)) and not T[idx].AffectsPreview) then
    FPendingReformat:= True;
  if FPendingSave or FPendingReformat then
  begin
    FReformatTmr.Enabled:= False; // debounce
    FReformatTmr.Enabled:= True;
  end;
end; // procedure

procedure TYadfOptionsFrame.Commit;
begin
  // Read-modify-write the profile CURRENTLY being edited: re-read the record
  // fresh so any field NOT surfaced as a control survives, apply this frame's
  // controls, and write it back through the shared OptionTable serializer
  // (comments in the template are preserved). Then mirror per policy.
  // GUARDED: Commit is invoked from the IDE's OTA DialogClosed callback -- a
  // read-only/locked profile file must report via the status sink, never
  // raise into the IDE's dialog dispatch.
  try
    FOpts:= LoadOptionsFromIni(FCurrentIni);
    ControlsToOptions;
    SaveOptionsToIni(FOpts, FCurrentIni);
    MirrorFProfile;
    DoIniStatus('  (saved)');
  except
    on E: Exception do
      DoIniStatus('  (save failed: ' + E.Message + ')');
  end;
end; // procedure

procedure TYadfOptionsFrame.LoadOptionsFromFile(const APath: string);
begin
  FOpts:= LoadOptionsFromIni(APath);
  OptionsToControls;
  if FPolicy.AutoSave then
    SaveCurrentProfile;
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
  if FPolicy.AutoSave then
    SaveCurrentProfile;
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
  if (i >= 0) and (i <= High(AFiles)) then
    Result:= AFiles[i];
end;

procedure TYadfOptionsFrame.RefreshProfileList;
var
  Files: TArray<string>;
  Dir  : string        ;
  Name : string        ;
  Badge: string        ;
  Cur  : string        ;
  i    : Integer       ;
  Sel  : Integer       ;
begin
  // Enumerate ProfilesDir\*.ini (skip the profiles.ini mapping file), badge
  // the F/R rows, rebuild the index-aligned FProfileFiles, and re-select the
  // row matching the profile now being edited.
  Dir:= ProfilesDir;
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);
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
      if SameText(Name, 'profiles.ini') then Continue; // mapping file, not a profile
      if SameText(Name, FProfiles.F) then
        Badge:= '[F]  '
      else if SameText(Name, FProfiles.R) then
        Badge:= '[R]  '
      else
        Badge:= '      ';
      FProfileList.Items.Add(Badge + Name);
      SetLength(FProfileFiles, Length(FProfileFiles) + 1);
      FProfileFiles[High(FProfileFiles)]:= Name;
      if SameText(Name, Cur) then
        Sel:= High(FProfileFiles);
    end; // for
  finally
    FProfileList.Items.EndUpdate;
  end; // try
  if Sel >= 0 then
    FProfileList.ItemIndex:= Sel;
  FEditingLbl.Caption:= 'Editing: ' + Cur;
end; // procedure

procedure TYadfOptionsFrame.SwitchEditTo(const AIniFile: string);
var
  Path: string;
begin
  // Switch which profile the option controls edit. FLUSH the current profile's
  // values first so clicking another row never silently discards edits: under
  // AutoSave this rewrites the bytes already on disk (harmless); under the
  // OK-commit policy it is the documented profile-actions-are-live semantic.
  // The yadf.ini MIRROR however runs here only under AutoSave: on the IDE page
  // (commit-on-OK) the standard file must change on OK alone -- mirroring on a
  // mere row click would propagate edits that Cancel then cannot undo.
  // I/O is guarded: this runs inside a VCL OnClick (in the IDE process for
  // the options page) and a locked profile file must not raise into it.
  Path:= ResolveProfileIniPath(AIniFile);
  if (Path = '') or SameFileName(Path, FCurrentIni) then
    Exit;
  ControlsToOptions;
  try
    SaveOptionsToIni(FOpts, FCurrentIni); // flush current profile before leaving
    FPendingSave:= False; // queued autosave now redundant
    if FPolicy.AutoSave then
      MirrorFProfile;
  except
    on E: Exception do
      DoIniStatus('  (save failed: ' + E.Message + ')');
  end;
  FCurrentIni:= Path;
  EnsureIniExists(FCurrentIni);
  try
    FOpts:= LoadOptionsFromIni(FCurrentIni);
  except
    on E: Exception do
    begin
      FOpts:= DefaultOptions;
      DoIniStatus('  (load failed: ' + E.Message + ' -- showing defaults)');
    end;
  end;
  OptionsToControls;
  FEditingLbl.Caption:= 'Editing: ' + ExtractFileName(FCurrentIni);
  DoIniStatus('');
  Reformat;
end; // procedure

procedure TYadfOptionsFrame.ProfileListClick(Sender: TObject);
var
  Name: string;
begin
  // Single-click a row -> edit THAT profile (SwitchEditTo flushes the current
  // one first). No-op when the row is already the one being edited.
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name <> '' then
    SwitchEditTo(Name);
end;

procedure TYadfOptionsFrame.AssignShortcut(AWhich: Char);
var
  Name: string;
begin
  // Assign the selected profile to F or R. Saved immediately; under the IDE's
  // OK-commit policy the dialog OK/Cancel governs only the option VALUES, not
  // the F/R mapping (documented in the page remarks).
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name = '' then
    Exit;
  if AWhich = 'F' then
    FProfiles.F:= Name
  else
    FProfiles.R:= Name;
  SaveProfiles(FProfiles);
  RefreshProfileList;
end; // procedure

procedure TYadfOptionsFrame.UnassignSelected;
var
  Name: string;
begin
  // Clear the selected profile's F/R assignment. F must always resolve to a
  // file (the CLI + shortcut need one), so unassigning F resets it to the
  // default 'yadf.ini' rather than leaving it blank; R may be cleared outright.
  Name:= SelectedProfile(FProfileList, FProfileFiles);
  if Name = '' then
    Exit;
  if SameText(FProfiles.R, Name) then
    FProfiles.R:= ''
  else if SameText(FProfiles.F, Name) then
    FProfiles.F:= 'yadf.ini';
  SaveProfiles(FProfiles);
  RefreshProfileList;
end; // procedure

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

procedure TYadfOptionsFrame.ProfileListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Keyboard mirror of the button bar: highlight a row, press F / R to assign
  // the shortcut, Del to unassign.
  case Key of
    Ord('F') : begin AssignShortcut('F'); Key:= 0; end;
    Ord('R') : begin AssignShortcut('R'); Key:= 0; end;
    VK_DELETE: begin UnassignSelected; Key:= 0; end   ;
  end;
end;

procedure TYadfOptionsFrame.NewProfileClick(Sender: TObject);
var
  Nm      : string ;
  FileName: string ;
  Path    : string ;
  k       : Integer;
begin
  // Create a new yadf-<name>.ini seeded with the CURRENT settings, then switch
  // to editing it. Sanitise the name so it is a legal single-segment file name.
  Nm:= '';
  if not InputQuery('New profile', 'Profile name (creates yadf-<name>.ini):', Nm) then
    Exit;
  Nm:= Trim(Nm);
  if Nm = '' then
    Exit;
  for k:= 1 to Length(Nm) do
    if CharInSet(Nm[k], ['\', '/', ':', '*', '?', '"', '<', '>', '|', ' ']) then
      Nm[k]:= '-';
  FileName:= 'yadf-' + Nm + '.ini';
  Path:= ResolveProfileIniPath(FileName);
  if FileExists(Path) then
  begin
    if MessageDlg(FileName + ' already exists. Edit it instead?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end
  else
  begin
    ControlsToOptions;
    SaveOptionsToIni(FOpts, Path); // seed the new profile with current settings
  end;
  SwitchEditTo(FileName);
  RefreshProfileList;
end; // procedure

{ ==================== preview ==================== }

procedure TYadfOptionsFrame.Reformat;
begin
  // Render the result memo from the current source + FOpts. A malformed paste
  // can raise inside FormatSource (DelphiAST lexer/parser); show it in the
  // result memo rather than letting it escape into the host dialog.
  if FResult = nil then
    Exit;
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
end; // procedure

procedure TYadfOptionsFrame.SourceChanged(Sender: TObject);
begin
  FPendingReformat:= True;
  FReformatTmr.Enabled:= False; // debounce
  FReformatTmr.Enabled:= True;
end;

procedure TYadfOptionsFrame.ReformatTimer(Sender: TObject);
begin
  // The single debounce tick runs whatever was queued: the autosave first
  // (so a save error shows in the status line even when no reformat is due),
  // then the preview refresh.
  FReformatTmr.Enabled:= False;
  if FPendingSave then
  begin
    FPendingSave:= False;
    SaveCurrentProfile;
  end;
  if FPendingReformat then
  begin
    FPendingReformat:= False;
    Reformat;
  end;
end; // procedure

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
  FALLBACK = 'unit Sample;'#13#10 + 'interface'#13#10 + 'type TFoo=record A:Integer;B:string; end;'#13#10 + 'const K=1;LongName=2;'#13#10 + 'procedure Go(X:Integer);'#13#10 +
  'implementation'#13#10 + 'procedure Go(X:Integer);begin if X>0 then Inc(X) else Dec(X); end;'#13#10 + 'end.'#13#10;
var
  Base: string        ;
  Cand: TArray<string>;
  i   : Integer       ;
begin
  // Try a bundled Demo\Sample.pas relative to a few plausible roots -- the
  // host module's dir (YADFSetup.exe or YADFOT.bpl) and its build-tree
  // parents. If none is present, fall back to the built-in snippet above.
  Base:= ExtractFilePath(GetModuleName(HInstance));
  Cand:= [ Base + 'Sample.pas', Base + 'Demo\Sample.pas', Base + '..\..\..\Demo\Sample.pas' ];
  for i:= 0 to High(Cand) do
    if TFile.Exists(Cand[i]) then
    begin
      FSource.Lines.LoadFromFile(Cand[i]);
      FSourceName.Caption:= 'file: ' + ExtractFileName(Cand[i]);
      Exit;
    end;
  FSource    .Text   := FALLBACK;
  FSourceName.Caption:= 'sample (built-in)';
end; // procedure

{ ==================== lifecycle ==================== }

procedure TYadfOptionsFrame.Load;
begin
  // Start editing the F profile (the file YADFSetup + the F shortcut + the CLI
  // default all resolve). Then populate the profiles list so the user can see
  // F/R and switch to any other profile. GUARDED: Load runs from the IDE's
  // OTA FrameCreated callback; unreadable profile files fall back to the
  // compiled defaults (reported via the status sink) instead of raising into
  // the IDE's options-dialog construction.
  FProfiles:= LoadProfiles;
  FCurrentIni:= ResolveProfileIniPath(FProfiles.F);
  if FCurrentIni = '' then
    FCurrentIni:= SharedAppDataIniPath;
  EnsureIniExists(FCurrentIni);
  try
    FOpts:= LoadOptionsFromIni(FCurrentIni);
  except
    on E: Exception do
    begin
      FOpts:= DefaultOptions;
      DoIniStatus('  (load failed: ' + E.Message + ' -- showing defaults)');
    end;
  end;
  OptionsToControls; // FUpdating guards the ~40 OnChange fires here
  RefreshProfileList; // list all profiles, badge F/R, select the current one
  LoadSample; // populate the source memo
  Reformat; // render the first before/after view
  DoIniStatus('');
end; // procedure

end.
