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
  i: Integer;
  Bad: string;
begin
  T := OptionTable;
  Check('descriptor count == record field count', Length(T) = EXPECTED_OPTION_COUNT);
  // Descriptor invariant: every okEnum row must carry its value list (the UI
  // combos are built from EnumValues; an empty list would render an empty
  // combo), and non-enum rows must not smuggle one in.
  Bad := '';
  for i := 0 to High(T) do
    if (T[i].Kind = okEnum) <> (Length(T[i].EnumValues) > 0) then
      Bad := Bad + ' ' + T[i].Ident;
  Check('EnumValues set exactly on okEnum rows (bad:' + Bad + ')', Bad = '');
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

// LooksLikeUtf8 drives BOM-less encoding detection in the CLI and the wizard:
// valid multi-byte UTF-8 must be promoted from the ANSI fallback; everything
// ambiguous or invalid must stay ANSI.
procedure TestLooksLikeUtf8;
begin
  Check('utf8: 2-byte seq accepted',        LooksLikeUtf8(TBytes.Create($41, $C3, $A9, $42)));
  Check('utf8: 3-byte euro accepted',       LooksLikeUtf8(TBytes.Create($E2, $82, $AC)));
  Check('utf8: 4-byte emoji accepted',      LooksLikeUtf8(TBytes.Create($F0, $9F, $98, $80)));
  Check('utf8: pure ascii rejected',        not LooksLikeUtf8(TBytes.Create($41, $42)));
  Check('utf8: empty rejected',             not LooksLikeUtf8(nil));
  Check('utf8: lone cp1252 byte rejected',  not LooksLikeUtf8(TBytes.Create($E9, $41, $42)));
  Check('utf8: truncated tail rejected',    not LooksLikeUtf8(TBytes.Create($41, $C3)));
  Check('utf8: stray continuation rejected',not LooksLikeUtf8(TBytes.Create($80)));
  Check('utf8: overlong C0 AF rejected',    not LooksLikeUtf8(TBytes.Create($C0, $AF)));
  Check('utf8: surrogate ED A0 80 rejected',not LooksLikeUtf8(TBytes.Create($ED, $A0, $80)));
  Check('utf8: F5 lead rejected',           not LooksLikeUtf8(TBytes.Create($F5, $80, $80, $80)));
end;

begin
  try
    TestDescriptorCompleteness;
    TestRoundTrip;
    TestCommentPreservation;
    TestHelpCoversAll;
    TestLooksLikeUtf8;
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
