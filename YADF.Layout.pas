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

unit YADF.Layout;

interface

uses
  YADF.Tokens
  , YADF.Options
  ;

function FormatSource(const ASource: string; const AOpts: TYadfOptions): string;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Math
  , System.Generics.Collections
  , System.Character
  , SimpleParser.Lexer
  , SimpleParser.Lexer.Types
  , YADF.Groups
  ;

function ColumnFromPre(const APre: string): Integer;
var
  i     : Integer;
  LastNL: Integer;
begin
  LastNL:= 0;
  for i:= Length(APre) downto 1 do if (APre[i] = #10) or (APre[i] = #13) then
  begin
    LastNL:= i;
    Break;
  end;
  Result:= Length(APre) - LastNL;
end;

function CollapseToSpace(const S: string): string;
var
  i    : Integer;
  InRun: Boolean;
  Sb   : TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    InRun:= False;
    for i:= 1 to Length(S) do
    begin
      if (S[i] = #9) or (S[i] = #10) or (S[i] = #13) or (S[i] = ' ') then
      begin
        if not InRun then
        begin
          Sb.Append(' ');
          InRun:= True;
        end;
      end
      else
      begin
        Sb.Append(S[i]);
        InRun:= False;
      end;
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

function NormalizeCRLF(const S: string): string;
begin
  Result:= StringReplace(S     , #13#10, #10   , [rfReplaceAll]);
  Result:= StringReplace(Result, #10   , #13#10, [rfReplaceAll]);
end;

function TrimTrailingWhitespace(const S: string): string;
var
  i    : Integer;
  Lines: TStringList;
  Out_ : TStringBuilder;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Out_.Append(TrimRight(Lines[i]));
        Out_.Append(#13#10);
      end;
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end;
  finally
    Lines.Free;
  end; // try
end; // function

function IsAllAlphabetic(const S: string): Boolean;
var
  i: Integer;
begin
  if S = '' then Exit(False);
  for i:= 1 to Length(S) do if not (((S[i] >= 'a') and (S[i] <= 'z')) or ((S[i] >= 'A') and (S[i] <= 'Z'))) then
    Exit(False);
  Result:= True;
end;

function UpperHexLiteral(const S: string): string;
var
  C: Char;
  i: Integer;
begin
  Result:= S;
  if (Length(Result) >= 2) and (Result[1] = '$') then
    for i:= 2 to Length(Result) do
  begin
    C:= Result[i];
    if (C >= 'a') and (C <= 'f') then
      Result[i]:= Chr(Ord(C) - 32);
  end
  else
    for i:= 1 to Length(Result) do if (Result[i] = 'e') then
    Result[i]:= 'E';
end;

function UpperDirectiveName(const S: string): string;
var
  C        : Char;
  i        : Integer;
  NameStart: Integer;
begin
  Result:= S;
  if (Length(Result) < 3) or (Result[1] <> '{') or (Result[2] <> '$') then Exit;
  NameStart:= 3        ;
  i        := NameStart;
  while (i <= Length(Result)) and (((Result[i] >= 'a') and (Result[i] <= 'z')) or ((Result[i] >= 'A') and (Result[i] <= 'Z'))) do
  begin
    C:= Result[i];
    if (C >= 'a') and (C <= 'z') then
      Result[i]:= Chr(Ord(C) - 32);
    Inc(i);
  end;
end;

procedure NormalizeAssignSpacing(const ATokens: TTokenList; const AOpts: TYadfOptions);
var
  i   : Integer;
  NewT: TToken;
  T   : TToken;
begin
  i:= 0;
  while i < ATokens.Count do
  begin
    if ATokens[i].Kind = ptAssign then
    begin
      if AOpts.AssignNoSpaceBefore then
      begin
        if (i > 0) and (ATokens[i - 1].Kind = ptSpace) then
        begin
          ATokens.Delete(i - 1);
          Dec(i);
        end;
      end;
      if AOpts.AssignSpaceAfter then
      begin
        if (i + 1 < ATokens.Count) then
        begin
          if ATokens[i + 1].Kind = ptSpace then
          begin
            T:= ATokens[i + 1];
            T.Text:= ' ';
            ATokens[i + 1]:= T;
          end
          else if ATokens[i + 1].Kind <> ptCRLF then
          begin
            NewT.Kind:= ptSpace  ;
            NewT.ExID:= ptUnknown;
            NewT.Text:= ' '      ;
            NewT.Pre := ''       ;
            NewT.Line:= ATokens[i].Line;
            NewT.Col:= 0;
            ATokens.Insert(i + 1, NewT);
          end;
        end; // if
      end; // if
    end; // if
    Inc(i);
  end; // while
end; // procedure

procedure ApplyCapitalization(const ATokens: TTokenList; const AOpts: TYadfOptions);
var
  Existing     : string;
  FirstMap     : TDictionary<string, string>;
  i            : Integer;
  IsLiteralKind: Boolean;
  Key          : string;
  T            : TToken;
begin
  if AOpts.LowercaseKeywords then
    for i:= 0 to ATokens.Count - 1 do
  begin
    T:= ATokens[i];
    IsLiteralKind:= T.Kind in [ptIdentifier, ptIntegerConst, ptFloat, ptStringConst, ptStringDQConst, ptAsciiChar, ptAnsiComment, ptBorComment, ptSlashesComment, ptCRLF, ptCRLFCo,
      ptSpace, ptNull, ptUnknown, ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect, ptIfEndDirect, ptDefineDirect,
      ptUndefDirect, ptIncludeDirect, ptResourceDirect, ptCompDirect, ptScopedEnumsDirect];
    if (not IsLiteralKind) and IsAllAlphabetic(T.Text) then
    begin
      T.Text:= LowerCase(T.Text);
      ATokens[i]:= T;
    end;
  end; // for

  if AOpts.UpperHexNumbers then
    for i:= 0 to ATokens.Count - 1 do
  begin
    T:= ATokens[i];
    if T.Kind in [ptIntegerConst, ptFloat] then
    begin
      T.Text:= UpperHexLiteral(T.Text);
      ATokens[i]:= T;
    end;
  end;

  if AOpts.UpperDirectives then
    for i:= 0 to ATokens.Count - 1 do
  begin
    T:= ATokens[i];
    if T.Kind in [ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect, ptIfEndDirect, ptDefineDirect, ptUndefDirect,
      ptIncludeDirect, ptResourceDirect, ptCompDirect, ptScopedEnumsDirect] then
    begin
      T.Text:= UpperDirectiveName(T.Text);
      ATokens[i]:= T;
    end;
  end; // for

  if AOpts.FirstOccCasing then
  begin
    FirstMap:= TDictionary<string, string>.Create;
    try
      for i:= 0 to ATokens.Count - 1 do
      begin
        T:= ATokens[i];
        if (T.Kind = ptIdentifier) and (T.Text <> '') then
        begin
          Key:= LowerCase(T.Text);
          if not FirstMap.TryGetValue(Key, Existing) then
            FirstMap.Add(Key, T.Text);
        end;
      end;
      for i:= 0 to ATokens.Count - 1 do
      begin
        T:= ATokens[i];
        if (T.Kind = ptIdentifier) and (T.Text <> '') then
        begin
          Key:= LowerCase(T.Text);
          if FirstMap.TryGetValue(Key, Existing) then
          if T.Text <> Existing then
          begin
            T.Text:= Existing;
            ATokens[i]:= T;
          end;
        end;
      end;
    finally
      FirstMap.Free;
    end; // try
  end; // if
end; // procedure

function DetabLeadingWhitespace(const S: string; ATabWidth: Integer): string;
var
  i    : Integer;
  j    : Integer;
  Line : string;
  Lines: TStringList;
  Out_ : TStringBuilder;
  Tab  : string;
begin
  if ATabWidth <= 0 then Exit(S);
  Tab:= StringOfChar(' ', ATabWidth);
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Line:= Lines[i];
        j:= 1;
        while (j <= Length(Line)) and ((Line[j] = ' ') or (Line[j] = #9)) do
        begin
          if Line[j] = #9 then
            Out_.Append(Tab)
          else
            Out_.Append(' ');
          Inc(j);
        end;
        Out_.Append(Copy(Line, j, MaxInt));
        Out_.Append(#13#10);
      end;
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // function

function JoinShortCaseAlts(const S: string; AMaxLen: Integer): string;
var
  Cur        : string;
  CurTrimmedR: string;
  i          : Integer;
  Joined     : string;
  Lines      : TStringList;
  Next       : string;
  NextTrim   : string;
  Out_       : TStringBuilder;

  function LeadingSpaces(const ALine: string): Integer;
  var
    k: Integer;
  begin
    Result:= 0;
    for k:= 1 to Length(ALine) do if ALine[k] = ' ' then Inc(Result)
    else Break;
  end;

  function EndsWithColon(const ALine: string): Boolean;
  begin
    Result:= (CurTrimmedR <> '') and (CurTrimmedR[Length(CurTrimmedR)] = ':');
  end;

  function NextStartsCompound(const ATrimmed: string): Boolean;
  var
    L: string;
  begin
    L:= LowerCase(ATrimmed);
    Result:= L.StartsWith('begin') or L.StartsWith('case') or L.StartsWith('try') or L.StartsWith('asm') or L.StartsWith('record');
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      i:= 0;
      while i < Lines.Count do
      begin
        Cur:= Lines[i];
        CurTrimmedR:= TrimRight(Cur);
        if (i + 1 < Lines.Count) and EndsWithColon(Cur) then
        begin
          Next:= Lines[i + 1];
          NextTrim:= Trim(Next);
          if (NextTrim <> '') and (LeadingSpaces(Next) > LeadingSpaces(Cur)) and not NextStartsCompound(NextTrim) then
          begin
            Joined:= CurTrimmedR + ' ' + NextTrim;
            if Length(Joined) <= AMaxLen then
            begin
              Out_.Append(Joined);
              Out_.Append(#13#10);
              Inc(i, 2);
              Continue;
            end;
          end;
        end; // if
        Out_.Append(Cur);
        Out_.Append(#13#10);
        Inc(i);
      end; // while
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // begin

function FindAnchorAtTopLevel(const ALine: string; const AAnchor: string): Integer;
var
  Depth   : Integer;
  i       : Integer;
  InBrace : Boolean;
  InPar   : Boolean;
  InString: Boolean;
begin
  Result  := 0    ;
  InString:= False;
  InBrace := False;
  InPar   := False;
  Depth   := 0    ;
  i       := 1    ;
  while i <= Length(ALine) - Length(AAnchor) + 1 do
  begin
    if InBrace then
    begin
      if ALine[i] = '}' then InBrace:= False;
      Inc(i); Continue;
    end;
    if InPar then
    begin
      if (i + 1 <= Length(ALine)) and (ALine[i] = '*') and (ALine[i + 1] = ')') then
      begin
        InPar:= False;
        Inc(i, 2); Continue;
      end;
      Inc(i); Continue;
    end;
    if InString then
    begin
      if ALine[i] = '''' then
      begin
        if (i + 1 <= Length(ALine)) and (ALine[i + 1] = '''') then Inc(i, 2)
        else begin InString:= False; Inc(i); end;
      end
      else
        Inc(i);
      Continue;
    end;
    if ALine[i] = '''' then begin InString:= True; Inc(i); Continue; end;
    if ALine[i] = '{'  then begin InBrace := True; Inc(i); Continue; end;
    if (i + 1 <= Length(ALine)) and (ALine[i] = '/') and (ALine[i + 1] = '/') then
      Exit(0);
    if (i + 1 <= Length(ALine)) and (ALine[i] = '(') and (ALine[i + 1] = '*') then
    begin
      InPar:= True;
      Inc(i, 2); Continue;
    end;
    if CharInSet(ALine[i], ['(', '[']) then begin Inc(Depth); Inc(i); Continue; end;
    if CharInSet(ALine[i], [')', ']']) then begin Dec(Depth); Inc(i); Continue; end;
    if (Depth = 0) and (Copy(ALine, i, Length(AAnchor)) = AAnchor) then
    begin
      if AAnchor = ':' then
      if (i + 1 <= Length(ALine)) and (ALine[i + 1] = '=') then
      begin
        Inc(i, 2); Continue;
      end;
      if AAnchor = '=' then
      if (i > 1) and (ALine[i - 1] = ':') then
      begin
        Inc(i); Continue;
      end;
      Exit(i);
    end;
    Inc(i);
  end; // while
end; // function

function StartsConstBlock(const ALine: string): Boolean;
var
  T: string;
begin
  T:= TrimLeft(ALine);
  Result:= SameText(Copy(T, 1, 5), 'const') and ((Length(T) = 5) or (T[6] = ' ') or (T[6] = #9) or (T[6] = #13));
end;

function StartsBlockBoundary(const ALine: string): Boolean;
var
  T: string;

  function StartsKW(const AKeyword: string): Boolean;
  var
    L: Integer;
    C: Char;
  begin
    L:= Length(AKeyword);
    if Length(T) < L then Exit(False);
    if not SameText(Copy(T, 1, L), AKeyword) then Exit(False);
    if Length(T) = L then Exit(True);
    C:= T[L + 1];
    Result:= not (((C >= 'a') and (C <= 'z')) or
                  ((C >= 'A') and (C <= 'Z')) or
                  ((C >= '0') and (C <= '9')) or
                  (C = '_'));
  end;

begin
  T:= TrimLeft(ALine);
  if T = '' then Exit(True);
  if StartsKW('begin') then Exit(True);
  if StartsKW('end') then Exit(True);
  if StartsKW('type') then Exit(True);
  if StartsKW('var') then Exit(True);
  if StartsKW('const') then Exit(True);
  if StartsKW('procedure') then Exit(True);
  if StartsKW('function') then Exit(True);
  if StartsKW('constructor') then Exit(True);
  if StartsKW('destructor') then Exit(True);
  if StartsKW('interface') then Exit(True);
  if StartsKW('implementation') then Exit(True);
  Result:= False;
end; // function

function CollapseInteriorSpacesInLine(const ALine: string): string;
var
  Body   : string;
  i      : Integer;
  Lead   : string;
  LeadLen: Integer;
  Sb     : TStringBuilder;
  T      : TToken;
  Tokens : TTokenList;
begin
  LeadLen:= 0;
  while (LeadLen < Length(ALine)) and (ALine[LeadLen + 1] = ' ') do Inc(LeadLen);
  Lead:= Copy(ALine, 1, LeadLen);
  Body:= Copy(ALine, LeadLen + 1, MaxInt);
  if Body = '' then Exit(ALine);
  Tokens:= LoadTokensFromString(Body);
  Sb:= TStringBuilder.Create;
  try
    Sb.Append(Lead);
    for i:= 0 to Tokens.Count - 1 do
    begin
      T:= Tokens[i];
      Sb.Append(T.Pre);
      if (T.Kind = ptSpace) and (Length(T.Text) > 1) then
        Sb.Append(' ')
      else
        Sb.Append(T.Text);
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
    Tokens.Free;
  end; // try
end; // function

function CollapseInteriorSpaces(const S: string): string;
var
  i    : Integer;
  Lines: TStringList;
  Out_ : TStringBuilder;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Out_.Append(CollapseInteriorSpacesInLine(Lines[i]));
        Out_.Append(#13#10);
      end;
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end;
  finally
    Lines.Free;
  end; // try
end; // function

function AlignByAnchor(const S, AAnchor: string; AMaxColumn: Integer): string;
var
  Anchors : TArray<Integer>;
  i       : Integer;
  j       : Integer;
  Line    : string;
  Lines   : TStringList;
  MaxPos  : Integer;
  Out_    : TStringBuilder;
  Pad     : Integer;
  StartIdx: Integer;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    SetLength(Anchors, Lines.Count);
    for i:= 0 to Lines.Count - 1 do Anchors[i]:= FindAnchorAtTopLevel(Lines[i], AAnchor);
    Out_:= TStringBuilder.Create;
    try
      i:= 0;
      while i < Lines.Count do
      begin
        if (Anchors[i] = 0) or StartsBlockBoundary(Lines[i]) then
        begin
          Out_.Append(Lines[i]);
          Out_.Append(#13#10);
          Inc(i);
          Continue;
        end;
        StartIdx:= i;
        MaxPos:= Anchors[i];
        j:= i + 1;
        while (j < Lines.Count) and (Anchors[j] > 0) and not StartsBlockBoundary(Lines[j]) do
        begin
          if Anchors[j] > MaxPos then MaxPos:= Anchors[j];
          Inc(j);
        end;
        if (j - StartIdx >= 2) and (MaxPos <= AMaxColumn) then
        begin
          for i:= StartIdx to j - 1 do
          begin
            Pad:= MaxPos - Anchors[i];
            if Pad > 0 then
            begin
              Line:= Copy(Lines[i], 1, Anchors[i] - 1) + StringOfChar(' ', Pad) + Copy(Lines[i], Anchors[i], MaxInt);
              Out_.Append(Line);
            end
            else
              Out_.Append(Lines[i]);
            Out_.Append(#13#10);
          end;
        end // if
        else
          for i:= StartIdx to j - 1 do
        begin
          Out_.Append(Lines[i]);
          Out_.Append(#13#10);
        end;
        i:= j;
      end; // while
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // function

type
  TLineShape = record
    Shape    : TArray<TptTokenKind>;
    Cols     : TArray<Integer>;
    HasAssign: Boolean;
  end;

function ComputeLineShape(const ALine: string): TLineShape;
var
  Cols : TList<Integer>;
  Lex  : TmwPasLex;
  Shape: TList<TptTokenKind>;
  Tok  : TptTokenKind;
begin
  Result.HasAssign:= False;
  SetLength(Result.Shape, 0);
  SetLength(Result.Cols, 0);
  Lex:= TmwPasLex.Create;
  Shape:= TList<TptTokenKind>.Create;
  Cols := TList<Integer     >.Create;
  try
    Lex.Origin:= ALine;
    while Lex.TokenID <> ptNull do
    begin
      Tok:= Lex.TokenID;
      if Tok = ptAssign then Result.HasAssign:= True;
      if not (Tok in [ ptSpace, ptCRLF, ptCRLFCo, ptIdentifier, ptStringConst, ptStringDQConst, ptIntegerConst, ptFloat, ptAsciiChar, ptAnsiComment, ptBorComment,
          ptSlashesComment]) then
      begin
        Shape.Add(Tok);
        Cols.Add(Lex.PosXY.X);
      end;
      Lex.Next;
    end;
    Result.Shape:= Shape.ToArray;
    Result.Cols := Cols .ToArray;
  finally
    Cols.Free;
    Shape.Free;
    Lex.Free;
  end; // try
end; // function

function ShapesMatch(const A, B: TArray<TptTokenKind>): Boolean;
var
  i: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for i:= 0 to High(A) do if A[i] <> B[i] then Exit(False);
  Result:= True;
end;

function SmartAlignAssignments(const S: string; AMaxCol: Integer): string;
var
  AnyOver : Boolean;
  i       : Integer;
  Info    : TArray<TLineShape>;
  j       : Integer;
  k       : Integer;
  Lines   : TStringList;
  MaxCol  : Integer;
  Out_    : TStringBuilder;
  Pad     : Integer;
  WorkCols: TArray<TArray<Integer>>;
  WorkLine: TArray<string>;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    SetLength(Info, Lines.Count);
    for i:= 0 to Lines.Count - 1 do Info[i]:= ComputeLineShape(Lines[i]);

    Out_:= TStringBuilder.Create;
    try
      i:= 0;
      while i < Lines.Count do
      begin
        if not Info[i].HasAssign then
        begin
          Out_.Append(Lines[i]);
          Out_.Append(#13#10);
          Inc(i);
          Continue;
        end;
        j:= i + 1;
        while (j < Lines.Count) and Info[j].HasAssign and ShapesMatch(Info[i].Shape, Info[j].Shape) do Inc(j);
        if (j - i >= 2) and (Length(Info[i].Shape) > 0) then
        begin
          SetLength(WorkLine, j - i);
          SetLength(WorkCols, j - i);
          for k:= 0 to (j - i) - 1 do
          begin
            WorkLine[k]:= Lines[i + k];
            WorkCols[k]:= Copy(Info[i + k].Cols, 0, Length(Info[i + k].Cols));
          end;

          AnyOver:= False;
          for k:= 0 to Length(Info[i].Shape) - 1 do
          begin
            MaxCol:= 0;
            for var L: Integer:= 0 to (j - i) - 1 do if WorkCols[L][k] > MaxCol then
              MaxCol:= WorkCols[L][k];
            if MaxCol > AMaxCol then
            begin
              AnyOver:= True;
              Break;
            end;
            for var L: Integer:= 0 to (j - i) - 1 do
            begin
              Pad:= MaxCol - WorkCols[L][k];
              if Pad > 0 then
              begin
                WorkLine[L]:= Copy(WorkLine[L], 1, WorkCols[L][k] - 1) + StringOfChar(' ', Pad) + Copy(WorkLine[L], WorkCols[L][k], MaxInt);
                for var M: Integer:= k to High(WorkCols[L]) do WorkCols[L][M]:= WorkCols[L][M] + Pad;
              end;
            end;
          end; // for

          if AnyOver then
          begin
            for k:= i to j - 1 do
            begin
              Out_.Append(Lines[k]);
              Out_.Append(#13#10);
            end;
          end
          else
            for k:= 0 to (j - i) - 1 do
          begin
            Out_.Append(WorkLine[k]);
            Out_.Append(#13#10);
          end;
          i:= j;
        end // if
        else
        begin
          Out_.Append(Lines[i]);
          Out_.Append(#13#10);
          Inc(i);
        end;
      end; // while
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // function

function ReflowLineBreaks(const S: string; AMaxLen: Integer): string;

  function StartsWordCI(const ALine, AWord: string): Boolean;
  var
    Trimmed: string;
  begin
    Trimmed:= TrimLeft(ALine);
    if Length(Trimmed) < Length(AWord) then Exit(False);
    if not SameText(Copy(Trimmed, 1, Length(AWord)), AWord) then Exit(False);
    if Length(Trimmed) > Length(AWord) then
      Result:= not (((Trimmed[Length(AWord) + 1] >= 'a') and (Trimmed[Length(AWord) + 1] <= 'z')) or
        ((Trimmed[Length(AWord) + 1] >= 'A') and (Trimmed[Length(AWord) + 1] <= 'Z')) or ((Trimmed[Length(AWord) + 1] >= '0') and (Trimmed[Length(AWord) + 1] <= '9')) or
        (Trimmed[Length(AWord) + 1] = '_'))
    else
      Result:= True;
  end;

  function EndsWordCI(const ALine, AWord: string): Boolean;
  var
    Trimmed: string;
    EndPos: Integer;
  begin
    Trimmed:= TrimRight(ALine);
    if Length(Trimmed) < Length(AWord) then Exit(False);
    EndPos:= Length(Trimmed) - Length(AWord) + 1;
    if not SameText(Copy(Trimmed, EndPos, Length(AWord)), AWord) then Exit(False);
    if EndPos > 1 then
      Result:= not (((Trimmed[EndPos - 1] >= 'a') and (Trimmed[EndPos - 1] <= 'z')) or ((Trimmed[EndPos - 1] >= 'A') and (Trimmed[EndPos - 1] <= 'Z')) or
        ((Trimmed[EndPos - 1] >= '0') and (Trimmed[EndPos - 1] <= '9')) or (Trimmed[EndPos - 1] = '_'))
    else
      Result:= True;
  end;

  function HasLineCommentOrOpenBlock(const ALine: string): Boolean;
  var
    i                       : Integer;
    InString, InBrace, InPar: Boolean;
  begin
    InString:= False;
    InBrace := False;
    InPar   := False;
    i       := 1    ;
    while i <= Length(ALine) do
    begin
      if InBrace then
      begin
        if ALine[i] = '}' then InBrace:= False;
        Inc(i);
        Continue;
      end;
      if InPar then
      begin
        if (i + 1 <= Length(ALine)) and (ALine[i] = '*') and (ALine[i + 1] = ')') then
        begin
          InPar:= False;
          Inc(i, 2);
          Continue;
        end;
        Inc(i);
        Continue;
      end;
      if InString then
      begin
        if ALine[i] = '''' then
        begin
          if (i + 1 <= Length(ALine)) and (ALine[i + 1] = '''') then
            Inc(i, 2)
          else
          begin
            InString:= False;
            Inc(i);
          end;
        end
        else
          Inc(i);
        Continue;
      end;
      if ALine[i] = '''' then begin InString:= True; Inc(i); Continue; end;
      if ALine[i] = '{'  then begin InBrace := True; Inc(i); Continue; end;
      if (i + 1 <= Length(ALine)) and (ALine[i] = '(') and (ALine[i + 1] = '*') then
      begin
        InPar:= True;
        Inc(i, 2);
        Continue;
      end;
      if (i + 1 <= Length(ALine)) and (ALine[i] = '/') and (ALine[i + 1] = '/') then
        Exit(True);
      Inc(i);
    end; // while
    Result:= InBrace or InPar;
  end; // function

  function EndsWithTypeAncestorList(const ALine: string): Boolean;
  var
    R, Head : string;
    i, Level: Integer;
  begin
    R:= TrimRight(ALine);
    if (R = '') or (R[Length(R)] <> ')') then Exit(False);
    Level:= 0;
    i:= Length(R);
    while i > 0 do
    begin
      if R[i]      = ')' then Inc(Level)
      else if R[i] = '(' then
      begin
        Dec(Level);
        if Level = 0 then Break;
      end;
      Dec(i);
    end;
    if i <= 1 then Exit(False);
    Head:= TrimRight(Copy(R, 1, i - 1));
    Result:= EndsWordCI(Head, 'class') or EndsWordCI(Head, 'object') or EndsWordCI(Head, 'interface') or EndsWordCI(Head, 'dispinterface');
  end; // function

  function CurBlocksMerge(const ALine, ANext: string): Boolean;
  var
    R: string;
  begin
    if HasLineCommentOrOpenBlock(ALine) then Exit(True);
    if EndsWithTypeAncestorList(ALine) then Exit(True);
    R:= TrimRight(ALine);
    if R            = '' then Exit(True);
    if R[Length(R)] = ';' then Exit(True);
    if R[Length(R)] = '.' then Exit(True);
    if R[Length(R)] = '}' then Exit(True);
    if EndsWordCI(R, 'begin') then Exit(True);
    if EndsWordCI(R, 'end') then Exit(True);
    if EndsWordCI(R, 'asm') then Exit(True);
    if EndsWordCI(R, 'try') then Exit(True);
    if EndsWordCI(R, 'finally') then Exit(True);
    if EndsWordCI(R, 'except') then Exit(True);
    if EndsWordCI(R, 'repeat') then Exit(True);
    if EndsWordCI(R, 'of') then Exit(True);
    if EndsWordCI(R, 'class') then Exit(True);
    if EndsWordCI(R, 'object') then Exit(True);
    if EndsWordCI(R, 'record') then Exit(True);
    if EndsWordCI(R, 'interface') then Exit(True);
    if EndsWordCI(R, 'dispinterface') then Exit(True);
    if EndsWordCI(R, 'implementation') then Exit(True);
    if EndsWordCI(R, 'initialization') then Exit(True);
    if EndsWordCI(R, 'finalization') then Exit(True);
    if EndsWordCI(R, 'private') then Exit(True);
    if EndsWordCI(R, 'public') then Exit(True);
    if EndsWordCI(R, 'protected') then Exit(True);
    if EndsWordCI(R, 'published') then Exit(True);
    if EndsWordCI(R, 'then') then Exit(True);
    if EndsWordCI(R, 'else') then
    begin
      if not StartsWordCI(TrimLeft(ANext), 'if') then
        Exit(True);
    end;
    if EndsWordCI(R, 'uses') then Exit(True);
    if EndsWordCI(R, 'contains') then Exit(True);
    if EndsWordCI(R, 'requires') then Exit(True);
    Result:= False;
  end; // function

  function NextBlocksMerge(const ALine: string): Boolean;
  var
    T: string;
  begin
    T:= TrimLeft(ALine);
    if T = '' then Exit(True);
    if T.StartsWith('//') then Exit(True);
    if T.StartsWith('{$') then Exit(True);
    if StartsWordCI(T, 'begin') then Exit(True);
    if StartsWordCI(T, 'end') then Exit(True);
    if StartsWordCI(T, 'else') then Exit(True);
    if StartsWordCI(T, 'until') then Exit(True);
    if StartsWordCI(T, 'finally') then Exit(True);
    if StartsWordCI(T, 'except') then Exit(True);
    if StartsWordCI(T, 'interface') then Exit(True);
    if StartsWordCI(T, 'implementation') then Exit(True);
    if StartsWordCI(T, 'initialization') then Exit(True);
    if StartsWordCI(T, 'finalization') then Exit(True);
    if StartsWordCI(T, 'type') then Exit(True);
    if StartsWordCI(T, 'var') then Exit(True);
    if StartsWordCI(T, 'const') then Exit(True);
    if StartsWordCI(T, 'procedure') then Exit(True);
    if StartsWordCI(T, 'function') then Exit(True);
    if StartsWordCI(T, 'constructor') then Exit(True);
    if StartsWordCI(T, 'destructor') then Exit(True);
    if StartsWordCI(T, 'private') then Exit(True);
    if StartsWordCI(T, 'public') then Exit(True);
    if StartsWordCI(T, 'protected') then Exit(True);
    if StartsWordCI(T, 'published') then Exit(True);
    if StartsWordCI(T, 'uses') then Exit(True);
    if T.StartsWith(',') then Exit(True);
    if T.StartsWith(';') then Exit(True);
    Result:= False;
  end; // function

  function ComputeBlockCommentLock(ALines: TStringList): TArray<Boolean>;
  var
    i, k                    : Integer;
    Line                    : string;
    InBrace, InPar, InString: Boolean;
    StartedInside           : Boolean;
  begin
    SetLength(Result, ALines.Count);
    InBrace:= False;
    InPar  := False;
    for i:= 0 to ALines.Count - 1 do
    begin
      StartedInside:= InBrace or InPar;
      Line:= ALines[i];
      InString:= False;
      k       := 1    ;
      while k <= Length(Line) do
      begin
        if InBrace then
        begin
          if Line[k] = '}' then InBrace:= False;
          Inc(k);
          Continue;
        end;
        if InPar then
        begin
          if (k + 1 <= Length(Line)) and (Line[k] = '*') and (Line[k + 1] = ')') then
          begin
            InPar:= False;
            Inc(k, 2);
            Continue;
          end;
          Inc(k);
          Continue;
        end;
        if InString then
        begin
          if Line[k] = '''' then
          begin
            if (k + 1 <= Length(Line)) and (Line[k + 1] = '''') then
              Inc(k, 2)
            else
            begin
              InString:= False;
              Inc(k);
            end;
          end
          else
            Inc(k);
          Continue;
        end;
        if Line[k] = '''' then begin InString:= True; Inc(k); Continue; end;
        if Line[k] = '{'  then begin InBrace := True; Inc(k); Continue; end;
        if (k + 1 <= Length(Line)) and (Line[k] = '(') and (Line[k + 1] = '*') then
        begin
          InPar:= True;
          Inc(k, 2);
          Continue;
        end;
        if (k + 1 <= Length(Line)) and (Line[k] = '/') and (Line[k + 1] = '/') then
          Break;
        Inc(k);
      end; // while
      Result[i]:= StartedInside or InBrace or InPar;
    end; // for
  end; // function

var
  CommentLocked: TArray<Boolean>;
  Cur          : string;
  i            : Integer;
  Joined       : string;
  k            : Integer;
  Leading      : string;
  Lines        : TStringList;
  NextLn       : string;
  Out_         : TStringBuilder;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      CommentLocked:= ComputeBlockCommentLock(Lines);
      i:= 0;
      while i < Lines.Count do
      begin
        Cur:= Lines[i];
        while i + 1 < Lines.Count do
        begin
          NextLn:= Lines[i + 1];
          if Trim(NextLn) = '' then Break;
          if CommentLocked[i] or CommentLocked[i + 1] then Break;
          if CurBlocksMerge(Cur, NextLn) then Break;
          if NextBlocksMerge(NextLn) then Break;
          k      := 1 ;
          Leading:= '';
          while (k <= Length(Cur)) and ((Cur[k] = ' ') or (Cur[k] = #9)) do
          begin
            Leading:= Leading + Cur[k];
            Inc(k);
          end;
          var CurR : string:= TrimRight(Cur   );
          var NextT: string:= Trim     (NextLn);
          var Sep: string:= ' ';
          if (CurR <> '') and CharInSet(CurR[Length(CurR)], ['(', '[']) then
            Sep:= '';
          if (NextT <> '') and CharInSet(NextT[1], [')', ']', ',', ';', '.']) then
            Sep:= '';
          Joined:= CurR + Sep + NextT;
          if Length(Joined) > AMaxLen then Break;
          Cur:= Joined;
          Inc(i);
        end; // while
        Out_.Append(Cur);
        Out_.Append(#13#10);
        Inc(i);
      end; // while
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // begin

function EnforceBlankLines(const S: string; const AOpts: TYadfOptions): string;

  function StartsWordCI(const ALine, AWord: string): Boolean;
  var
    Trimmed: string;
  begin
    Trimmed:= TrimLeft(ALine);
    if Length(Trimmed) < Length(AWord) then Exit(False);
    if not SameText(Copy(Trimmed, 1, Length(AWord)), AWord) then Exit(False);
    if Length(Trimmed) > Length(AWord) then
      Result:= not (((Trimmed[Length(AWord) + 1] >= 'a') and (Trimmed[Length(AWord) + 1] <= 'z')) or
        ((Trimmed[Length(AWord) + 1] >= 'A') and (Trimmed[Length(AWord) + 1] <= 'Z')) or ((Trimmed[Length(AWord) + 1] >= '0') and (Trimmed[Length(AWord) + 1] <= '9')) or
        (Trimmed[Length(AWord) + 1] = '_'))
    else
      Result:= True;
  end;

  function IsSectionKw(const ALine: string): Boolean;
  begin
    Result:= StartsWordCI(ALine, 'interface') or StartsWordCI(ALine, 'implementation') or StartsWordCI(ALine, 'initialization') or StartsWordCI(ALine, 'finalization');
  end;

  function IsTypeKw(const ALine: string): Boolean;
  begin
    Result:= StartsWordCI(ALine, 'type');
  end;

  function IsMethodDecl(const ALine: string): Boolean;
  var
    T: string;
  begin
    T:= TrimLeft(ALine);
    Result:= StartsWordCI(T, 'procedure') or StartsWordCI(T, 'function') or StartsWordCI(T, 'constructor') or StartsWordCI(T, 'destructor');
    if Result and StartsWordCI(T, 'class') then Result:= False;
  end;

var
  Have : Integer;
  i    : Integer;
  j    : Integer;
  Lines: TStringList;
  Need : Integer;
  Out_ : TStringBuilder;
begin
  if (AOpts.BlanksBeforeSection <= 0) and (AOpts.BlanksBeforeMethod <= 0) and (AOpts.BlanksBeforeType <= 0) then
    Exit(S);
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Need:= 0;
        if (AOpts.BlanksBeforeSection > 0) and IsSectionKw(Lines[i]) then
          Need:= AOpts.BlanksBeforeSection;
        if (AOpts.BlanksBeforeType > 0) and IsTypeKw(Lines[i]) then
        if AOpts.BlanksBeforeType > Need then Need:= AOpts.BlanksBeforeType;
        if (AOpts.BlanksBeforeMethod > 0) and IsMethodDecl(Lines[i]) then
        if AOpts.BlanksBeforeMethod > Need then Need:= AOpts.BlanksBeforeMethod;
        if (Need > 0) and (i > 0) then
        begin
          Have:= 0;
          j:= i - 1;
          while (j >= 0) and (Trim(Lines[j]) = '') do
          begin
            Inc(Have);
            Dec(j);
          end;
          while Have < Need do
          begin
            Out_.Append(#13#10);
            Inc(Have);
          end;
        end;
        Out_.Append(Lines[i]);
        Out_.Append(#13#10);
      end; // for
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // begin

function CollapseBlankLines(const S: string; AMax: Integer): string;
var
  Blanks : Integer;
  i      : Integer;
  IsBlank: Boolean;
  Lines  : TStringList;
  Out_   : TStringBuilder;
begin
  if AMax < 0 then Exit(S);
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      Blanks:= 0;
      for i:= 0 to Lines.Count - 1 do
      begin
        IsBlank:= Trim(Lines[i]) = '';
        if IsBlank then
        begin
          Inc(Blanks);
          if Blanks > AMax then
            Continue;
        end
        else
          Blanks:= 0;
        Out_.Append(Lines[i]);
        Out_.Append(#13#10);
      end;
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // function

function IsCommentKind(k: TptTokenKind): Boolean;
begin
  Result:= k in [ptAnsiComment, ptBorComment, ptSlashesComment];
end;

function ReindentByDepth(const ASrc: string; AIndent: Integer): string;
var
  AfterCRLF         : Boolean;
  BodyBonus         : Integer;
  CurLineLast       : TptTokenKind;
  EffectiveDepth    : Integer;
  ExpectSectionDecl : Boolean;
  i                 : Integer;
  InInterfaceSection: Boolean;
  InUsesClause      : Boolean;
  InVisibility      : Boolean;
  IsProcBody        : TList<Boolean>;
  OpenProcRegions   : Integer;
  Out_              : TStringBuilder;
  ParensDepth       : Integer;
  PendingProcStack  : TList<Boolean>;
  PendingWS         : string;
  PrevNonKind       : TptTokenKind;
  Stack             : TList<TptTokenKind>;
  T                 : TToken;
  Tokens            : TTokenList;

  function StackContainsCaseAtTop: Boolean;
  var
    k: Integer;
  begin
    for k:= Stack.Count - 1 downto 0 do case Stack[k] of
      ptCase                                                         : Exit(True);
      ptBegin, ptRecord, ptTry, ptAsm, ptObject, ptClass, ptInterface: Exit(False);
    end;
    Result:= False;
  end;

  function StackTop: TptTokenKind;
  begin
    if Stack.Count = 0 then Result:= ptUnknown
    else Result:= Stack[Stack.Count - 1];
  end;

  function InClassOrRecord: Boolean;
  var
    k: Integer;
  begin
    for k:= 0 to Stack.Count - 1 do if Stack[k] in [ptClass, ptObject, ptInterface, ptRecord] then
      Exit(True);
    Result:= False;
  end;

  procedure StackPush(k: TptTokenKind);
  begin
    Stack.Add(k);
    IsProcBody.Add(False);
  end;

  procedure StackPushBegin;
  var
    IsBody         : Boolean;
    HasContextBlock: Boolean;
    k              : Integer;
  begin
    IsBody         := False;
    HasContextBlock:= False;
    for k:= 0 to Stack.Count - 1 do if Stack[k] in [ptBegin, ptCase, ptTry, ptAsm] then
    begin
      HasContextBlock:= True;
      Break;
    end;
    if (not HasContextBlock) and (PendingProcStack.Count > 0) then
    begin
      IsBody:= PendingProcStack[PendingProcStack.Count - 1];
      PendingProcStack.Delete(PendingProcStack.Count - 1);
    end;
    Stack.Add(ptBegin);
    IsProcBody.Add(IsBody);
  end; // procedure

  procedure StackPop;
  begin
    if Stack.Count > 0 then
    begin
      if (IsProcBody.Count > 0) and IsProcBody[IsProcBody.Count - 1] then
      if OpenProcRegions > 0 then Dec(OpenProcRegions);
      if IsProcBody.Count > 0 then
        IsProcBody.Delete(IsProcBody.Count - 1);
      Stack.Delete(Stack.Count - 1);
    end;
  end;

  procedure CloseSectionIfOpen;
  begin
    if StackTop in [ptType, ptVar, ptConst] then
      StackPop;
  end;

begin
  Tokens:= LoadTokensFromString(ASrc);
  try
    Out_:= TStringBuilder.Create;
    Stack           := TList<TptTokenKind>.Create;
    IsProcBody      := TList<Boolean     >.Create;
    PendingProcStack:= TList<Boolean     >.Create;
    try
      PrevNonKind       := ptUnknown;
      InVisibility      := False    ;
      AfterCRLF         := False    ;
      ParensDepth       := 0        ;
      PendingWS         := ''       ;
      CurLineLast       := ptUnknown;
      BodyBonus         := 0        ;
      InUsesClause      := False    ;
      OpenProcRegions   := 0        ;
      InInterfaceSection:= False    ;
      ExpectSectionDecl := False    ;
      for i:= 0 to Tokens.Count - 1 do
      begin
        T:= Tokens[i];

        if T.Kind in [ptCRLF, ptCRLFCo] then
        begin
          Out_.Append(T.Text);
          AfterCRLF:= True;
          PendingWS:= ''  ;
          case CurLineLast of
            ptThen, ptDo, ptElse: BodyBonus:= 1;
            ptColon             : if StackContainsCaseAtTop then
              BodyBonus:= 1;
            ptSemiColon: if ParensDepth = 0 then
              BodyBonus:= 0;
            ptEnd, ptBegin, ptCase, ptRecord, ptTry, ptAsm, ptObject, ptRepeat, ptUntil: BodyBonus:= 0;
          end;
          CurLineLast      := ptUnknown;
          ExpectSectionDecl:= False    ;
          Continue;
        end; // if

        if T.Kind = ptSpace then
        begin
          if AfterCRLF then
            PendingWS:= PendingWS + T.Text
          else
            Out_.Append(T.Text);
          Continue;
        end;

        if ExpectSectionDecl and not (T.Kind in [ptAnsiComment, ptBorComment, ptSlashesComment]) then
        begin
          while (Out_.Length > 0) and (Out_.Chars[Out_.Length - 1] = ' ') do Out_.Length:= Out_.Length - 1;
          Out_.Append(#13#10);
          AfterCRLF        := True     ;
          PendingWS        := ''       ;
          CurLineLast      := ptUnknown;
          ExpectSectionDecl:= False    ;
        end;

        if AfterCRLF and (InUsesClause or (T.Kind in [ptPlus, ptMinus, ptStar, ptSlash, ptComma, ptOr, ptAnd, ptXor, ptDiv, ptMod, ptShl, ptShr, ptEqual, ptLower, ptGreater,
              ptLowerEqual, ptGreaterEqual, ptNotEqual, ptDotDot, ptPoint, ptThen, ptDo, ptOf])) then
        begin
          Out_.Append(PendingWS);
          PendingWS:= ''   ;
          AfterCRLF:= False;
        end
        else if AfterCRLF then
        begin
          PendingWS:= '';
          EffectiveDepth:= Stack.Count + ParensDepth;
          if T.Kind in [ptRoundClose, ptSquareClose] then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if T.Kind in [ptEnd, ptUntil] then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if T.Kind in [ptExcept, ptFinally] then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if (T.Kind in [ptType, ptVar, ptConst]) and (StackTop in [ptType, ptVar, ptConst]) then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if (T.Kind = ptBegin) and (not InClassOrRecord) and (StackTop in [ptType, ptVar, ptConst]) then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if (T.Kind in [ptProcedure, ptFunction, ptConstructor, ptDestructor]) and (not InClassOrRecord) then
            EffectiveDepth:= OpenProcRegions;
          if T.Kind in [ptImplementation, ptInitialization, ptFinalization] then
            EffectiveDepth:= 0;
          if (T.Kind = ptInterface) and (PrevNonKind <> ptEqual) then
            EffectiveDepth:= 0;
          if T.Kind = ptUses then
            EffectiveDepth:= 0;
          if InVisibility and not (T.Kind in [ptPrivate, ptPublic, ptProtected, ptPublished, ptStrict, ptEnd])
             and not (T.ExID in [ptPrivate, ptPublic, ptProtected, ptPublished, ptStrict]) then
            Inc(EffectiveDepth);
          if (BodyBonus > 0) and not (T.Kind in [ptBegin, ptCase, ptTry, ptAsm, ptEnd, ptElse, ptIf, ptRecord, ptObject]) then
            Inc(EffectiveDepth, BodyBonus);
          if (OpenProcRegions > 1) and not ((T.Kind in [ptProcedure, ptFunction, ptConstructor, ptDestructor]) and (not InClassOrRecord)) then
            Inc(EffectiveDepth, OpenProcRegions - 1);
          Out_.Append(StringOfChar(' ', EffectiveDepth * AIndent));
          AfterCRLF:= False;
        end; // if

        Out_.Append(T.Text);

        if not (T.Kind in [ptAnsiComment, ptBorComment, ptSlashesComment]) then
        begin
          case T.Kind of
            ptRoundOpen, ptSquareOpen  : Inc(ParensDepth);
            ptRoundClose, ptSquareClose: if ParensDepth > 0 then Dec(ParensDepth);
            ptType, ptVar, ptConst     : if (ParensDepth = 0) and not (StackTop in [ptBegin, ptCase, ptTry, ptAsm]) then
            begin
              CloseSectionIfOpen;
              StackPush(T.Kind);
              InVisibility     := False;
              ExpectSectionDecl:= True ;
            end;
            ptProcedure, ptFunction, ptConstructor, ptDestructor: if (not InClassOrRecord) then
            begin
              CloseSectionIfOpen;
              InVisibility:= False;
              if not InInterfaceSection then
              begin
                PendingProcStack.Add(True);
                Inc(OpenProcRegions);
              end;
            end;
            ptBegin:
            begin
              if (not InClassOrRecord) then CloseSectionIfOpen;
              StackPushBegin;
              InVisibility:= False;
            end;
            ptRecord, ptCase, ptTry, ptAsm, ptRepeat:
            begin
              StackPush(T.Kind);
              InVisibility:= False;
            end;
            ptUntil:
            begin
              StackPop;
              InVisibility:= False;
            end;
            ptClass, ptObject: if PrevNonKind = ptEqual then
            begin
              StackPush(T.Kind);
              InVisibility:= False;
            end;
            ptInterface: if PrevNonKind = ptEqual then
            begin
              StackPush(T.Kind);
              InVisibility:= False;
            end
            else
            begin
              while Stack.Count > 0 do StackPop;
              InVisibility      := False;
              InInterfaceSection:= True ;
              OpenProcRegions   := 0    ;
              PendingProcStack.Clear;
            end;
            ptImplementation, ptInitialization, ptFinalization:
            begin
              while Stack.Count > 0 do StackPop;
              InVisibility      := False;
              InInterfaceSection:= False;
              OpenProcRegions   := 0    ;
              PendingProcStack.Clear;
            end;
            ptEnd:
            begin
              StackPop;
              InVisibility:= False;
            end;
            ptPrivate, ptPublic, ptProtected, ptPublished: InVisibility:= True;
            ptUses, ptContains, ptRequires               : InUsesClause:= True;
            ptSemiColon                                  : if (ParensDepth = 0) and InUsesClause then
              InUsesClause:= False;
            ptForward, ptExternal: if (not InClassOrRecord) and (PendingProcStack.Count > 0) then
            begin
              PendingProcStack.Delete(PendingProcStack.Count - 1);
              if OpenProcRegions > 0 then Dec(OpenProcRegions);
            end;
          end; // case
          if T.ExID in [ptPrivate, ptPublic, ptProtected, ptPublished] then
            InVisibility:= True;
          if (T.ExID in [ptForward, ptExternal]) and (not InClassOrRecord) and (PendingProcStack.Count > 0) then
          begin
            PendingProcStack.Delete(PendingProcStack.Count - 1);
            if OpenProcRegions > 0 then Dec(OpenProcRegions);
          end;
          PrevNonKind:= T.Kind;
          CurLineLast:= T.Kind;
        end; // if
      end; // for
      Result:= Out_.ToString;
    finally
      PendingProcStack.Free;
      IsProcBody.Free;
      Stack.Free;
      Out_.Free;
    end; // try
  finally
    Tokens.Free;
  end; // try
end; // begin

function CollectUsesItems(const ATokens: TTokenList; AStartIdx, AEndIdx: Integer; out AHasInClause: Boolean): TArray<string>;
var
  CurText: string;
  i      : Integer;
  Items  : TList<string>;
  T      : TToken;
begin
  Items:= TList<string>.Create;
  try
    AHasInClause:= False;
    CurText     := ''   ;
    for i:= AStartIdx to AEndIdx do
    begin
      T:= ATokens[i];
      if T.Kind = ptComma then
      begin
        Items.Add(Trim(CurText));
        CurText:= '';
      end
      else
      begin
        if T.Kind = ptIn then
          AHasInClause:= True;
        if (CurText <> '') and (T.Kind <> ptPoint) and not CurText.EndsWith('.') then
          CurText:= CurText + ' ';
        CurText:= CurText + T.Text;
      end;
    end; // for
    if Trim(CurText) <> '' then
      Items.Add(Trim(CurText));
    Result:= Items.ToArray;
  finally
    Items.Free;
  end; // try
end; // function

function RenderUsesGroup(const ATokens: TTokenList; G: TGroup; const AOpts: TYadfOptions): string;
var
  BaseCol  : Integer;
  HasIn    : Boolean;
  i        : Integer;
  Indent   : string;
  InlineLen: Integer;
  Items    : TArray<string>;
  Joined   : string;
  OpenTok  : TToken;
  Sb       : TStringBuilder;
begin
  OpenTok:= ATokens[G.OpenIdx];
  Items:= CollectUsesItems(ATokens, G.OpenIdx + 1, G.CloseIdx - 1, HasIn);
  if Length(Items) = 0 then
    Exit(OpenTok.Pre + OpenTok.Text + ';');

  BaseCol:= ColumnFromPre(OpenTok.Pre);

  Joined:= '';
  for i:= 0 to High(Items) do
  begin
    if i > 0 then
      Joined:= Joined + ', ';
    Joined:= Joined + Items[i];
  end;
  InlineLen:= BaseCol + Length(OpenTok.Text) + 1 + Length(Joined) + 1;

  if (not AOpts.UsesAlwaysBreak) and (InlineLen <= AOpts.MaxLen) and (not HasIn) then
    Exit(OpenTok.Pre + OpenTok.Text + ' ' + Joined + ';');

  Indent:= StringOfChar(' ', BaseCol + AOpts.Indent);
  Sb:= TStringBuilder.Create;
  try
    Sb.Append(OpenTok.Pre);
    Sb.Append(OpenTok.Text);
    for i:= 0 to High(Items) do
    begin
      Sb.Append(#13#10);
      Sb.Append(Indent);
      if i = 0 then
        Sb.Append(Items[i])
      else
      begin
        Sb.Append(', ');
        Sb.Append(Items[i]);
      end;
    end;
    Sb.Append(#13#10);
    Sb.Append(Indent);
    Sb.Append(';');
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

function InlineRenderRange(const ATokens: TTokenList; AFrom, ATo: Integer): string;
var
  HasContent: Boolean;
  i         : Integer;
  Sb        : TStringBuilder;
begin
  Sb:= TStringBuilder.Create;
  try
    HasContent:= False;
    for i:= AFrom to ATo do
    begin
      if ATokens[i].Kind in [ptSpace, ptCRLF, ptCRLFCo] then
      begin
        if HasContent and (Sb.Length > 0) and (Sb.Chars[Sb.Length - 1] <> ' ') then
          Sb.Append(' ');
        Continue;
      end;
      if HasContent and (ATokens[i].Pre <> '') and (Sb.Length > 0) and (Sb.Chars[Sb.Length - 1] <> ' ') then
        Sb.Append(' ');
      Sb.Append(ATokens[i].Text);
      HasContent:= True;
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

function RangeHasMultiLineToken(const ATokens: TTokenList; AFrom, ATo: Integer): Boolean;
var
  i: Integer;
begin
  for i:= AFrom to ATo do if not (ATokens[i].Kind in [ptSpace, ptCRLF, ptCRLFCo]) then
  if (Pos(#10, ATokens[i].Text) > 0) or (Pos(#13, ATokens[i].Text) > 0) then
    Exit(True);
  Result:= False;
end;

type
  TItemRange = record
    First, Last      : Integer;
    CmtFirst, CmtLast: Integer;
  end;

function CollectParensItems(const ATokens: TTokenList; AOpenIdx, ACloseIdx: Integer): TArray<TItemRange>;
var
  CmtF     : Integer;
  CmtL     : Integer;
  CommaLine: Integer;
  CurFirst : Integer;
  CurLast  : Integer;
  Depth    : Integer;
  i        : Integer;
  Item     : TItemRange;
  Items    : TList<TItemRange>;
  k        : Integer;
  T        : TToken;
begin
  Items:= TList<TItemRange>.Create;
  try
    Depth:= 0;
    while (AOpenIdx + 1 <= ACloseIdx - 1) and (ATokens[AOpenIdx + 1].Kind in [ptSpace, ptCRLF]) do Inc(AOpenIdx);
    CurFirst:= AOpenIdx + 1;
    CurLast:= -1;
    i:= AOpenIdx + 1;
    while i <= ACloseIdx - 1 do
    begin
      T:= ATokens[i];
      if (T.Kind = ptComma) and (Depth = 0) then
      begin
        CommaLine:= T.Line;
        k:= i + 1;
        CmtF:= -1;
        CmtL:= -1;
        while True do
        begin
          while (k <= ACloseIdx - 1) and (ATokens[k].Kind = ptSpace) do Inc(k);
          if (k <= ACloseIdx - 1) and IsCommentKind(ATokens[k].Kind) and (ATokens[k].Line = CommaLine) then
          begin
            if CmtF < 0 then CmtF:= k;
            CmtL:= k;
            Inc(k);
            Continue;
          end;
          Break;
        end;
        if CurLast < CurFirst then
          CurLast:= i - 1;
        Item.First   := CurFirst;
        Item.Last    := CurLast ;
        Item.CmtFirst:= CmtF    ;
        Item.CmtLast := CmtL    ;
        Items.Add(Item);
        while (k <= ACloseIdx - 1) and (ATokens[k].Kind in [ptSpace, ptCRLF]) do Inc(k);
        CurFirst:= k;
        CurLast:= -1;
        i:= k;
      end // if
      else
      begin
        if T.Kind in [ptRoundOpen, ptSquareOpen] then
          Inc(Depth);
        if T.Kind in [ptRoundClose, ptSquareClose] then
          Dec(Depth);
        if not (T.Kind in [ptSpace, ptCRLF]) then
          CurLast:= i;
        Inc(i);
      end;
    end; // while
    if CurFirst <= ACloseIdx - 1 then
    begin
      Item.First:= CurFirst;
      if CurLast < CurFirst then
        CurLast:= ACloseIdx - 1;
      Item.Last:= CurLast;
      Item.CmtFirst:= -1;
      Item.CmtLast := -1;
      Items.Add(Item);
    end;
    Result:= Items.ToArray;
  finally
    Items.Free;
  end; // try
end; // function

function FindBlockLabel(const ATokens: TTokenList; AOpenIdx: Integer): string;
var
  i    : Integer;
  k    : TptTokenKind;
  Limit: Integer;
begin
  case ATokens[AOpenIdx].Kind of
    ptRecord: Exit('record');
    ptCase  : Exit('case');
    ptTry   : Exit('try');
    ptAsm   : Exit('asm');
    ptObject: Exit('object');
  end;
  i:= AOpenIdx - 1;
  Limit:= 300;
  while (i >= 0) and (Limit > 0) do
  begin
    Dec(Limit);
    k:= ATokens[i].Kind;
    if k in [ptSpace, ptCRLF, ptCRLFCo, ptAnsiComment, ptBorComment, ptSlashesComment, ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect,
      ptIfEndDirect] then
    begin
      Dec(i);
      Continue;
    end;
    case k of
      ptDo, ptThen    : ;
      ptElse          : Exit('else');
      ptProcedure     : Exit('procedure');
      ptFunction      : Exit('function');
      ptConstructor   : Exit('constructor');
      ptDestructor    : Exit('destructor');
      ptWhile         : Exit('while');
      ptFor           : Exit('for');
      ptIf            : Exit('if');
      ptCase          : Exit('case');
      ptTry           : Exit('try');
      ptInitialization: Exit('initialization');
      ptFinalization  : Exit('finalization');
      ptEnd           : Exit('begin');
    end; // case
    Dec(i);
  end; // while
  Result:= 'begin';
end; // function

function FormatSource(const ASource: string; const AOpts: TYadfOptions): string;
var
  CurCol      : Integer;
  CurLine     : Integer;
  Cursor      : Integer;
  PendingLabel: string;
  Root        : TGroup;
  Sb          : TStringBuilder;
  Tokens      : TTokenList;

  procedure UpdateColumn(const S: string);
  var
    i: Integer;
  begin
    for i:= 1 to Length(S) do if S[i] = #10 then
    begin
      CurCol:= 0;
      Inc(CurLine);
    end
    else if S[i] = #9 then
      Inc(CurCol, AOpts.TabWidth)
    else if S[i] <> #13 then
      Inc(CurCol);
  end;

  procedure EmitText(const S: string);
  var
    i, k          : Integer;
    Pre, Lbl, Post: string;
  begin
    if PendingLabel <> '' then
    begin
      k:= 0;
      for i:= 1 to Length(S) do if (S[i] = #13) or (S[i] = #10) then
      begin
        k:= i;
        Break;
      end;
      if k > 0 then
      begin
        Pre:= Copy(S, 1, k - 1);
        Lbl:= PendingLabel;
        Post:= Copy(S, k, MaxInt);
        PendingLabel:= '';
        Sb.Append(Pre);
        UpdateColumn(Pre);
        Sb.Append(Lbl);
        UpdateColumn(Lbl);
        Sb.Append(Post);
        UpdateColumn(Post);
        Exit;
      end;
    end; // if
    Sb.Append(S);
    UpdateColumn(S);
  end; // procedure

  procedure EmitTokenRange(AFrom, ATo: Integer);
  var
    j: Integer;
  begin
    for j:= AFrom to ATo do
    begin
      EmitText(Tokens[j].Pre);
      EmitText(Tokens[j].Text);
    end;
  end;

  function ParensContentInlineWidth(G: TGroup): Integer;
  begin
    Result:= Length(InlineRenderRange(Tokens, G.OpenIdx + 1, G.CloseIdx - 1));
  end;

  function CurrentLineLeadingWS: string;
  var
    S        : string;
    i        : Integer;
    LineStart: Integer;
  begin
    S:= Sb.ToString;
    LineStart:= 1;
    for i:= Length(S) downto 1 do if (S[i] = #10) or (S[i] = #13) then
    begin
      LineStart:= i + 1;
      Break;
    end;
    Result:= ''       ;
    i     := LineStart;
    while (i <= Length(S)) and ((S[i] = ' ') or (S[i] = #9)) do
    begin
      Result:= Result + S[i];
      Inc(i);
    end;
  end; // function

  function FindChildGroupAt(G: TGroup; AOpenIdx: Integer): TGroup;
  var
    Child: TGroup;
  begin
    for Child in G.Children do if Child.OpenIdx = AOpenIdx then
      Exit(Child);
    Result:= nil;
  end;

  procedure RenderParensBroken(G: TGroup);
  var
    Items   : TArray<TItemRange>;
    LineWS  : string;
    Indent  : string;
    Inner   : string;
    i       : Integer;
    SubGroup: TGroup;
  begin
    Items:= CollectParensItems(Tokens, G.OpenIdx, G.CloseIdx);
    LineWS:= CurrentLineLeadingWS;
    Indent:= LineWS + StringOfChar(' ', AOpts.Indent * 2);
    EmitText(Tokens[G.OpenIdx].Text);
    for i:= 0 to High(Items) do
    begin
      EmitText(#13#10);
      EmitText(Indent);
      Inner:= InlineRenderRange(Tokens, Items[i].First, Items[i].Last);
      if (Length(Indent) + Length(Trim(Inner)) > AOpts.MaxLen) then
      begin
        SubGroup:= FindChildGroupAt(G, Items[i].First);
        if Assigned(SubGroup) and (SubGroup.Kind in [gkParens, gkBrackets]) and (SubGroup.CloseIdx = Items[i].Last)
           and (Length(CollectParensItems(Tokens, SubGroup.OpenIdx, SubGroup.CloseIdx)) > 1) then
          RenderParensBroken(SubGroup)
        else
          EmitText(Trim(Inner));
      end
      else
        EmitText(Trim(Inner));
      if i < High(Items) then
        EmitText(',');
      if Items[i].CmtFirst >= 0 then
      begin
        EmitText(' ');
        EmitText(Trim(InlineRenderRange(Tokens, Items[i].CmtFirst, Items[i].CmtLast)));
      end;
    end; // for
    EmitText(#13#10);
    EmitText(LineWS);
    EmitText(Tokens[G.CloseIdx].Text);
  end; // procedure

  function BlockAlreadyLabeled(G: TGroup): Boolean;
  var
    EndLine, k: Integer;
  begin
    EndLine:= Tokens[G.CloseIdx].Line;
    k:= G.CloseIdx + 1;
    while (k < Tokens.Count) and (Tokens[k].Line = EndLine) do
    begin
      if Tokens[k].Kind = ptSlashesComment then
        Exit(True);
      Inc(k);
    end;
    Result:= False;
  end;

  procedure WalkGroup(G: TGroup);
  var
    Child     : TGroup;
    GroupEnd  : Integer;
    InlineW   : Integer;
    Marker    : string;
    StartLine : Integer;
    BlockLines: Integer;
  begin
    GroupEnd:= G.CloseIdx;
    for Child in G.Children do
    begin
      if Cursor < Child.OpenIdx then
      begin
        EmitTokenRange(Cursor, Child.OpenIdx - 1);
        Cursor:= Child.OpenIdx;
      end;
      StartLine:= CurLine;
      if Child.Kind = gkUses then
      begin
        EmitText(RenderUsesGroup(Tokens, Child, AOpts));
        Cursor:= Child.CloseIdx + 1;
      end
      else if (Child.Kind in [gkParens, gkBrackets]) and not Child.ForceClosed then
      begin
        InlineW:= 1 + ParensContentInlineWidth(Child) + 1;
        if (CurCol + InlineW > AOpts.MaxLen) and (Length(CollectParensItems(Tokens, Child.OpenIdx, Child.CloseIdx)) > 1) then
        begin
          RenderParensBroken(Child);
          Cursor:= Child.CloseIdx + 1;
        end
        else if (CurCol + InlineW <= AOpts.MaxLen) and not RangeHasMultiLineToken(Tokens, Child.OpenIdx, Child.CloseIdx) then
        begin
          EmitText(InlineRenderRange(Tokens, Child.OpenIdx, Child.CloseIdx));
          Cursor:= Child.CloseIdx + 1;
        end
        else
          WalkGroup(Child);
      end // if
      else
      begin
        WalkGroup(Child);
      end;
      if AOpts.MarkUnclosed and Child.ForceClosed and (Child.Kind = gkBlock) then
      begin
        Marker:= Format('// TODO -oYADF : ''%s'' on line %d has no matching ''end''', [Tokens[Child.OpenIdx].Text, Tokens[Child.OpenIdx].Line]);
        if Pos(Marker, ASource) = 0 then
          EmitText(#13#10 + Marker);
      end;
      if AOpts.LabelLongBlocks and (Child.Kind = gkBlock) and not Child.ForceClosed and (Child.CloseIdx > Child.OpenIdx) then
      begin
        BlockLines:= CurLine - StartLine;
        if (BlockLines >= AOpts.LabelMinLines) and not BlockAlreadyLabeled(Child) then
          PendingLabel:= ' // ' + FindBlockLabel(Tokens, Child.OpenIdx);
      end;
    end; // for
    if Cursor <= GroupEnd then
    begin
      EmitTokenRange(Cursor, GroupEnd);
      Cursor:= GroupEnd + 1;
    end;
  end; // procedure

  function IsAlphaNum(C: Char): Boolean;
  begin
    Result:= C.IsLetterOrDigit or (C = '_');
  end;

  function FindOperatorPositionsAtTopLevel(const Line: string): TArray<Integer>;
  var
    Positions               : TList<Integer>;
    i                       : Integer;
    Depth                   : Integer;
    InString, InBrace, InPar: Boolean;
    procedure AddIfWord(Idx, Wlen: Integer; const W: string);
    begin
      if (Idx + Wlen - 1 > Length(Line)) then Exit;
      if not SameText(Copy(Line, Idx, Wlen), W) then Exit;
      if (Idx > 1) and IsAlphaNum(Line[Idx - 1]) then Exit;
      if (Idx + Wlen <= Length(Line)) and IsAlphaNum(Line[Idx + Wlen]) then Exit;
      Positions.Add(Idx);
    end;
  begin
    Positions:= TList<Integer>.Create;
    try
      Depth   := 0    ;
      InString:= False;
      InBrace := False;
      InPar   := False;
      i       := 1    ;
      while i <= Length(Line) do
      begin
        if InBrace then
        begin
          if Line[i] = '}' then InBrace:= False;
          Inc(i);
          Continue;
        end;
        if InPar then
        begin
          if (i + 1 <= Length(Line)) and (Line[i] = '*') and (Line[i+1] = ')') then
          begin
            InPar:= False;
            Inc(i, 2);
            Continue;
          end;
          Inc(i);
          Continue;
        end;
        if InString then
        begin
          if Line[i] = '''' then
          begin
            if (i + 1 <= Length(Line)) and (Line[i+1] = '''') then
              Inc(i, 2)
            else
            begin
              InString:= False;
              Inc(i);
            end;
          end
          else
            Inc(i);
          Continue;
        end;
        if Line[i] = '''' then begin InString:= True; Inc(i); Continue; end;
        if Line[i] = '{'  then begin InBrace := True; Inc(i); Continue; end;
        if (i + 1 <= Length(Line)) and (Line[i] = '/') and (Line[i+1] = '/') then Break;
        if (i + 1 <= Length(Line)) and (Line[i] = '(') and (Line[i+1] = '*') then
        begin
          InPar:= True;
          Inc(i, 2);
          Continue;
        end;
        if CharInSet(Line[i], ['(', '[']) then begin Inc(Depth); Inc(i); Continue; end;
        if CharInSet(Line[i], [')', ']']) then begin Dec(Depth); Inc(i); Continue; end;
        if (i > 1) and (Line[i - 1] = ' ') then
        begin
          if CharInSet(Line[i], ['+', '-']) and (i + 1 <= Length(Line)) and (Line[i+1] = ' ') then
          begin
            Positions.Add(i);
            Inc(i);
            Continue;
          end;
          AddIfWord(i, 2, 'or');
          AddIfWord(i, 3, 'and');
          AddIfWord(i, 3, 'xor');
        end;
        if (Line[i] = ',') and (Depth > 0) and (i + 1 <= Length(Line)) and (Line[i + 1] = ' ') then
        begin
          Positions.Add(i + 2);
          Inc(i);
          Continue;
        end;
        Inc(i);
      end; // while
      Result:= Positions.ToArray;
    finally
      Positions.Free;
    end; // try
  end; // begin

  function LeadingIndent(const Line: string): string;
  var
    i: Integer;
  begin
    i:= 1;
    while (i <= Length(Line)) and ((Line[i] = ' ') or (Line[i] = #9)) do Inc(i);
    Result:= Copy(Line, 1, i - 1);
  end;

  function BreakLineByOperators(const ALine: string): string;
  var
    Positions : TArray<Integer>;
    BestIdx   : Integer;
    Indent    : string;
    NewIndent : string;
    CurLine   : string;
    Out_      : TStringBuilder;
    p         : Integer;
    MinBreakAt: Integer;
  begin
    Indent:= LeadingIndent(ALine);
    NewIndent:= Indent + StringOfChar(' ', AOpts.Indent);
    Out_:= TStringBuilder.Create;
    try
      CurLine:= ALine;
      while Length(CurLine) > AOpts.MaxLen do
      begin
        MinBreakAt:= Length(LeadingIndent(CurLine)) + 2;
        Positions:= FindOperatorPositionsAtTopLevel(CurLine);
        BestIdx:= -1;
        for p in Positions do
        begin
          if p < MinBreakAt then
            Continue;
          if p <= AOpts.MaxLen then
            BestIdx:= p
          else
            Break;
        end;
        if (BestIdx <= 0) then
          for p in Positions do if p >= MinBreakAt then
        begin
          BestIdx:= p;
          Break;
        end;
        if BestIdx <= 0 then
          Break;
        Out_.Append(TrimRight(Copy(CurLine, 1, BestIdx - 1)));
        Out_.Append(#13#10);
        CurLine:= NewIndent + Copy(CurLine, BestIdx, MaxInt);
      end; // while
      Out_.Append(CurLine);
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  end; // function

  function BreakLongLines(const ASrc: string): string;
  var
    Lines                   : TStringList;
    i, k                    : Integer;
    Line                    : string;
    InBrace, InPar, InString: Boolean;
    StartedInside           : Boolean;
    Locked                  : TArray<Boolean>;
  begin
    Lines:= TStringList.Create;
    try
      Lines.LineBreak        := #13#10;
      Lines.TrailingLineBreak:= True  ;
      Lines.Text             := ASrc  ;
      SetLength(Locked, Lines.Count);
      InBrace:= False;
      InPar  := False;
      for i:= 0 to Lines.Count - 1 do
      begin
        StartedInside:= InBrace or InPar;
        Line:= Lines[i];
        InString:= False;
        k       := 1    ;
        while k <= Length(Line) do
        begin
          if InBrace then
          begin
            if Line[k] = '}' then InBrace:= False;
            Inc(k);
            Continue;
          end;
          if InPar then
          begin
            if (k + 1 <= Length(Line)) and (Line[k] = '*') and (Line[k + 1] = ')') then
            begin
              InPar:= False;
              Inc(k, 2);
              Continue;
            end;
            Inc(k);
            Continue;
          end;
          if InString then
          begin
            if Line[k] = '''' then
            begin
              if (k + 1 <= Length(Line)) and (Line[k + 1] = '''') then
                Inc(k, 2)
              else
              begin
                InString:= False;
                Inc(k);
              end;
            end
            else
              Inc(k);
            Continue;
          end;
          if Line[k] = '''' then begin InString:= True; Inc(k); Continue; end;
          if Line[k] = '{'  then begin InBrace := True; Inc(k); Continue; end;
          if (k + 1 <= Length(Line)) and (Line[k] = '(') and (Line[k + 1] = '*') then
          begin
            InPar:= True;
            Inc(k, 2);
            Continue;
          end;
          if (k + 1 <= Length(Line)) and (Line[k] = '/') and (Line[k + 1] = '/') then
            Break;
          Inc(k);
        end; // while
        Locked[i]:= StartedInside or InBrace or InPar;
      end; // for
      for i:= 0 to Lines.Count - 1 do if (Length(Lines[i]) > AOpts.MaxLen) and not Locked[i] then
        Lines[i]:= BreakLineByOperators(Lines[i]);
      Result:= Lines.Text;
    finally
      Lines.Free;
    end; // try
  end; // function

begin
  Tokens:= LoadTokensFromString(ASource);
  try
    ApplyCapitalization(Tokens, AOpts);
    NormalizeAssignSpacing(Tokens, AOpts);
    Root:= ParseGroups(Tokens);
    try
      Sb:= TStringBuilder.Create;
      try
        Cursor      := 0 ;
        CurCol      := 0 ;
        CurLine     := 1 ;
        PendingLabel:= '';
        WalkGroup(Root);
        if PendingLabel <> '' then
        begin
          EmitText(#13#10);
          PendingLabel:= '';
        end;
        Result:= NormalizeCRLF(Sb.ToString);
        if AOpts.TrimTrailing then
          Result:= TrimTrailingWhitespace(Result);
        Result:= DetabLeadingWhitespace(Result, AOpts.TabWidth);
        Result:= ReindentByDepth       (Result, AOpts.Indent  );
        Result:= EnforceBlankLines(Result, AOpts);
        Result:= BreakLongLines(Result);
        if AOpts.ReflowLines then
        begin
          Result:= ReflowLineBreaks(Result, AOpts.MaxLen);
          Result:= ReindentByDepth (Result, AOpts.Indent);
        end
        else
          Result:= JoinShortCaseAlts(Result, AOpts.MaxLen);
        var EffMaxBlanks: Integer:= AOpts.MaxBlankLines;
        if AOpts.BlanksBeforeSection > EffMaxBlanks then EffMaxBlanks:= AOpts.BlanksBeforeSection;
        if AOpts.BlanksBeforeMethod  > EffMaxBlanks then EffMaxBlanks:= AOpts.BlanksBeforeMethod ;
        if AOpts.BlanksBeforeType    > EffMaxBlanks then EffMaxBlanks:= AOpts.BlanksBeforeType   ;
        Result:= CollapseBlankLines(Result, EffMaxBlanks);
        if AOpts.AlignTypeColon or AOpts.AlignConstEquals or AOpts.AlignSmartAssign then
          Result:= CollapseInteriorSpaces(Result);
        if AOpts.AlignTypeColon then
          Result:= AlignByAnchor(Result, ':', AOpts.AlignMaxColumn);
        if AOpts.AlignConstEquals then
          Result:= AlignByAnchor(Result, '=', AOpts.AlignMaxColumn);
        if AOpts.AlignSmartAssign then
          Result:= SmartAlignAssignments(Result, AOpts.AlignMaxColumn);
      finally
        Sb.Free;
      end; // try
    finally
      Root.Free;
    end; // try
  finally
    Tokens.Free;
  end; // try
end; // begin

end.
