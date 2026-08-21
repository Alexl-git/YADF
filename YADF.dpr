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
  SimpleParser.Lexer in '..\DelphiAST\Source\SimpleParser\SimpleParser.Lexer.pas',
  SimpleParser.Lexer.Types in '..\DelphiAST\Source\SimpleParser\SimpleParser.Lexer.Types.pas',
  YADF.Tokens,
  YADF.Options,
  YADF.Groups,
  YADF.Guard,
  YADF.LineScan,
  YADF.Layout,
  YADF.Debug,
  YadfMain;

begin
  try
    RunYadf;
  except
    on E: EYadfUsage do
    begin
      Writeln(ErrOutput, E.Message);
      Writeln(ErrOutput, 'Run yadf --help for usage.');
      ExitCode := 2;
    end;
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
