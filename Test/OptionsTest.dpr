program OptionsTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Variants,
  YADF.Options in '..\YADF.Options.pas';

var
  GFailures: Integer = 0;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then
    Writeln('ok   - ', AName)
  else
  begin
    Writeln('FAIL - ', AName);
    Inc(GFailures);
  end;
end;

// Count of fields in TYadfOptions; the descriptor table must match exactly.
const
  EXPECTED_OPTION_COUNT = 40;

procedure TestDescriptorCompleteness;
var
  T: TArray<TOptInfo>;
begin
  T := OptionTable;
  Check('descriptor count == record field count', Length(T) = EXPECTED_OPTION_COUNT);
end;

procedure TestRoundTrip;
var
  A, B: TYadfOptions;
  Path: string;
  T: TArray<TOptInfo>;
  i: Integer;
  Mism: string;
begin
  A := DefaultOptions;
  // perturb a few fields so we are not just re-reading defaults
  A.MaxLen := 99;
  A.Indent := 7;
  A.LowercaseKeywords := False;
  A.BackupDir := 'C:\tmp\bak';
  A.Encoding := encUTF8BOM;
  Path := TPath.Combine(TPath.GetTempPath, 'yadf_roundtrip_test.ini');
  if TFile.Exists(Path) then TFile.Delete(Path);
  SaveOptionsToIni(A, Path);
  B := LoadOptionsFromIni(Path);
  T := OptionTable;
  Mism := '';
  for i := 0 to High(T) do
    if VarToStr(T[i].GetVal(A)) <> VarToStr(T[i].GetVal(B)) then
      Mism := Mism + ' ' + T[i].Ident;
  Check('round-trip identity for all fields (mismatch:' + Mism + ')', Mism = '');
  TFile.Delete(Path);
end;

procedure TestCommentPreservation;
var
  A: TYadfOptions;
  Path: string;
  S: string;
begin
  A := DefaultOptions;
  Path := TPath.Combine(TPath.GetTempPath, 'yadf_comments_test.ini');
  if TFile.Exists(Path) then TFile.Delete(Path);
  SaveOptionsToIni(A, Path);  // should ensure template (with ';' comments) first
  S := TFile.ReadAllText(Path, TEncoding.ANSI);
  Check('saved ini keeps ; comment lines', S.Contains(';'));
  Check('saved ini has [Format] section', S.Contains('[Format]'));
  TFile.Delete(Path);
end;

procedure TestHelpCoversAll;
var
  H: string;
  T: TArray<TOptInfo>;
  i: Integer;
  Missing: string;
begin
  H := OptionsHelpText;
  T := OptionTable;
  Missing := '';
  for i := 0 to High(T) do
    if not H.Contains(T[i].Ident) then
      Missing := Missing + ' ' + T[i].Ident;
  Check('help text covers every option (missing:' + Missing + ')', Missing = '');
end;

begin
  try
    TestDescriptorCompleteness;
    TestRoundTrip;
    TestCommentPreservation;
    TestHelpCoversAll;
    Writeln('');
    if GFailures = 0 then
      Writeln('ALL PASS')
    else
      Writeln(Format('%d FAILURE(S)', [GFailures]));
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Inc(GFailures);
    end;
  end;
  ExitCode := GFailures;
end.
