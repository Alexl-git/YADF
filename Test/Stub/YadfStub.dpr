program YadfStub;

{ Copy-only stand-in for YADF.exe, used by Test\prove_harness_red.ps1 (via
  $env:YADF_TEST_EXE) to prove the suites go RED against a no-op formatter.
  --o / --of copies the input bytes, --stdout writes them, an in-place run
  changes nothing, --check / --check-dir prints PASS. With the environment
  variable STUB_ANSI_STDOUT=1 the --stdout bytes are re-encoded to the ANSI
  code page (the pre-1.0.20 lossy path of review #5). Never shipped. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
, System.IOUtils
, Winapi.Windows
;

var
  Arg       : string ;
  Bytes     : TBytes ;
  CheckMode : Boolean;
  I         : Integer;
  OutFile   : string ;
  Src       : string ;
  StdoutMode: Boolean;
  Written   : DWORD  ;
begin
  CheckMode:= False;
  StdoutMode:= False;
  I:= 1;
  while I <= ParamCount do
  begin
    Arg:= ParamStr(I);
    if (Arg = '--o') or (Arg = '--of') or (Arg = '--ini') then
    begin
      Inc(I);
      if Arg <> '--ini' then
        OutFile:= ParamStr(I);
    end
    else if Arg = '--stdout' then
      StdoutMode:= True
    else if (Arg = '--check') or (Arg = '--check-dir') then
      CheckMode:= True
    else if (Src = '') and not Arg.StartsWith('--') and FileExists(Arg) then
      Src:= Arg;
    Inc(I);
  end;
  if CheckMode then
  begin
    Writeln('PASS');
    Exit;
  end;
  if Src = '' then
    Exit;
  Bytes:= TFile.ReadAllBytes(Src);
  if StdoutMode then
  begin
    if GetEnvironmentVariable('STUB_ANSI_STDOUT') = '1' then
      Bytes:= TEncoding.ANSI.GetBytes(TEncoding.UTF8.GetString(Bytes));
    if Length(Bytes) > 0 then
      Win32Check(WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), Bytes[0], Length(Bytes), Written, nil));
  end
  else if OutFile <> '' then
    TFile.WriteAllBytes(OutFile, Bytes);
end.
