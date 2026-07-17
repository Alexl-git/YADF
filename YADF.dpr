{
  YADF -- Yet Another Delphi Formatter

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Uses lexer/parser code from DelphiAST:
  Copyright (c) 2014-2020 Roman Yankovsky (roman@yankovsky.me) et al
  https://github.com/RomanYankovsky/DelphiAST
}

program YADF;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  YADF.Tokens in 'YADF.Tokens.pas',
  YADF.Options in 'YADF.Options.pas',
  YADF.Groups in 'YADF.Groups.pas',
  YADF.Guard in 'YADF.Guard.pas',
  YADF.LineScan in 'YADF.LineScan.pas',
  YADF.Layout in 'YADF.Layout.pas',
  YADF.Debug in 'YADF.Debug.pas',
  YadfMain in 'YadfMain.pas';

begin
  try
    RunYadf;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
