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

unit YADF.Options;

interface

type
  TYadfEncoding = (encANSI, encUTF8BOM, encUTF16BOM);

  TYadfOptions = record
    MaxLen             : Integer;
    Indent             : Integer;
    TabWidth           : Integer;
    MarkUnclosed       : Boolean;
    LabelLongBlocks    : Boolean;
    LabelMinLines      : Integer;
    MaxBlankLines      : Integer;
    TrimTrailing       : Boolean;
    ReflowLines        : Boolean;
    LowercaseKeywords  : Boolean;
    UpperHexNumbers    : Boolean;
    UpperDirectives    : Boolean;
    FirstOccCasing     : Boolean;
    BlanksBeforeSection: Integer;
    BlanksBeforeMethod : Integer;
    BlanksBeforeType   : Integer;
    AssignNoSpaceBefore: Boolean;
    AssignSpaceAfter   : Boolean;
    AlignConstEquals   : Boolean;
    AlignTypeColon     : Boolean;
    AlignSmartAssign   : Boolean;
    AlignMaxColumn     : Integer;
    AlignMatchingShapes: Boolean;
    AlignShapeMinAnchors: Integer;
    AlignCommentMaxShift: Integer;
    UsesAlwaysBreak    : Boolean;
    Backup             : Boolean;
    BackupDir          : string;
    ResultDir          : string;
    Encoding           : TYadfEncoding;
    Logging            : Boolean;
  end; // record

function DefaultOptions: TYadfOptions;

implementation

function DefaultOptions: TYadfOptions;
begin
  Result.MaxLen             := 180    ;
  Result.Indent             := 2      ;
  Result.TabWidth           := 4      ;
  Result.MarkUnclosed       := False  ;
  Result.LabelLongBlocks    := True   ;
  Result.LabelMinLines      := 15     ;
  Result.MaxBlankLines      := 1      ;
  Result.TrimTrailing       := True   ;
  Result.ReflowLines        := True   ;
  Result.LowercaseKeywords  := True   ;
  Result.UpperHexNumbers    := True   ;
  Result.UpperDirectives    := True   ;
  Result.FirstOccCasing     := True   ;
  Result.BlanksBeforeSection:= 0      ;
  Result.BlanksBeforeMethod := 0      ;
  Result.BlanksBeforeType   := 0      ;
  Result.AssignNoSpaceBefore:= True   ;
  Result.AssignSpaceAfter   := True   ;
  Result.AlignConstEquals   := True   ;
  Result.AlignTypeColon     := True   ;
  Result.AlignSmartAssign   := True   ;
  Result.AlignMaxColumn     := 140    ;
  Result.AlignMatchingShapes := True  ;
  Result.AlignShapeMinAnchors := 3    ;
  Result.AlignCommentMaxShift := 7    ;
  Result.UsesAlwaysBreak    := True   ;
  Result.Backup             := False  ;
  Result.BackupDir          := ''     ;
  Result.ResultDir          := ''     ;
  Result.Encoding           := encANSI;
  Result.Logging            := False  ;
end; // function

end.
