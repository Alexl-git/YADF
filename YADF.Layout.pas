{
  YADF -- Yet Another Delphi Formatter

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Uses lexer/parser code from DelphiAST:
  Copyright (c) 2014-2020 Roman Yankovsky (roman@yankovsky.me) et al
  https://github.com/RomanYankovsky/DelphiAST

  --------------------------------------------------------------------
  Unit overview
  --------------------------------------------------------------------
  YADF.Layout owns the formatting engine. The public surface is one
  function -- FormatSource -- which takes a raw Pascal source string
  plus a TYadfOptions record and returns the formatted source.

  Pipeline (see FormatSource at the bottom of the implementation)
  --------------------------------------------------------------------
  1. Lex the source into a TTokenList via YADF.Tokens.
  2. ApplyCapitalization     -- normalize keyword/hex/directive/
                                identifier casing on the token stream.
  3. NormalizeAssignSpacing  -- fix spaces around `:=` per options.
  4. ParseGroups             -- build a structural TGroup tree
                                (begin/end, parens, brackets, uses)
                                from the token stream.
  5. WalkGroup               -- emit the token stream into a string,
                                substituting structural renderings for
                                uses / parens / brackets groups, and
                                inserting `// keyword` block-end labels
                                and unclosed-block TODOs.
  6. Sequence of string -> string passes on the rendered output:
       NormalizeCRLF          canonicalise line endings.
       TrimTrailingWhitespace strip per-line trailing spaces.
       DetabLeadingWhitespace leading tabs -> spaces.
       ReindentByDepth        full structural re-indentation.
       EnforceBlankLines      blank lines before sections/methods/types.
       BreakLongLines         operator/comma-aware overflow wrapping.
       ReflowLineBreaks       (optional) drop redundant line breaks
                              and re-pack short consecutive lines.
       ReindentByDepth        (after reflow, depth changed)
       -- OR --
       JoinShortCaseAlts      (when reflow is off) merge `value:`
                              followed by a short stmt onto one line.
       CollapseBlankLines     consecutive blanks -> N.
  7. Pass 2 (optional column alignment, all string->string):
       CollapseInteriorSpaces normalise spaces so anchors line up.
       AlignByAnchor          pad `:` in declarations (var/param/field).
       AlignByAnchor          pad `=` in const blocks.
       SmartAlignAssignments  pad `:=` and shared anchors across
                              adjacent shape-matched lines.

  Design constraints
  --------------------------------------------------------------------
  - Idempotent: FormatSource(FormatSource(x)) == FormatSource(x).
  - Comments and string literals are never reformatted internally;
    they pass through verbatim. Indentation around them may change.
  - Output line endings are always CRLF, regardless of input.
  - Pass-2 alignment never grows a line past AOpts.AlignMaxColumn.
  - The walker never reformats raw bytes inside multi-line tokens
    (block comments, triple-quoted strings); those preserve content
    while their leading whitespace is still re-indented.
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

// ===== Whitespace and character helpers =====
// Tiny pure functions reused across the layout passes. None mutate the
// token stream; they all take strings and return strings or scalars.

// Counts characters after the last CR/LF in APre. Used to compute the
// column at which a token will be emitted given its pre-whitespace.
// Returns 0 when APre ends with a newline (token will be at column 0).
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

// Collapses any run of horizontal/vertical whitespace (spaces, tabs,
// CR, LF) to a single space. Used to flatten a multi-line token range
// onto one line during inline rendering of parens groups, uses items,
// etc. Adjacent non-whitespace chars stay untouched.
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

// Canonicalises every line break to CRLF. We collapse CRLF -> LF first
// so mixed input (CRLF + bare LF) folds to a single LF run, then
// expand back. This deliberately produces CRLF regardless of platform.
function NormalizeCRLF(const S: string): string;
begin
  Result:= StringReplace(S     , #13#10, #10   , [rfReplaceAll]);
  Result:= StringReplace(Result, #10   , #13#10, [rfReplaceAll]);
end;

// Strips trailing spaces/tabs from every line and preserves the final
// trailing line break. Run late in the pipeline so passes that emit
// intermediate trailing whitespace don't accumulate it in the output.
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

// True iff S is non-empty and every character is an ASCII letter.
// Used as a guard before lowercasing a token text -- we never want to
// touch hex literals, punctuation, mixed tokens, etc.
function IsAllAlphabetic(const S: string): Boolean;
var
  i: Integer;
begin
  if S = '' then Exit(False);
  for i:= 1 to Length(S) do if not (((S[i] >= 'a') and (S[i] <= 'z')) or ((S[i] >= 'A') and (S[i] <= 'Z'))) then
    Exit(False);
  Result:= True;
end;

// Uppercases hex digits in a $-prefixed integer literal ($ff -> $FF),
// or just the exponent letter in a float literal (1e5 -> 1E5). The
// fork between integer-vs-float is decided by the leading `$`. Other
// characters are preserved as-is.
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

// Uppercases the directive name in a compiler-directive comment:
// {$ifdef X} -> {$IFDEF X}, {$define} -> {$DEFINE}, etc. Only the
// leading alphabetic run after `{$` is touched -- arguments, payload
// text, and the closing `}` are preserved exactly.
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

// ===== Token-stream passes =====
// These mutate the TTokenList in place before the structural walker
// emits anything. Capitalisation and spacing are easier to enforce at
// the token level than in the rendered output, where we'd need to
// re-distinguish identifiers from string contents.

// Enforces spacing policy around `:=` per AOpts.AssignNoSpaceBefore
// and AOpts.AssignSpaceAfter. Walks the token list in one pass: when
// `ptAssign` is found, optionally drops the preceding ptSpace and
// either trims the trailing ptSpace to a single space or inserts one
// when missing (but not at end-of-line -- a `:=` immediately followed
// by CRLF is left untouched so multi-line RHS reflow still works).
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

// Applies all four capitalisation rules driven by AOpts:
//   LowercaseKeywords - lowercases reserved words (any all-alpha token
//                       whose Kind is not in the literal/comment/whitespace
//                       block-list).
//   UpperHexNumbers   - uppercases hex digits and the float exponent E.
//   UpperDirectives   - uppercases compiler directive names.
//   FirstOccCasing    - normalises every identifier to the casing of
//                       its first occurrence in the file (Pascal is
//                       case-insensitive so this is purely cosmetic).
// Each rule is independent; they're applied as separate passes for
// clarity, not performance. The IsLiteralKind block-list keeps us
// from accidentally lowercasing string contents, comments, etc.
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

// ===== Single-line string transforms =====
// Each of these takes the rendered output as a string, slices it into
// lines, performs a per-line operation, and reassembles. Tabs and
// spaces inside string literals and comments are not touched (we only
// scan the LEADING run of whitespace on each line).

// Replaces every leading tab with ATabWidth spaces. Tabs appearing
// after non-whitespace text on a line are preserved. The leading run
// is handled char-by-char (rather than a global StringReplace) so
// non-uniform tab widths are respected.
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

// Joins a `case` alternative label and a short body that fit within
// AMaxLen onto a single line:
//
//     SomeValue:                              SomeValue: DoIt(x);
//       DoIt(x);                ==>
//
// Only kicks in when ReflowLines is OFF (otherwise the reflow pass
// handles this in a more general way). Refuses to join when the
// candidate body begins a structured construct (begin/case/try/asm/
// record) so we don't end up with `Foo: begin ... end` collapsed.
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

// ===== Pass-2 column alignment =====
// These run AFTER the structural rendering and re-indentation. They
// operate purely on the string output, scanning each line for an
// anchor character (`:`, `=`, `:=`) at the top syntactic level --
// outside string literals, braces, parens, comments. Adjacent lines
// that share an anchor are padded so the anchors line up at the
// rightmost column observed in the run, capped at AlignMaxColumn so
// runaway nesting can't push alignment off the right edge.

// Locates AAnchor at top level in ALine -- not inside strings,
// brace/paren comments, // line comments, or () [] groups (Depth > 0).
// Returns the 1-based byte index of the anchor, or 0 if not found.
// Sticky edge cases:
//   * Looking for `:` ignores `:=`.
//   * Looking for `=` ignores the `=` immediately after a `:`.
// Both rules prevent the type-colon align pass and const-equals align
// pass from latching onto the wrong character on the same line.
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
      // Skip the trailing `=` of any two-char operator that ends in
      // it: `:=` assignment, `<=` less-or-equal, `>=` greater-or-
      // equal. Without this, the const-equals alignment pass mistakes
      // the second char of `<=`/`>=` for a const-block `=` and right-
      // pads it -- producing `>          = N`, which dcc32 rejects.
      // (Bug repro: BUG_LE_OPERATOR.md, 2026-05-14.)
      if (i > 1) and ((ALine[i - 1] = ':') or (ALine[i - 1] = '<') or (ALine[i - 1] = '>')) then
      begin
        Inc(i); Continue;
      end;
      Exit(i);
    end;
    Inc(i);
  end; // while
end; // function

// True if ALine begins with `const` followed by whitespace or EOL.
// Used by the const-equals alignment pass to detect the section
// keyword (the `const` line itself is never aligned).
function StartsConstBlock(const ALine: string): Boolean;
var
  T: string;
begin
  T:= TrimLeft(ALine);
  Result:= SameText(Copy(T, 1, 5), 'const') and ((Length(T) = 5) or (T[6] = ' ') or (T[6] = #9) or (T[6] = #13));
end;

// True iff ALine starts with a structural keyword that breaks any
// in-progress alignment run (begin/end/type/var/const/procedure/
// function/constructor/destructor/interface/implementation) or is
// blank. The nested StartsKW helper ensures we match whole keywords
// rather than identifier prefixes (so `endpoint` is not detected as
// `end`).
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

// Collapses every multi-space run inside a single line to one space,
// preserving the leading indent. Re-lexes the line body through
// TmwPasLex so whitespace inside string literals and comments stays
// untouched (the lexer marks those as their own token kinds). Used
// to normalise input before the column-alignment passes so they
// don't have to think about pre-existing alignment padding.
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

// Enforces canonical anchor spacing on ONE line before the smart-align
// pass measures its columns. Rule: a member-access `.` is tight on both
// sides, and `;` has no space before it. Any whitespace that violates
// those rules is dropped here so alignment never freezes a rule-breaking
// gap into a column -- the align pass then re-adds spacing only where a
// shorter line needs padding to reach the shared column. `:=` spacing is
// already canonical from the pass-1 emitter (AssignNoSpaceBefore /
// AssignSpaceAfter) so it is left untouched. Leading indent, strings,
// and comments are preserved verbatim (single-token, not re-spaced).
function TightenAnchorSpacingInLine(const ALine: string): string;
var
  Body    : string;
  i       : Integer;
  Lead    : string;
  LeadLen : Integer;
  NextKind: TptTokenKind;
  n       : Integer;
  PrevKind: TptTokenKind;
  Sb      : TStringBuilder;
  T       : TToken;
  Tokens  : TTokenList;
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
    PrevKind:= ptNull;
    for i:= 0 to Tokens.Count - 1 do
    begin
      T:= Tokens[i];
      if T.Kind = ptSpace then
      begin
        NextKind:= ptNull;
        n:= i + 1;
        while (n < Tokens.Count) and (Tokens[n].Kind = ptSpace) do Inc(n);
        if n < Tokens.Count then NextKind:= Tokens[n].Kind;
        if (NextKind = ptPoint) or (NextKind = ptSemiColon) or (PrevKind = ptPoint) then
          Continue; // drop: tight before `.`/`;` and after `.`
        Sb.Append(T.Pre);
        if Length(T.Text) > 1 then Sb.Append(' ') else Sb.Append(T.Text);
        Continue;
      end;
      Sb.Append(T.Pre);
      Sb.Append(T.Text);
      PrevKind:= T.Kind;
    end;
    Result:= Sb.ToString;
  finally
    Sb.Free;
    Tokens.Free;
  end; // try
end; // function

// Per-line wrapper around CollapseInteriorSpacesInLine that walks the
// entire formatted output. Runs once before the column-alignment
// passes so they see a clean baseline.
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

// Number of consecutive space characters immediately to the left of
// the 1-based column APos in ALine. Used by the alignment passes to
// measure the gap between an anchor and the content preceding it so
// a whole aligned column can be compacted left when every line in
// the run shares surplus padding before the anchor.
function SpacesBeforeCol(const ALine: string; APos: Integer): Integer;
var
  k: Integer;
begin
  Result:= 0;
  k:= APos - 1;
  while (k >= 1) and (k <= Length(ALine)) and (ALine[k] = ' ') do
  begin
    Inc(Result);
    Dec(k);
  end;
end;

// Given an alignment run -- a set of lines whose anchor sits at the
// 1-based columns in AAnchorCols -- compute the tightest column the
// anchor can share without losing alignment or shrinking any line's
// own gap below the run minimum. The result is
//   max(content-extent) + min(gap) + 1
// which equals the old `max(anchor column)` exactly when the run is
// already tight (so existing output is byte-for-byte unchanged), and
// is strictly smaller when every line carries common surplus spaces
// before the anchor (so the whole column is moved left).
function CompactedAnchorCol(const ALines: array of string; const AAnchorCols: array of Integer): Integer;
var
  Ext   : Integer;
  Gap   : Integer;
  i     : Integer;
  MaxExt: Integer;
  MinGap: Integer;
begin
  MaxExt:= 0;
  MinGap:= MaxInt;
  for i:= 0 to High(AAnchorCols) do
  begin
    Gap:= SpacesBeforeCol(ALines[i], AAnchorCols[i]);
    Ext:= AAnchorCols[i] - 1 - Gap;
    if Ext    > MaxExt then MaxExt:= Ext;
    if Gap    < MinGap then MinGap:= Gap;
  end;
  if MinGap = MaxInt then MinGap:= 0;
  Result:= MaxExt + MinGap + 1;
end;

// Generic anchor-alignment pass. Walks the text line by line:
//   1. For every line, compute the column of AAnchor at top level
//      (anchors inside strings/parens/comments don't count).
//   2. Group consecutive lines that all have a non-zero anchor and
//      none of which is a block-boundary line. Stop at the first
//      gap (anchor = 0) or block-boundary keyword.
//   3. If the group has at least 2 lines and the rightmost anchor
//      fits within AMaxColumn, left-pad each line so its anchor
//      reaches that rightmost column.
// AAnchor is the literal anchor string (`:` or `=`); the special-case
// for `:=` is handled inside FindAnchorAtTopLevel.
// v1.0.3: split combined declarations like `I, J: integer;` into one
// line per name. Operates on the post-layout text; runs BEFORE
// AlignByAnchor(':') so the alignment sees the split result.
//
// Rules:
//  - Only fires when the line is at paren depth 0 (so procedure
//    parameter lists like `procedure F(A, B: integer);` are untouched).
//  - The line must shape-match `<indent><name>{,<name>}+<separators>:<type>;<optional-trailing-comment>`.
//    Whitespace tolerated everywhere.
//  - Trailing `// comment` (if any) is preserved on the FIRST split
//    line only -- moving it to the last would change which name the
//    comment annotates.
//
// String- and brace-comment awareness is handled by the paren depth
// tracker, which mirrors YADF's other text passes.
function SplitMultiVarDeclarations(const S: string): string;
var
  Lines       : TStringList;
  Out_        : TStringBuilder;
  i, k, Col   : Integer;
  Line        : string;
  Indent, Body, Names, TypePart, Tail: string;
  ColonPos, SemiPos, CommentPos, FirstNonWs: Integer;
  Depth       : Integer;
  C           : Char;
  InStr       : Boolean;
  InBrace     : Boolean;
  InParenStar : Boolean;
  NameTokens  : TArray<string>;
  HasComma    : Boolean;
  IdentChars  : set of AnsiChar;
begin
  Lines:= TStringList.Create;
  IdentChars:= ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'];
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    Out_:= TStringBuilder.Create;
    try
      Depth      := 0;
      InBrace    := False;
      InParenStar:= False;
      for i:= 0 to Lines.Count - 1 do
      begin
        Line:= Lines[i];

        // Track depth crossing this line BEFORE rewriting, so the next
        // line sees the correct context regardless of whether we split.
        if (Depth > 0) or InBrace or InParenStar then
        begin
          // Line lives inside a paren/brace/paren-star context. Don't
          // split anything here; just update depth tracker.
          InStr:= False;
          Col:= 1;
          while Col <= Length(Line) do
          begin
            C:= Line[Col];
            if InBrace then begin if C = '}' then InBrace:= False; Inc(Col); end
            else if InParenStar then begin
              if (C = '*') and (Col < Length(Line)) and (Line[Col + 1] = ')') then
                begin InParenStar:= False; Inc(Col, 2) end
              else Inc(Col);
            end
            else if InStr then begin if C = '''' then InStr:= False; Inc(Col); end
            else if C = '''' then begin InStr:= True; Inc(Col) end
            else if C = '{' then begin InBrace:= True; Inc(Col) end
            else if (C = '(') and (Col < Length(Line)) and (Line[Col + 1] = '*') then
              begin InParenStar:= True; Inc(Col, 2) end
            else if (C = '/') and (Col < Length(Line)) and (Line[Col + 1] = '/') then Break
            else if (C = '(') or (C = '[') then begin Inc(Depth); Inc(Col) end
            else if (C = ')') or (C = ']') then begin if Depth > 0 then Dec(Depth); Inc(Col) end
            else Inc(Col);
          end;
          Out_.Append(Line);
          Out_.Append(#13#10);
          Continue;
        end;

        // At paren depth 0. Try to shape-match the line.
        FirstNonWs:= 1;
        while (FirstNonWs <= Length(Line)) and
              (Line[FirstNonWs] in [' ', #9]) do Inc(FirstNonWs);
        Indent:= Copy(Line, 1, FirstNonWs - 1);

        // Find `:` and `;` at this line's top level (no nested parens),
        // and detect any trailing line comment so we can preserve it.
        ColonPos:= 0; SemiPos:= 0; CommentPos:= 0;
        InStr:= False;
        Col:= FirstNonWs;
        while Col <= Length(Line) do
        begin
          C:= Line[Col];
          if InStr then begin if C = '''' then InStr:= False; Inc(Col); end
          else if C = '''' then begin InStr:= True; Inc(Col) end
          else if (C = '/') and (Col < Length(Line)) and (Line[Col + 1] = '/') then
            begin CommentPos:= Col; Break end
          else if C = '{' then
          begin
            // Inline brace comment. Skip to matching `}` on the same
            // line; if it doesn't close, bail (we'll just emit the
            // line as-is below).
            Inc(Col);
            while (Col <= Length(Line)) and (Line[Col] <> '}') do Inc(Col);
            if Col <= Length(Line) then Inc(Col);
          end
          else if (C = '(') or (C = '[') then begin Inc(Depth); Inc(Col) end
          else if (C = ')') or (C = ']') then begin if Depth > 0 then Dec(Depth); Inc(Col) end
          else if (Depth = 0) and (C = ':')
                  and not ((Col < Length(Line)) and (Line[Col + 1] = '=')) then
          begin
            if ColonPos = 0 then ColonPos:= Col;
            Inc(Col);
          end
          else if (Depth = 0) and (C = ';') then
          begin
            SemiPos:= Col;
            Inc(Col);
          end
          else
            Inc(Col);
        end;

        // Shape-match: indent + names + `:` + type + `;` + optional comment.
        // ColonPos > FirstNonWs AND SemiPos > ColonPos AND no trailing
        // garbage between `;` and `//` or EOL.
        if (ColonPos > FirstNonWs) and (SemiPos > ColonPos) then
        begin
          Names:= Trim(Copy(Line, FirstNonWs, ColonPos - FirstNonWs));
          TypePart:= Trim(Copy(Line, ColonPos + 1, SemiPos - ColonPos - 1));
          if CommentPos > 0 then
            Tail:= Trim(Copy(Line, CommentPos, Length(Line) - CommentPos + 1))
          else
            Tail:= '';

          // Reject if `Names` is not a clean identifier-comma list.
          // Tolerates whitespace; rejects parens, brackets, equals
          // (initialisers), operators, etc.
          HasComma:= Pos(',', Names) > 0;
          if HasComma then
          begin
            Body:= '';
            for k:= 1 to Length(Names) do
            begin
              C:= Names[k];
              if (AnsiChar(C) in IdentChars) or (C = ',') or
                 (C = ' ') or (C = #9) then
                Body:= Body + C
              else
              begin
                HasComma:= False;  // poison: not a clean name list
                Break;
              end;
            end;
          end;

          if HasComma and (TypePart <> '') then
          begin
            NameTokens:= Names.Split([','], TStringSplitOptions.ExcludeEmpty);
            for k:= 0 to High(NameTokens) do
            begin
              if k = 0 then
              begin
                if Tail <> '' then
                  Out_.AppendLine(Indent + Trim(NameTokens[k]) + ': ' +
                    TypePart + '; ' + Tail)
                else
                  Out_.AppendLine(Indent + Trim(NameTokens[k]) + ': ' +
                    TypePart + ';');
              end
              else
                Out_.AppendLine(Indent + Trim(NameTokens[k]) + ': ' +
                  TypePart + ';');
            end;
            Continue;  // line replaced
          end;
        end;

        // No match (or rejected) -- emit line unchanged.
        Out_.Append(Line);
        Out_.Append(#13#10);
      end;
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end;
  finally
    Lines.Free;
  end;
end;

// v1.0.3: align the trailing `;` on consecutive declaration lines
// (lines that contain a top-level `:` and end with `;`). Runs AFTER
// Bracket depth at the START of each line, tracked ACROSS lines (string- and
// comment-aware). A line whose start-depth > 0 sits inside a multi-line `( )`
// or `[ ]` group -- an enum body, a multi-line array literal, or a split
// parameter list. Those lines must be excluded from the top-level declaration
// alignment passes; otherwise enum members and array internals get their
// `=` / `:` / `;` aligned as if they were real declarations (and the trailing
// `//` comments shift with them).
function ComputeLineStartDepths(Lines: TStringList): TArray<Integer>;
var
  i, p, depth: Integer;
  line       : string;
  c          : Char;
  InBrace, InParenStar, InString: Boolean;
begin
  SetLength(Result, Lines.Count);
  depth := 0; InBrace := False; InParenStar := False;
  for i := 0 to Lines.Count - 1 do
  begin
    Result[i] := depth;          // depth BEFORE this line is processed
    line := Lines[i];
    InString := False;           // Pascal string literals do not span lines
    p := 1;
    while p <= Length(line) do
    begin
      c := line[p];
      if InBrace then
      begin
        if c = '}' then InBrace := False;
        Inc(p); Continue;
      end;
      if InParenStar then
      begin
        if (c = '*') and (p < Length(line)) and (line[p + 1] = ')') then
        begin InParenStar := False; Inc(p, 2); Continue; end;
        Inc(p); Continue;
      end;
      if InString then
      begin
        if c = '''' then InString := False;
        Inc(p); Continue;
      end;
      if c = '''' then begin InString := True; Inc(p); Continue; end;
      if c = '{' then begin InBrace := True; Inc(p); Continue; end;
      if (c = '(') and (p < Length(line)) and (line[p + 1] = '*') then
      begin InParenStar := True; Inc(p, 2); Continue; end;
      if (c = '/') and (p < Length(line)) and (line[p + 1] = '/') then
        Break;                   // line comment: ignore the rest of the line
      if (c = '(') or (c = '[') then Inc(depth)
      else if (c = ')') or (c = ']') then
      begin if depth > 0 then Dec(depth); end;
      Inc(p);
    end;
  end;
end;

// AlignByAnchor(':') so the colons are already in their final column;
// this pass just adds spaces before the `;` so the right edge lines up.
// Runs of fewer than 2 declaration lines are left untouched.
function AlignDeclarationSemicolons(const S: string;
  AMaxColumn: Integer): string;
var
  Lines     : TStringList;
  Out_      : TStringBuilder;
  i, j      : Integer;
  ColonAt, SemiAt: TArray<Integer>;
  Depths    : TArray<Integer>;
  RunStart, RunEnd: Integer;
  Target, k : Integer;
  Pad       : Integer;
  Line      : string;

  function HasDeclShape(const ALine: string;
    out AColon, ASemi: Integer): Boolean;
  var
    p, Depth, sCol: Integer;
    C: Char;
    InStr: Boolean;
  begin
    AColon:= 0; ASemi:= 0;
    InStr:= False; Depth:= 0;
    p:= 1;
    while p <= Length(ALine) do
    begin
      C:= ALine[p];
      if InStr then
      begin
        if C = '''' then InStr:= False;
        Inc(p);
      end
      else if C = '''' then
      begin
        InStr:= True;
        Inc(p);
      end
      else if C = '{' then  // skip inline brace comment
      begin
        Inc(p);
        while (p <= Length(ALine)) and (ALine[p] <> '}') do Inc(p);
        if p <= Length(ALine) then Inc(p);
      end
      else if (C = '/') and (p < Length(ALine)) and (ALine[p + 1] = '/') then
        Break
      else if (C = '(') or (C = '[') then begin Inc(Depth); Inc(p) end
      else if (C = ')') or (C = ']') then begin Dec(Depth); Inc(p) end
      else if (Depth = 0) and (C = ':') and
              not ((p < Length(ALine)) and (ALine[p + 1] = '=')) then
      begin
        if AColon = 0 then AColon:= p;
        Inc(p);
      end
      else if (Depth = 0) and (C = ';') then
      begin
        ASemi:= p;
        Inc(p);
      end
      else
        Inc(p);
    end;
    // The line must have a top-level `:` and a `;` that lives AFTER
    // the colon (i.e., this really is a `name : type;` declaration).
    // We also require that nothing non-whitespace follows the `;`
    // except an optional line comment.
    Result:= (AColon > 0) and (ASemi > AColon);
    if Result then
    begin
      sCol:= ASemi + 1;
      while (sCol <= Length(ALine)) and
            (ALine[sCol] in [' ', #9]) do Inc(sCol);
      if sCol <= Length(ALine) then
      begin
        // Only line comments allowed after the `;`.
        if not ((sCol < Length(ALine)) and (ALine[sCol] = '/') and
                (ALine[sCol + 1] = '/')) then
          Result:= False;
      end;
    end;
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;

    SetLength(ColonAt, Lines.Count);
    SetLength(SemiAt , Lines.Count);
    Depths:= ComputeLineStartDepths(Lines);
    for i:= 0 to Lines.Count - 1 do
    begin
      HasDeclShape(Lines[i], ColonAt[i], SemiAt[i]);
      // A declaration-shaped line that actually sits inside a multi-line
      // ()/[] group is not a real top-level declaration -- leave it alone.
      if Depths[i] > 0 then begin ColonAt[i]:= 0; SemiAt[i]:= 0; end;
    end;

    Out_:= TStringBuilder.Create;
    try
      i:= 0;
      while i < Lines.Count do
      begin
        if (ColonAt[i] = 0) or (SemiAt[i] = 0) then
        begin
          Out_.Append(Lines[i]);
          Out_.Append(#13#10);
          Inc(i);
          Continue;
        end;
        RunStart:= i;
        RunEnd:= i;
        j:= i + 1;
        while (j < Lines.Count) and (ColonAt[j] > 0) and (SemiAt[j] > 0) do
        begin
          RunEnd:= j;
          Inc(j);
        end;
        if RunEnd - RunStart >= 1 then
        begin
          // Compute target column = max of current semi columns,
          // capped by AMaxColumn.
          Target:= 0;
          for k:= RunStart to RunEnd do
            if SemiAt[k] > Target then Target:= SemiAt[k];
          if Target > AMaxColumn then Target:= 0;  // skip if too wide
          if Target > 0 then
          begin
            for k:= RunStart to RunEnd do
            begin
              Line:= Lines[k];
              Pad:= Target - SemiAt[k];
              if Pad > 0 then
                Line:= Copy(Line, 1, SemiAt[k] - 1) +
                  StringOfChar(' ', Pad) + Copy(Line, SemiAt[k], MaxInt);
              Out_.Append(Line);
              Out_.Append(#13#10);
            end;
          end
          else
            for k:= RunStart to RunEnd do
            begin
              Out_.Append(Lines[k]);
              Out_.Append(#13#10);
            end;
        end
        else
        begin
          Out_.Append(Lines[i]);
          Out_.Append(#13#10);
        end;
        i:= RunEnd + 1;
      end;
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end;
  finally
    Lines.Free;
  end;
end;

function AlignByAnchor(const S, AAnchor: string; AMaxColumn: Integer): string;
var
  Anchors : TArray<Integer>;
  Depths  : TArray<Integer>;
  i       : Integer;
  j       : Integer;
  Line    : string;
  Lines   : TStringList;
  Out_    : TStringBuilder;
  Pad     : Integer;
  RunCols : TArray<Integer>;
  RunLines: TArray<string>;
  StartIdx: Integer;
  Target  : Integer;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak        := #13#10;
    Lines.TrailingLineBreak:= True  ;
    Lines.Text             := S     ;
    SetLength(Anchors, Lines.Count);
    for i:= 0 to Lines.Count - 1 do Anchors[i]:= FindAnchorAtTopLevel(Lines[i], AAnchor);
    // Exclude lines inside a multi-line ()/[] group (enum bodies, array
    // literals, split parameter lists): they must not be aligned as if they
    // were top-level const/var/type declarations.
    Depths:= ComputeLineStartDepths(Lines);
    for i:= 0 to Lines.Count - 1 do
      if Depths[i] > 0 then Anchors[i]:= 0;
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
        j:= i + 1;
        while (j < Lines.Count) and (Anchors[j] > 0) and not StartsBlockBoundary(Lines[j]) do Inc(j);
        if j - StartIdx >= 2 then
        begin
          SetLength(RunLines, j - StartIdx);
          SetLength(RunCols , j - StartIdx);
          for i:= StartIdx to j - 1 do
          begin
            RunLines[i - StartIdx]:= Lines  [i];
            RunCols [i - StartIdx]:= Anchors[i];
          end;
          // Align to the tightest shared column rather than the
          // rightmost current anchor: this strips surplus padding
          // that every line carries before the anchor (compacting
          // the whole column left) while keeping it aligned. Equal
          // to the old max-anchor column when the run is tight.
          Target:= CompactedAnchorCol(RunLines, RunCols);
        end
        else
          Target:= 0;
        if (j - StartIdx >= 2) and (Target <= AMaxColumn) then
        begin
          for i:= StartIdx to j - 1 do
          begin
            Pad:= Target - Anchors[i];
            if Pad > 0 then
              Line:= Copy(Lines[i], 1, Anchors[i] - 1) + StringOfChar(' ', Pad) + Copy(Lines[i], Anchors[i], MaxInt)
            else if Pad < 0 then
              Line:= Copy(Lines[i], 1, Anchors[i] - 1 + Pad) + Copy(Lines[i], Anchors[i], MaxInt)
            else
              Line:= Lines[i];
            Out_.Append(Line);
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

// Shape record for the smart-assignment alignment pass. Two lines
// have the same "shape" when their punctuation/operator tokens form
// the same sequence -- so identifier names and literals are
// interchangeable, but `a.b := c(d, e);` and `x.y := z(w, v);` count
// as the same shape and get their `.`, `:=`, `(`, `,`, `)`, `;`
// padded to a shared column run.
//   Shape     - the sequence of structural token kinds (no idents,
//               whitespace, strings, numbers, chars, or comments).
//   Cols      - the 1-based column of each structural token on the
//               line, parallel to Shape.
//   HasAssign - true iff `:=` appears anywhere on the line (used as
//               the cheap precondition to skip lines that obviously
//               can't participate).
type
  TLineShape = record
    Shape    : TArray<TptTokenKind>;
    Cols     : TArray<Integer>;
    HasAssign: Boolean;
  end;

// Builds the TLineShape for a single line by re-lexing it.
// Identifiers, literals, whitespace, and comments are filtered out so
// only the structural skeleton remains; that skeleton is what gets
// compared between adjacent lines to decide whether they're alignment
// peers.
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

// Element-wise array compare on shape arrays. False as soon as a
// length or kind differs.
function ShapesMatch(const A, B: TArray<TptTokenKind>): Boolean;
var
  i: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for i:= 0 to High(A) do if A[i] <> B[i] then Exit(False);
  Result:= True;
end;

// The "smart" alignment pass: finds runs of adjacent lines that all
// contain `:=` and share an identical structural shape, then pads
// every shared anchor column-by-column so the structure lines up.
// Algorithm per shape-matched run:
//   1. Snapshot each line's text and per-anchor column array.
//   2. For each anchor index k (left-to-right):
//      - Compute MaxCol = rightmost column of anchor k across the run.
//      - If MaxCol > AMaxCol, abort this run entirely (no partial
//        alignment -- avoids ugly half-padded blocks).
//      - Else left-pad each line whose anchor k is to the left of
//        MaxCol, and shift its remaining anchor columns by the pad
//        width so subsequent iterations stay accurate.
//   3. Emit either the padded lines (success) or the originals (abort).
// Single-line "runs" (j - i < 2) and lines with empty shapes (no
// structural tokens at all) are passed through untouched.
// Column (1-based) of the first top-level `//` line comment in ALine
// -- one that is not inside a '...' string, a {...} brace comment, or
// a (*...*) comment. Returns 0 when the line carries no such comment.
// Used by SmartAlignAssignments to optionally pull trailing comments
// to a shared column across a shape-matched run.
function TopLevelLineCommentCol(const ALine: string): Integer;
var
  i                       : Integer;
  InString, InBrace, InPar: Boolean;
begin
  Result   := 0    ;
  InString := False;
  InBrace  := False;
  InPar    := False;
  i        := 1    ;
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
    if ALine[i] = '''' then
    begin
      InString:= True;
      Inc(i);
      Continue;
    end;
    if ALine[i] = '{' then
    begin
      InBrace:= True;
      Inc(i);
      Continue;
    end;
    if (i + 1 <= Length(ALine)) and (ALine[i] = '(') and (ALine[i + 1] = '*') then
    begin
      InPar:= True;
      Inc(i, 2);
      Continue;
    end;
    if (i + 1 <= Length(ALine)) and (ALine[i] = '/') and (ALine[i + 1] = '/') then
      Exit(i);
    Inc(i);
  end;
end;

function SmartAlignAssignments(const S: string; AMaxCol: Integer; AMatchShapes: Boolean; AMinAnchors, ACommentMaxShift: Integer): string;
var
  AnyOver : Boolean;
  ColCols : TArray<Integer>;
  ColLines: TArray<string>;
  i       : Integer;
  Info    : TArray<TLineShape>;
  j       : Integer;
  k       : Integer;
  Lines   : TStringList;
  Out_    : TStringBuilder;
  Pad     : Integer;
  Target  : Integer;
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
        // Eligibility: a line joins an alignment run if it carries a
        // `:=` (original behaviour) OR -- when AlignMatchingShapes is
        // on -- its structural skeleton has at least AMinAnchors
        // anchors. ShapesMatch still demands an identical skeleton
        // across the run, so the min-anchor floor only suppresses
        // trivial 1-2 symbol shapes (e.g. every `Foo(x);`) from
        // triggering noisy column padding in ordinary code.
        //
        // Exception: a declaration-colon line -- shape's first anchor
        // is `:` and there is no `:=` (a `name : type ;` field/var).
        // AlignByAnchor(':') already aligns those uniformly across the
        // whole block; the type-name token class fragments the shape
        // (keyword `string` keeps a `string` anchor, identifier types
        // like `integer`/`TStringList` do not), so letting SmartAlign
        // re-compact per sub-shape shatters one uniform field list
        // into staggered columns. Leave declaration colons to
        // AlignByAnchor by treating them as shape-ineligible.
        if not (Info[i].HasAssign or (AMatchShapes and (Length(Info[i].Shape) >= AMinAnchors) and (Length(Info[i].Shape) > 0) and (Info[i].Shape[0] <> ptColon))) then
        begin
          Out_.Append(Lines[i]);
          Out_.Append(#13#10);
          Inc(i);
          Continue;
        end;
        j:= i + 1;
        while (j < Lines.Count) and (Info[j].HasAssign or (AMatchShapes and (Length(Info[j].Shape) >= AMinAnchors) and (Length(Info[j].Shape) > 0) and (Info[j].Shape[0] <> ptColon)))
          and ShapesMatch(Info[i].Shape, Info[j].Shape) do Inc(j);
        if (j - i >= 2) and (Length(Info[i].Shape) > 0) then
        begin
          SetLength(WorkLine, j - i);
          SetLength(WorkCols, j - i);
          for k:= 0 to (j - i) - 1 do
          begin
            // Normalize anchor spacing FIRST (tight `.`, no space before
            // `;`), then measure columns from the normalized text. This
            // guarantees the run carries zero rule-violating surplus, so
            // the compaction below only ever adds alignment padding -- it
            // never preserves a stray pre-anchor space just because every
            // line happened to have one.
            WorkLine[k]:= TightenAnchorSpacingInLine(Lines[i + k]);
            WorkCols[k]:= ComputeLineShape(WorkLine[k]).Cols;
          end;

          AnyOver:= False;
          SetLength(ColLines, j - i);
          SetLength(ColCols , j - i);
          for k:= 0 to Length(Info[i].Shape) - 1 do
          begin
            // Never align a line-terminal `;`. Padding to reach a
            // shared column would insert a run of spaces immediately
            // before the semicolon -- exactly the surplus the tighten
            // pass exists to remove, and ruinous on declaration runs
            // (property/var lists) whose tails vary in length. An
            // interior `;` (record-literal field separator, followed
            // by more anchors) is still aligned, so grid-shaped const
            // arrays keep their columns.
            if (k = High(Info[i].Shape)) and (Info[i].Shape[k] = ptSemiColon) then Continue;
            for var L: Integer:= 0 to (j - i) - 1 do
            begin
              ColLines[L]:= WorkLine[L]   ;
              ColCols [L]:= WorkCols[L][k];
            end;
            // Tightest shared column for this anchor: compacts away
            // padding common to every line in the run (e.g. inserted
            // by an earlier anchor or an upstream align pass) instead
            // of freezing it into the alignment. Identical to the old
            // max-column when the run is already tight.
            Target:= CompactedAnchorCol(ColLines, ColCols);
            if Target > AMaxCol then
            begin
              AnyOver:= True;
              Break;
            end;
            for var L: Integer:= 0 to (j - i) - 1 do
            begin
              Pad:= Target - WorkCols[L][k];
              if Pad > 0 then
                WorkLine[L]:= Copy(WorkLine[L], 1, WorkCols[L][k] - 1) + StringOfChar(' ', Pad) + Copy(WorkLine[L], WorkCols[L][k], MaxInt)
              else if Pad < 0 then
                WorkLine[L]:= Copy(WorkLine[L], 1, WorkCols[L][k] - 1 + Pad) + Copy(WorkLine[L], WorkCols[L][k], MaxInt);
              if Pad <> 0 then
                for var M: Integer:= k to High(WorkCols[L]) do WorkCols[L][M]:= WorkCols[L][M] + Pad;
            end;
          end; // for

          // Operator padding overflowed AMaxCol: drop it and fall
          // back to the raw lines. The run is still a shape-matched
          // peer group, so trailing-comment alignment below may yet
          // apply to the originals.
          if AnyOver then
            for k:= 0 to (j - i) - 1 do WorkLine[k]:= Lines[i + k];

          // Optional trailing-comment alignment. A shape-matched run
          // whose every member carries a top-level `//` gets those
          // comments pulled to one column -- but only when no line
          // must travel more than ACommentMaxShift spaces to get
          // there. That cap keeps far-flung comments where the author
          // put them instead of tearing open a ragged gap, and
          // ACommentMaxShift = 0 disables the step entirely. The
          // shared column is still bounded by AMaxCol.
          if ACommentMaxShift > 0 then
          begin
            var AllHaveCo: Boolean:= True ;
            var MaxCoCol : Integer:= 0    ;
            SetLength(ColCols, j - i);
            for k:= 0 to (j - i) - 1 do
            begin
              ColCols[k]:= TopLevelLineCommentCol(WorkLine[k]);
              if ColCols[k] = 0 then
              begin
                AllHaveCo:= False;
                Break;
              end;
              if ColCols[k] > MaxCoCol then MaxCoCol:= ColCols[k];
            end;
            if AllHaveCo then
            begin
              var MaxShift: Integer:= 0;
              for k:= 0 to (j - i) - 1 do
                if MaxCoCol - ColCols[k] > MaxShift then MaxShift:= MaxCoCol - ColCols[k];
              if (MaxShift > 0) and (MaxShift <= ACommentMaxShift) and (MaxCoCol <= AMaxCol) then
                for k:= 0 to (j - i) - 1 do
                begin
                  Pad:= MaxCoCol - ColCols[k];
                  if Pad > 0 then
                    WorkLine[k]:= Copy(WorkLine[k], 1, ColCols[k] - 1) + StringOfChar(' ', Pad) + Copy(WorkLine[k], ColCols[k], MaxInt);
                end;
            end;
          end;

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

// ===== Reflow =====
// Reflow is the most invasive string pass: it deletes user-supplied
// line breaks where they aren't structurally required, and merges
// short adjacent lines that fit MaxLen when joined. Off-switch:
// AOpts.ReflowLines = False (set in INI / via --no-reflow).
//
// The merge decision lives in CurBlocksMerge / NextBlocksMerge below.
// A merge is REFUSED when either:
//   * the current line ends in a structural break (`;`, `.`, `}`,
//     `begin`, `end`, section keyword, visibility keyword, `try`,
//     `else` not followed by `if`, `uses`, etc.)
//   * the next line starts with one (`begin`, `end`, `else`, `until`,
//     `var`, `procedure`, line comment, directive, ...)
// Block-comment / string-literal interiors are tracked so we never
// merge across an open `{...}` or `(*...*)` boundary.
function ReflowLineBreaks(const S: string; AMaxLen: Integer): string;

  // True iff ALine starts with AWord, case-insensitively, with a
  // non-identifier boundary after the word (so `class` matches but
  // `classes` does not).
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

  // True iff ALine ends with AWord, case-insensitively, with a
  // non-identifier boundary before the word.
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

  // True if ALine contains a `//` line comment at top level or leaves
  // a `{...}` / `(*...*)` block open at end-of-line. Either case
  // forbids merging the next line into this one -- a line comment
  // would swallow it, and an open block makes "where does this end"
  // ambiguous.
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

  // Detects `... class(TFoo, IBar)` / `... interface(IBaz)` style
  // lines -- where the parenthesised ancestor list is the actual end
  // of the line. Used to block merging the next member declaration
  // onto the class header line, which would look terrible.
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

  // Returns True when the CURRENT line forbids being merged with the
  // following one. The big run of EndsWordCI checks below is the rule
  // book: every keyword that terminates a structural construct ends
  // the line. The `else` case has one exception -- `else if ...` is
  // a chain we WANT to keep on one line, so an `else` is allowed to
  // merge if the next line starts with `if`.
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
    // A line ending in an unclosed `(` / `[` is the opener of a multi-line
    // group that the structural emitter chose NOT to inline (it overflows or
    // contains a line comment -- e.g. an enum/array body). Pulling the first
    // member up onto the opener re-creates the half-merged enum bug, so keep
    // the break.
    if (R[Length(R)] = '(') or (R[Length(R)] = '[') then Exit(True);
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

  // Returns True when the NEXT line forbids being merged onto its
  // predecessor. Mirrors CurBlocksMerge from the opposite direction:
  // structural keywords, line comments, directives, and section
  // openers all force a line break to be preserved.
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

  // Returns a Boolean[Lines.Count] where Locked[i] = True iff line i
  // is "inside" a block comment that was already open at the start of
  // that line, OR opens a new block comment that stays open at end of
  // line. Locked lines never participate in merge decisions, so block
  // comment interiors pass through verbatim.
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

// ===== Blank-line policy =====
// Enforces minimum blank-line counts before structurally important
// lines. Three independent settings:
//   BlanksBeforeSection - before interface/implementation/
//                         initialization/finalization
//   BlanksBeforeType    - before `type`
//   BlanksBeforeMethod  - before top-level procedure/function/
//                         constructor/destructor (class methods are
//                         excluded so we don't blanks before
//                         `class procedure Foo`)
// When multiple rules apply on the same line, the maximum wins.
// Existing blank lines are counted backwards and only the deficit is
// inserted, so this pass is idempotent.
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

// Caps consecutive blank lines at AMax. Runs after EnforceBlankLines
// so the floors set there are still respected -- the AMax used in the
// pipeline is computed as max(MaxBlankLines, BlanksBeforeSection,
// BlanksBeforeMethod, BlanksBeforeType). AMax < 0 disables the pass.
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

// True for the three comment token kinds: {brace}, (*Borland*), //line.
function IsCommentKind(k: TptTokenKind): Boolean;
begin
  Result:= k in [ptAnsiComment, ptBorComment, ptSlashesComment];
end;

// ===== Structural re-indentation =====
// Re-emits ASrc with every line's leading whitespace replaced by N *
// AIndent spaces, where N is the structural depth at that point.
// Existing leading whitespace is ignored (this pass is the source of
// truth for indentation). The depth tracking is driven by the token
// stream, not by pattern matching on lines, so it handles weird
// hand-formatted input correctly.
//
// Depth state lives on Stack (TList<TptTokenKind>), one entry per
// open block. Pushers: begin / case / try / asm / record / object /
// class / interface / type / var / const. Poppers: end / until /
// procedure-body completion / `;` after a section item.
//
// Bonuses (lines indent one level deeper than the structural depth
// would suggest):
//   * Members inside private/public/protected/published (InVisibility).
//   * Single-statement bodies after then/do/else (BodyBonus,
//     persists across multi-line bodies until the next stmt break).
//   * `case`-label bodies after `Label:`.
//
// Within parens/brackets (ParensDepth > 0) and within a uses clause,
// re-indentation is suppressed -- those constructs are rendered by
// the structural walker, not the re-indenter.
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
            ptProcedure, ptFunction, ptConstructor, ptDestructor: if (not InClassOrRecord) and (ParensDepth = 0) then
            // ParensDepth = 0 distinguishes a real procedure/function
            // declaration from an inline anonymous method expression
            // (e.g. CallSomething(procedure(X) begin ... end)). The
            // anonymous form's inner begin/end is balanced on its own,
            // so we must NOT push a pending-proc marker for it -- if
            // we did, that marker would never be consumed, leaving
            // OpenProcRegions elevated and over-indenting every line
            // after the call. (Bug repro: inline anon proc, 2026-05-15.)
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

// ===== Uses-clause rendering =====
// The uses clause is special-cased because the standard parens/comma
// breaking rules don't apply -- it has no parentheses and uses
// comma-first formatting when broken.

// Walks the token range covering one uses clause body (between the
// `uses` keyword and the closing `;`) and returns the list of "name"
// strings. Each name is the full identifier including dots; a name
// followed by `in 'path'` is captured as the single string
// `Unit in 'path'`. Sets AHasInClause = True when any `in` form is
// present (which forces breaking even when the joined inline form
// would fit, because mixed inline+in looks awful).
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

// Renders one uses/contains/requires clause, replacing it inline in
// the token stream. Two output forms:
//
//   Inline (chosen when UsesAlwaysBreak is False AND the joined form
//   fits within MaxLen AND no `in 'path'` items appear):
//       uses System.SysUtils, System.Classes;
//
//   Broken (default; chosen otherwise):
//       uses
//         System.SysUtils
//       , System.Classes
//       ;
//
// The broken form uses comma-first style at column (BaseCol + Indent),
// with the closing semicolon on its own line at the same column. This
// makes diffs cleaner when units are added/removed -- the line being
// added is a complete row including its comma.
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

// ===== Parens-group rendering helpers =====
// Used by the structural walker to decide whether a parenthesised
// group fits inline or needs to be broken one-argument-per-line, and
// to actually render it both ways.

// Concatenates tokens [AFrom..ATo] onto a single line, collapsing any
// internal whitespace/CRLF runs to a single space. Pre-whitespace
// before each token is normalised to either '' (when next to opening
// punctuation) or ' ' (otherwise). The result has NO leading or
// trailing whitespace; callers add indentation as needed.
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

// True iff any token in [AFrom..ATo] has a CR or LF inside its own
// text. Multi-line tokens (block comments, multi-line strings) can't
// be safely flattened to one line, so the structural walker skips
// the inline-rendering optimisation when this returns True.
function RangeHasMultiLineToken(const ATokens: TTokenList; AFrom, ATo: Integer): Boolean;
var
  i: Integer;
begin
  for i:= AFrom to ATo do if not (ATokens[i].Kind in [ptSpace, ptCRLF, ptCRLFCo]) then
  if (Pos(#10, ATokens[i].Text) > 0) or (Pos(#13, ATokens[i].Text) > 0) then
    Exit(True);
  Result:= False;
end;

// True iff any token in [AFrom..ATo] is a `//` / `///` line comment.
// A line comment runs to physical end-of-line, so a range that
// contains one can NEVER be flattened onto a single rendered line --
// every token placed after it would be swallowed into the comment
// (silently commenting out code: enum members, `)`, `;`, the next
// argument). Callers that would otherwise inline-render or
// item-flatten a range must consult this and fall back to verbatim,
// line-preserving emission instead. The lexer classifies both `//`
// and `///` (XMLDoc) as ptSlashesComment, so this covers both.
function RangeHasLineComment(const ATokens: TTokenList; AFrom, ATo: Integer): Boolean;
var
  i: Integer;
begin
  for i:= AFrom to ATo do if ATokens[i].Kind = ptSlashesComment then
    Exit(True);
  Result:= False;
end;

// One item slot in a comma-separated parens/brackets group.
//   First, Last     - token range of the item payload (no commas).
//   CmtFirst,
//   CmtLast         - optional token range of an inline comment that
//                     followed the comma on the same source line as
//                     that comma; -1/-1 when no such comment. We keep
//                     these so the inline brace `{...}` after a
//                     parameter stays glued to that parameter when
//                     the group is broken.
type
  TItemRange = record
    First, Last      : Integer;
    CmtFirst, CmtLast: Integer;
  end;

// Walks the token range [AOpenIdx + 1 .. ACloseIdx - 1] (i.e. between
// matched `(` `)` or `[` `]`) and slices it at top-level commas. Each
// slice becomes a TItemRange. Nested parens/brackets are tracked via
// Depth so commas inside an inner pair don't split the outer item.
// Leading and trailing whitespace tokens at each boundary are absorbed
// into the surrounding slot rather than into an item, so trim and
// re-render are clean. After a top-level comma, the walker looks
// ahead for an inline comment whose `Line` equals the comma's line --
// that comment is captured as the item's CmtFirst/CmtLast.
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

// ===== Block-end label discovery =====

// Returns the keyword to use in the trailing `// keyword` comment
// appended to a long block's closing `end`. Cheap path: if the
// opener is itself record/case/try/asm/object, use that keyword
// literally. For a plain `begin`, walk backwards through whitespace,
// comments, and conditional directives looking for the introducing
// keyword (while / for / if / else / procedure / function / try /
// initialization / finalization / a prior `end` which we treat as
// "anonymous begin"). The Limit guard caps the backwards scan at 300
// non-trivial tokens so pathological input can't pin the formatter.
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

// ===== FormatSource =====
// Top-level orchestrator. Runs the pipeline described in the unit
// header comment. The first stage is token-level (capitalisation,
// assignment spacing); the second is a structural emission driven by
// WalkGroup over the TGroup tree; the third is a sequence of pure
// string -> string passes for indentation, blank lines, line breaks,
// and (optionally) reflow and column alignment.
//
// Shared mutable state for the walker (in scope of the nested procs):
//   Tokens       - the lexed token stream (after capitalisation /
//                  assign-spacing passes have mutated it).
//   Root         - the parsed TGroup tree.
//   Sb           - StringBuilder for the rendered output.
//   Cursor       - next un-emitted token index. Incremented as
//                  WalkGroup descends into / past child groups.
//   CurCol,
//   CurLine      - track the current output position so the walker
//                  can decide whether a parens group fits inline at
//                  the current column or must be broken.
//   PendingLabel - block-end label that needs to be appended to the
//                  next-emitted closing `end`. Buffered here because
//                  the label is computed at the moment we leave a
//                  child group, but must appear AFTER the `end`
//                  token text and BEFORE the next CRLF.
function FormatSource(const ASource: string; const AOpts: TYadfOptions): string;
var
  CurCol      : Integer;
  CurLine     : Integer;
  Cursor      : Integer;
  PendingLabel: string;
  Root        : TGroup;
  Sb          : TStringBuilder;
  Tokens      : TTokenList;

  // Updates CurCol/CurLine after every text emission. Tabs are
  // counted as TabWidth columns; CR is ignored (column reset happens
  // on LF). Plain ASCII characters all count as one column -- we
  // don't try to handle ambiguous-width Unicode here because the
  // input is Pascal source.
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

  // Appends S to the output StringBuilder, flushing any PendingLabel
  // first. If S contains a line break, the label is spliced in BEFORE
  // the break -- e.g. `end;` + pending `// while` + `\r\n` becomes
  // `end; // while\r\n`. CurCol/CurLine are kept in sync via
  // UpdateColumn so subsequent walker decisions remain accurate.
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

  // Emits a parens/brackets group in broken form, one item per line:
  //     Header(
  //         item1,                <- items at LineWS + 2*Indent
  //         item2,
  //         item3
  //     );                        <- close at LineWS (same as opener)
  // Each item that ITSELF overflows AND is a single nested parens/
  // brackets group with multiple items is recursively broken. Inline
  // brace comments captured into Items[i].CmtFirst..CmtLast stick
  // with the preceding item, on the same output line.
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
      // An item that itself contains a `//`/`///` line comment cannot
      // be inline-flattened (it would comment out everything after the
      // `//` on the rendered line). Emit it verbatim, preserving its
      // source line breaks; ReindentByDepth re-indents it afterward.
      if RangeHasLineComment(Tokens, Items[i].First, Items[i].Last) then
        EmitTokenRange(Items[i].First, Items[i].Last)
      else
      begin
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
      end;
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

  // The structural emission walker. Recursively descends the TGroup
  // tree, handing off to specialised renderers per group kind:
  //   gkUses     -> RenderUsesGroup (uses-clause formatter)
  //   gkParens / gkBrackets:
  //     - fits inline at current column -> InlineRenderRange
  //     - overflows AND has >1 comma item -> RenderParensBroken
  //     - else descend into children (let inner groups break)
  //   gkBlock and everything else -> recurse, emitting tokens
  //                                   between child groups verbatim.
  // After each child closes, two side-channels may fire:
  //   * MarkUnclosed: emits a // TODO -oYADF marker if Child was
  //     ForceClosed by the group parser (unmatched begin/record).
  //   * LabelLongBlocks: stores a PendingLabel that EmitText will
  //     splice in on the next CRLF if the block was long enough.
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
        // A `//`/`///` line comment anywhere inside the group makes
        // BOTH flattening paths unsafe: InlineRenderRange and
        // RenderParensBroken's per-item inline render would place the
        // closing `)`/`]`, following members, or the next argument on
        // the comment's physical line and comment them out (the enum /
        // argument-list corruption bug). Fall through to WalkGroup,
        // which emits the group's tokens verbatim and keeps the
        // developer's own line breaks (reflow is already comment-safe).
        if RangeHasLineComment(Tokens, Child.OpenIdx, Child.CloseIdx) then
          WalkGroup(Child)
        else if (CurCol + InlineW > AOpts.MaxLen) and (Length(CollectParensItems(Tokens, Child.OpenIdx, Child.CloseIdx)) > 1) then
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

  // Scans Line for top-level break points usable by the line-overflow
  // breaker. Two categories are collected:
  //   * Word operators with surrounding spaces: ` + ` ` - ` ` and `
  //     ` xor ` (with whole-word boundaries enforced by AddIfWord).
  //   * Commas inside parens/brackets at any nesting depth, where
  //     the break point is just AFTER the comma+space.
  // Returns positions are 1-based byte indices. String/brace/paren
  // comment interiors are skipped so we don't split a literal or a
  // documentation block.
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

  // Greedy line-wrapping at top-level operators/commas. Strategy:
  //   1. Find all candidate break positions in the current line.
  //   2. Pick the rightmost position that's still <= MaxLen (so the
  //      first piece is as full as possible).
  //   3. If no candidate fits, fall back to the leftmost candidate
  //      after the leading indent (the line will overflow, but at
  //      least we tried).
  //   4. Emit head, push tail to the next iteration with NewIndent
  //      (LeadingIndent + AOpts.Indent extra). The continuation
  //      starts WITH the operator so the structure reads "op operand"
  //      at the new column.
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

  // Whole-output pass for overflow handling. Splits the rendered text
  // into lines, computes a Locked[] mask using the same block-comment
  // tracker as ReflowLineBreaks (lines inside a `{...}` or `(*...*)`
  // are never broken), then runs BreakLineByOperators on every
  // remaining line whose length exceeds MaxLen. Returns the modified
  // text. This is the LAST defence against overflow before optional
  // reflow; without it, long lines from heavily-nested expressions
  // would survive the pipeline unchanged.
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

// FormatSource body: see the pipeline diagram in the unit header.
// The code below is a literal rendering of those stages.
begin
  Tokens:= LoadTokensFromString(ASource);
  try
    // Stage 1: token-level passes (mutate Tokens in place).
    ApplyCapitalization(Tokens, AOpts);
    NormalizeAssignSpacing(Tokens, AOpts);
    Root:= ParseGroups(Tokens);
    try
      Sb:= TStringBuilder.Create;
      try
        // Stage 2: structural emission. WalkGroup writes into Sb.
        Cursor      := 0 ;
        CurCol      := 0 ;
        CurLine     := 1 ;
        PendingLabel:= '';
        WalkGroup(Root);
        // A trailing PendingLabel (block-end label on the last block
        // of the file) needs an explicit CRLF to flush.
        if PendingLabel <> '' then
        begin
          EmitText(#13#10);
          PendingLabel:= '';
        end;

        // Stage 3: string-level passes. Order matters here:
        //   * CRLF first so every subsequent pass sees a uniform
        //     line terminator.
        //   * Trim trailing whitespace before any indent-aware pass.
        //   * Re-indent BEFORE blank-line/overflow handling so those
        //     passes see the canonical indented form.
        //   * Reflow (when on) collapses multi-line statements; we
        //     re-indent again because the merge may have changed
        //     structural depth on some lines.
        //   * CollapseBlankLines uses the MAX of the user's caps to
        //     avoid clobbering EnforceBlankLines' results.
        //   * Pass-2 alignment runs LAST so the columns it inserts
        //     are never disturbed by a later pass.
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

        // Stage 4: column alignment (Pass 2). CollapseInteriorSpaces
        // normalises spacing so anchor columns are predictable.
        // SplitMultiVarDecls runs first so the alignment sees one
        // declaration per line.
        if AOpts.SplitMultiVarDecls then
          Result:= SplitMultiVarDeclarations(Result);
        if AOpts.AlignTypeColon or AOpts.AlignConstEquals or AOpts.AlignSmartAssign then
          Result:= CollapseInteriorSpaces(Result);
        if AOpts.AlignTypeColon then
          Result:= AlignByAnchor(Result, ':', AOpts.AlignMaxColumn);
        if AOpts.AlignDeclSemicolons then
          Result:= AlignDeclarationSemicolons(Result, AOpts.AlignMaxColumn);
        if AOpts.AlignConstEquals then
          Result:= AlignByAnchor(Result, '=', AOpts.AlignMaxColumn);
        if AOpts.AlignSmartAssign then
          Result:= SmartAlignAssignments(Result, AOpts.AlignMaxColumn, AOpts.AlignMatchingShapes, AOpts.AlignShapeMinAnchors,
            AOpts.AlignCommentMaxShift);
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
