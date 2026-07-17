program YADFSetup;

uses
  Vcl.Forms,
  uYADFSetupMain in 'uYADFSetupMain.pas' {frmMain},
  YADF.OptionsFrame in 'YADF.OptionsFrame.pas' {YadfOptionsFrame: TFrame},
  YADF.Tokens in 'YADF.Tokens.pas',
  YADF.Options in 'YADF.Options.pas',
  YADF.Groups in 'YADF.Groups.pas',
  YADF.Guard in 'YADF.Guard.pas',
  YADF.LineScan in 'YADF.LineScan.pas',
  YADF.Layout in 'YADF.Layout.pas',
  YADF.Debug in 'YADF.Debug.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
