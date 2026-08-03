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

// Format ASource per AOpts. The overload with ADeclineReason reports the
// content guard's verdict: '' when the output was accepted, otherwise the
// reason FormatSource DECLINED and returned the input unchanged (see
// YADF.Guard) -- callers that talk to a user should surface it instead of
// silently pretending the file was formatted.
/// <summary></summary>
/// <param name="ASource"></param>
/// <param name="AOpts"></param>
/// <returns>Observed: FormatSource(ASource, AOpts, Reason).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YADF.Layout.FormatSource (YADF.Layout.pas), YadfMain.FormatToStdout (YadfMain.pas), YadfMain.FormatToFile (YadfMain.pas), YadfMain.BatchFormat (YadfMain.pas), YadfMain.ProcessOneFile (YadfMain.pas) (+4 more)
/// Calls: YADF.Layout.FormatSource
/// Returns: FormatSource(ASource, AOpts, Reason)
/// Overload 1 of 2
/// Covered by: TestFormatSourceStillFormats
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatSource(const ASource: string; const AOpts: TYadfOptions): string; overload ;
/// <summary></summary>
/// <param name="ASource"></param>
/// <param name="AOpts"></param>
/// <param name="ADeclineReason"></param>
/// <returns>Observed: Length(InlineRenderRange(Tokens, G.OpenIdx + 1, G.CloseIdx - 1)); ''; Result + S[i]; Child; nil; True.</returns>
/// <remarks>
/// <!-- drag-lint:auto -->Shared mutable state for the walker (in scope of the nested procs): Tokens - the lexed token stream (after capitalisation / assign-spacing passes have mutated it). Root - the parsed TGroup tree. Sb - StringBuilder for the rendered output. Cursor - next un-emitted token index. Incremented as WalkGroup descends into / past child groups. CurCol, CurLine - track the current output position so the walker can decide whether a parens group fits inline at the current column or must be broken. PendingLabel - block-end label that needs to be appended to the next-emitted closing `end`. Buffered here because the label is computed at the moment we leave a child group, but must appear AFTER the `end` token text and BEFORE the next CRLF.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: YadfMain.FormatToStdout (YadfMain.pas), YadfMain.FormatToFile (YadfMain.pas), YadfMain.BatchFormat (YadfMain.pas), YadfMain.ProcessOneFile (YadfMain.pas), TestFormatSourceStillFormats (GuardTest.dpr) (+3 more)
/// Calls: Add, AddIfWord, Append, Assigned, BlockAlreadyLabeled, BreakLineByOperators, BreakLongLines, CharInSet, CollectParensItems, ComputeBlockCommentLock (+53 more)
/// Overload 2 of 2
/// Complexity: 24 (cyclomatic), 603 lines
/// Covered by: TestFormatSourceStillFormats
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatSource(const ASource: string; const AOpts: TYadfOptions; out ADeclineReason: string): string; overload;

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
  , YADF.Guard
  , YADF.LineScan
  ;

const
  // Forced CRLF on every platform. System.sLineBreak is platform-dependent
  // (#10 on POSIX), so we use an explicit constant to keep output identical
  // everywhere. Also keeps the source clean of scattered #13#10 literals.
  CR   = #13;
  LF   = #10;
  CRLF = CR + LF;

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
  for i:= Length(APre) downto 1 do if (APre[i] = LF) or (APre[i] = CR) then
  begin
    LastNL:= i;
    Break;
  end;
  Result:= Length(APre) - LastNL;
end;

// Canonicalises every line break to CRLF. We collapse CRLF -> LF first
// so mixed input (CRLF + bare LF) folds to a single LF run, then
// expand back. This deliberately produces CRLF regardless of platform.
function NormalizeCRLF(const S: string): string;
begin
  Result:= StringReplace(S     , CRLF, LF  , [rfReplaceAll]);
  Result:= StringReplace(Result, LF  , CRLF, [rfReplaceAll]);
end;

// Strips trailing spaces/tabs from every line and preserves the final
// trailing line break. Run late in the pipeline so passes that emit
// intermediate trailing whitespace don't accumulate it in the output.
function TrimTrailingWhitespace(const S: string): string;
var
  i    : Integer       ;
  Lines: TStringList   ;
  Out_ : TStringBuilder;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Out_.Append(TrimRight(Lines[i]));
        Out_.Append(CRLF);
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
  if S = '' then
    Exit(False);
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
  C: Char   ;
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
end; // function

// Uppercases the directive name in a compiler-directive comment:
// {$ifdef X} -> {$IFDEF X}, {$define} -> {$DEFINE}, etc. Only the
// leading alphabetic run after `{$` is touched -- arguments, payload
// text, and the closing `}` are preserved exactly.
function UpperDirectiveName(const S: string): string;
var
  C        : Char   ;
  i        : Integer;
  NameStart: Integer;
begin
  Result:= S;
  if (Length(Result) < 3) or (Result[1] <> '{') or (Result[2] <> '$') then
    Exit;
  NameStart:= 3;
  i        := NameStart;
  while (i <= Length(Result)) and (((Result[i] >= 'a') and (Result[i] <= 'z')) or ((Result[i] >= 'A') and (Result[i] <= 'Z'))) do
  begin
    C:= Result[i];
    if (C >= 'a') and (C <= 'z') then
      Result[i]:= Chr(Ord(C) - 32);
    Inc(i);
  end;
end; // function

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
  NewT: TToken ;
  T   : TToken ;
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
            NewT.Kind:= ptSpace;
            NewT.ExID:= ptUnknown;
            NewT.Text:= ' ';
            NewT.Pre := '';
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

// Puts exactly one space around binary operators (+ - * / = <= >= <>) per
// AOpts.SpaceAroundOperators. Token-based, so it tells a binary `-`/`+` from a
// unary one and never touches bare `<`/`>` (generic brackets), `..` ranges,
// `^` pointers, `@` address-of, comments, or strings (different token kinds).
// An operator at end-of-line is left untouched so multi-line RHS reflow still
// works (mirrors NormalizeAssignSpacing). Rebuilds the token list so insert/
// delete bookkeeping stays simple.
procedure NormalizeOperatorSpacing(const ATokens: TTokenList; const AOpts: TYadfOptions);
var
  Src     : TArray<TToken>;
  Outp    : TTokenList    ;
  i       : Integer       ;
  j       : Integer       ;
  k       : Integer       ;
  PrevKind: TptTokenKind  ;
  IsBinary: Boolean       ;
  NewT    : TToken        ;

  function MakeSpace(ALine: Integer): TToken;
  begin
    Result.Kind:= ptSpace;
    Result.ExID:= ptUnknown;
    Result.Text:= ' ';
    Result.Pre := '';
    Result.Line:= ALine;
    Result.Col := 0;
  end;

// Kind of the last non-space token already emitted; ptCRLF (line start)
// when there is none yet on this line.
  function LastRealKind: TptTokenKind;
  var
    k: Integer;
  begin
    k:= Outp.Count - 1;
    while (k >= 0) and (Outp[k].Kind = ptSpace) do
      Dec(k);
    if k < 0 then
      Result:= ptCRLF
    else
      Result:= Outp[k].Kind;
  end;

begin
  Src := ATokens   .ToArray;
  Outp:= TTokenList.Create;
  try
    i:= 0;
    while i <= High(Src) do
    begin
      if Src[i].Kind in [ptStar, ptSlash, ptEqual, ptNotEqual, ptLowerEqual, ptGreaterEqual, ptPlus, ptMinus] then
      begin
        PrevKind:= LastRealKind;
        // Split scientific-notation exponent sign. The lexer's NumberProc
        // swallows the exponent letter into the number token but only marks it
        // ptFloat when a '.' was seen, so a signed exponent arrives split:
        //   0.10000E-2 -> ptFloat('0.10000E') '-' '2'
        //   5E-16      -> ptIntegerConst('5E')  '-' '16'
        // Either way the preceding number token ends in E/e. Spacing the sign
        // as a binary operator yields `... E - 2`, an invalid real (E2053), so
        // re-merge the number + sign + digits back into one float token. The
        // leading-digit guard excludes hex ($5E - 16 is a real subtraction).
        if Src[i].Kind in [ptPlus, ptMinus] then
        begin
          k:= Outp.Count - 1;
          while (k >= 0) and (Outp[k].Kind = ptSpace) do
            Dec(k);
          j:= i + 1;
          while (j <= High(Src)) and (Src[j].Kind = ptSpace) do
            Inc(j);
          if (k >= 0) and (j <= High(Src)) and (Src[j].Kind = ptIntegerConst) and (Outp[k].Kind in [ptFloat, ptIntegerConst]) and (Length(Outp[k].Text) > 0)
            and CharInSet(Outp[k].Text[1], ['0'..'9']) and CharInSet(Outp[k].Text[Length(Outp[k].Text)], ['E', 'e']) then
          begin
            while Outp.Count - 1 > k do Outp.Delete(Outp.Count - 1); // drop stray spaces
            NewT:= Outp[k];
            NewT.Kind:= ptFloat;
            NewT.Text:= NewT.Text + Src[i].Text + Src[j].Text;
            Outp[k]:= NewT;
            i:= j + 1;
            Continue;
          end;
        end; // if
        if Src[i].Kind in [ptPlus, ptMinus] then
          // binary only when the previous real token ends an operand;
          // otherwise it is a unary sign and stays attached.
          IsBinary:= PrevKind in [ptIdentifier, ptIntegerConst, ptFloat, ptStringConst, ptAsciiChar, ptRoundClose, ptSquareClose, ptPointerSymbol]
        else
          IsBinary:= True;
        if PrevKind = ptCRLF then IsBinary:= False; // never at line start
        if IsBinary then
        begin
          // exactly one space before
          while (Outp.Count > 0) and (Outp[Outp.Count - 1].Kind = ptSpace) do
            Outp.Delete(Outp.Count - 1);
          Outp.Add(MakeSpace(Src[i].Line));
          Outp.Add(Src[i]);
          // exactly one space after -- unless the operator sits at end of
          // line (next real token is a CRLF or end of stream), in which case
          // leave the trailing layout for the reflow pass.
          j:= i + 1;
          while (j <= High(Src)) and (Src[j].Kind = ptSpace) do
            Inc(j);
          if (j <= High(Src)) and (Src[j].Kind <> ptCRLF) then
          begin
            Outp.Add(MakeSpace(Src[i].Line));
            i:= j;
            Continue;
          end
          else
          begin
            i:= i + 1;
            Continue;
          end;
        end; // if
      end; // if
      Outp.Add(Src[i]);
      Inc(i);
    end; // while
    ATokens.Clear;
    ATokens.AddRange(Outp.ToArray);
  finally
    Outp.Free;
  end; // try
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
  Existing     : string                     ;
  FirstMap     : TDictionary<string, string>;
  i            : Integer                    ;
  IsLiteralKind: Boolean                    ;
  Key          : string                     ;
  T            : TToken                     ;
begin
  if AOpts.LowercaseKeywords then
    for i:= 0 to ATokens.Count - 1 do
    begin
      T:= ATokens[i];
      IsLiteralKind:= T.Kind in [
        ptIdentifier, ptIntegerConst, ptFloat, ptStringConst, ptStringDQConst, ptAsciiChar, ptAnsiComment, ptBorComment, ptSlashesComment, ptCRLF, ptCRLFCo, ptSpace, ptNull,
        ptUnknown, ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect, ptIfEndDirect, ptDefineDirect, ptUndefDirect,
        ptIncludeDirect, ptResourceDirect, ptCompDirect, ptScopedEnumsDirect];
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
      if T.Kind in [
        ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect, ptIfEndDirect, ptDefineDirect, ptUndefDirect, ptIncludeDirect,
        ptResourceDirect, ptCompDirect, ptScopedEnumsDirect] then
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
      end; // for
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
  i    : Integer       ;
  j    : Integer       ;
  Line : string        ;
  Lines: TStringList   ;
  Out_ : TStringBuilder;
  Tab  : string        ;
begin
  if ATabWidth <= 0 then
    Exit(S);
  Tab:= StringOfChar(' ', ATabWidth);
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
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
        Out_.Append(CRLF);
      end; // for
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
  Cur        : string        ;
  CurTrimmedR: string        ;
  i          : Integer       ;
  Joined     : string        ;
  Lines      : TStringList   ;
  Next       : string        ;
  NextTrim   : string        ;
  Out_       : TStringBuilder;

  function LeadingSpaces(const ALine: string): Integer;
  var
    k: Integer;
  begin
    Result:= 0;
    for k:= 1 to Length(ALine) do if ALine[k] = ' ' then Inc(Result)
    else
      Break;
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
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
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
              Out_.Append(CRLF  );
              Inc(i, 2);
              Continue;
            end;
          end;
        end; // if
        Out_.Append(Cur );
        Out_.Append(CRLF);
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
  St: TLineScanState;
  i : Integer       ;
begin
  Result:= 0;
  St.Reset;
  i:= 1;
  while True do
  case St.SkipNonCode(ALine, i) of
    seEndOfLine  : Exit   ;
    seLineComment: Exit(0);
    seCode       :
    begin
      if (St.Depth = 0) and (Copy(ALine, i, Length(AAnchor)) = AAnchor) then
      begin
        // Looking for `:`: skip the `:` of a `:=` assignment.
        if (AAnchor = ':') and (i + 1 <= Length(ALine)) and (ALine[i + 1] = '=') then
        begin
          Inc(i, 2);
          Continue;
        end;
        // Looking for `=`: skip the trailing `=` of any two-char operator
        // that ends in it: `:=` assignment, `<=` less-or-equal, `>=`
        // greater-or-equal. Without this, the const-equals alignment pass
        // mistakes the second char of `<=`/`>=` for a const-block `=` and
        // right-pads it -- producing `>          = N`, which dcc32
        // rejects. (Bug repro: BUG_LE_OPERATOR.md, 2026-05-14.)
        if (AAnchor = '=') and (i > 1) and ((ALine[i - 1] = ':') or (ALine[i - 1] = '<') or (ALine[i - 1] = '>')) then
        begin
          Inc(i);
          Continue;
        end;
        Exit(i);
      end; // if
      St.StepCode(ALine, i);
    end; // case
  end; // case
end; // function

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
    C: Char   ;
  begin
    L:= Length(AKeyword);
    if Length(T) < L then
      Exit(False);
    if not SameText(Copy(T, 1, L), AKeyword) then
      Exit(False);
    if Length(T) = L then
      Exit(True);
    C:= T[L + 1];
    Result:= not (((C >= 'a') and (C <= 'z')) or ((C >= 'A') and (C <= 'Z')) or ((C >= '0') and (C <= '9')) or (C = '_'));
  end;

begin
  T:= TrimLeft(ALine);
  if T = '' then
    Exit(True);
  if StartsKW('begin' ) then
    Exit(True);
  if StartsKW('end' ) then
    Exit(True);
  if StartsKW('type' ) then
    Exit(True);
  if StartsKW('var' ) then
    Exit(True);
  if StartsKW('const' ) then
    Exit(True);
  if StartsKW('procedure' ) then
    Exit(True);
  if StartsKW('function' ) then
    Exit(True);
  if StartsKW('constructor' ) then
    Exit(True);
  if StartsKW('destructor' ) then
    Exit(True);
  if StartsKW('interface' ) then
    Exit(True);
  if StartsKW('implementation') then
    Exit(True);
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
  Body   : string        ;
  i      : Integer       ;
  Lead   : string        ;
  LeadLen: Integer       ;
  Sb     : TStringBuilder;
  T      : TToken        ;
  Tokens : TTokenList    ;
begin
  LeadLen:= 0;
  while (LeadLen < Length(ALine)) and (ALine[LeadLen + 1] = ' ') do
    Inc(LeadLen);
  Lead:= Copy(ALine, 1, LeadLen);
  Body:= Copy(ALine, LeadLen + 1, MaxInt);
  if Body = '' then
    Exit(ALine);
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
  Body    : string        ;
  i       : Integer       ;
  Lead    : string        ;
  LeadLen : Integer       ;
  NextKind: TptTokenKind  ;
  n       : Integer       ;
  PrevKind: TptTokenKind  ;
  Sb      : TStringBuilder;
  T       : TToken        ;
  Tokens  : TTokenList    ;
begin
  LeadLen:= 0;
  while (LeadLen < Length(ALine)) and (ALine[LeadLen + 1] = ' ') do
    Inc(LeadLen);
  Lead:= Copy(ALine, 1, LeadLen);
  Body:= Copy(ALine, LeadLen + 1, MaxInt);
  if Body = '' then
    Exit(ALine);
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
        while (n < Tokens.Count) and (Tokens[n].Kind = ptSpace) do
          Inc(n);
        if n < Tokens.Count then
          NextKind:= Tokens[n].Kind;
        if (NextKind = ptPoint) or (NextKind = ptSemiColon) or (PrevKind = ptPoint) then
          Continue; // drop: tight before `.`/`;` and after `.`
        Sb.Append(T.Pre);
        if Length(T.Text) > 1 then
          Sb.Append(' ')
        else
          Sb.Append(T.Text);
        Continue;
      end; // if
      Sb.Append(T.Pre );
      Sb.Append(T.Text);
      PrevKind:= T.Kind;
    end; // for
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
  i    : Integer       ;
  Lines: TStringList   ;
  Out_ : TStringBuilder;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Out_.Append(CollapseInteriorSpacesInLine(Lines[i]));
        Out_.Append(CRLF);
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
    Dec(k     );
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
    if Ext > MaxExt then
      MaxExt:= Ext;
    if Gap < MinGap then
      MinGap:= Gap;
  end;
  if MinGap = MaxInt then
    MinGap:= 0;
  Result:= MaxExt + MinGap + 1;
end; // function

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
//
// True when a `names: body;` line is a CASE-statement arm (the body is a
// statement) rather than a genuine variable/field declaration (the body is
// a type). Lets SplitMultiVarDeclarations route the two: real declarations
// obey SplitMultiVarDecls, case arms obey BreakCaseLabels. The signals are
// conservative -- a numeric label, a `:=`/`(` in the body, or a leading
// statement keyword. (The rare `enumA, enumB: BareParamlessProc;` arm is not
// caught and still splits; harmless and uncommon.)
function CaseArmLikeBody(const ANames, AType: string): Boolean;
var
  FirstWord: string        ;
  T        : string        ;
  p        : Integer       ;
  k        : Integer       ;
  NameList : TArray<string>;
begin
  // A label that does not start like an identifier (e.g. a numeric literal
  // `0`/`1`) proves these are case labels, not variable names.
  NameList:= ANames.Split([',']);
  for k:= 0 to High(NameList) do
  begin
    T:= Trim(NameList[k]);
    if (T <> '') and CharInSet(T[1], ['0'..'9']) then
      Exit(True);
  end;
  // A `:=` (assignment) or `(` (call / parenthesised expr) in the body marks
  // it as a statement rather than a type.
  if Pos(':=', AType) > 0 then
    Exit(True);
  if Pos('(' , AType) > 0 then
    Exit(True);
  // Body opening with a statement keyword.
  FirstWord:= '';
  p        := 1;
  while (p <= Length(AType)) and CharInSet(AType[p], ['A'..'Z', 'a'..'z']) do
  begin
    FirstWord:= FirstWord + AType[p];
    Inc(p);
  end;
  FirstWord:= LowerCase(FirstWord);
  Result:= (FirstWord = 'begin') or (FirstWord = 'if') or (FirstWord = 'while') or (FirstWord = 'for') or (FirstWord = 'with') or (FirstWord = 'try') or
  (FirstWord = 'repeat') or (FirstWord = 'asm') or (FirstWord = 'raise') or (FirstWord = 'inherited') or (FirstWord = 'goto') or (FirstWord = 'exit') or
  (FirstWord = 'halt') or (FirstWord = 'break') or (FirstWord = 'continue');
end; // function

// True when TypePart is an ANONYMOUS structured type whose identity is fixed
// per declaration: array of T / array[..] of T / record .. end / set of T /
// file of T / packed .. / procedure / function (incl. ".. of object") / inline
// class or object type, or a typed pointer (^T). Splitting "A, B: <such type>"
// into one decl per name makes A and B DISTINCT, incompatible types (E2008), so
// the formatter must leave them combined. Every matched word is RESERVED, so a
// NAMED type can never equal one; a name that merely STARTS like a keyword
// (TArrayHelper / SetItem) keeps its whole first word and so does NOT match --
// those stay safe to split. ('class'/'object' combined decls do not actually
// compile, but are matched as the safe conservative choice.)
function TypePartIsAnonymousStructured(const ATypePart: string): Boolean;
var
  T: string ;
  W: string ;
  p: Integer;
begin
  T:= TrimLeft(ATypePart);
  if T = '' then
    Exit(False);
  // A typed pointer is anonymous (per-decl identity) just like the keyword
  // forms; key off the leading caret before the word scan.
  if T[1] = '^' then
    Exit(True);
  // First word = leading run of letters; compare WHOLE word (not a prefix) so
  // a named type like SetItem/TArrayHelper is not vetoed.
  W:= '';
  p:= 1;
  while (p <= Length(T)) and CharInSet(T[p], ['A'..'Z', 'a'..'z']) do
  begin
    W:= W + T[p];
    Inc(p);
  end;
  W:= LowerCase(W);
  Result:= (W = 'array') or (W = 'record') or (W = 'set') or (W = 'file') or (W = 'packed') or (W = 'object') or (W = 'class') or (W = 'procedure') or (W = 'function');
end; // function

function SplitMultiVarDeclarations(const S: string; ASplitDecls, ASplitCaseLabels: Boolean): string;
var
  Lines     : TStringList    ;
  Out_      : TStringBuilder ;
  i         : Integer        ;
  k         : Integer        ;
  Col       : Integer        ;
  Line      : string         ;
  Indent    : string         ;
  Body      : string         ;
  Names     : string         ;
  TypePart  : string         ;
  Tail      : string         ;
  ColonPos  : Integer        ;
  SemiPos   : Integer        ;
  FirstNonWs: Integer        ;
  C         : Char           ;
  St        : TLineScanState ;
  SkipLine  : Boolean        ;
  Done      : Boolean        ;
  NameTokens: TArray<string> ;
  HasComma  : Boolean        ;
  DoSplit   : Boolean        ;
  IdentChars: set of AnsiChar;
begin
  Lines:= TStringList.Create;
  IdentChars:= ['A'..'Z', 'a'..'z', '0'..'9', '_', '.'];
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Out_:= TStringBuilder.Create;
    try
      St.Reset;
      St.ClampDepth:= True;
      for i:= 0 to Lines.Count - 1 do
      begin
        Line:= Lines[i];

        // A line that STARTS inside a paren/bracket group or block comment
        // is never rewritten -- but it is still scanned below so the shared
        // tracker sees its brackets/comment closers and the NEXT line gets
        // the correct context.
        SkipLine:= (St.Depth > 0) or St.InBlockComment;

        // One scan does double duty: it advances the cross-line tracker AND
        // (for candidate lines) finds `:` / `;` at this line's top level (the
        // trailing-comment tail is taken from everything after the final `;`).
        ColonPos:= 0; SemiPos:= 0;
        St.BeginLine;
        Col := 1;
        Done:= False;
        while not Done do
        case St.SkipNonCode(Line, Col) of
          seEndOfLine  : Done:= True;
          seLineComment: Done:= True;
          seCode       :
          begin
            C:= Line[Col];
            if (St.Depth = 0) and (C = ':') and not ((Col < Length(Line)) and (Line[Col + 1] = '=')) then
            begin
              if ColonPos = 0 then
                ColonPos:= Col;
              Inc(Col);
            end
            else if (St.Depth = 0) and (C = ';') then
            begin
              SemiPos:= Col;
              Inc(Col);
            end
            else
              St.StepCode(Line, Col);
          end; // case
        end; // case

        if SkipLine then
        begin
          Out_.Append(Line);
          Out_.Append(CRLF);
          Continue;
        end;

        // At paren depth 0. Try to shape-match the line.
        FirstNonWs:= 1;
        while (FirstNonWs <= Length(Line)) and CharInSet(Line[FirstNonWs], [' ', #9]) do
          Inc(FirstNonWs);
        Indent:= Copy(Line, 1, FirstNonWs - 1);

        // Shape-match: indent + names + `:` + type + `;` + optional comment.
        // ColonPos > FirstNonWs AND SemiPos > ColonPos AND no trailing
        // garbage between `;` and `//` or EOL.
        if (ColonPos > FirstNonWs) and (SemiPos > ColonPos) then
        begin
          Names:= Trim(Copy(Line, FirstNonWs, ColonPos - FirstNonWs));
          TypePart:= Trim(Copy(Line, ColonPos + 1, SemiPos - ColonPos - 1));
          // The TAIL is everything after the FINAL top-level `;`: a trailing
          // `//`, `{...}` or `(*...*)` comment that must ride on the first
          // split line. (Capturing only `//` tails dropped a brace comment,
          // which tripped the content guard and silently declined the whole
          // file.) Anything here can only be comments/whitespace -- real code
          // after the `;` would have moved SemiPos or poisoned TypePart.
          Tail:= Trim(Copy(Line, SemiPos + 1, Length(Line) - SemiPos));

          // Reject if `Names` is not a clean identifier-comma list. Each
          // comma-separated NAME, trimmed, must be a single bare identifier.
          // The previous char-scan tolerated spaces ANYWHERE, so an inline
          // `var A, B: T;` STATEMENT (Names = 'var A, B') slipped through and
          // split with the `var`/`const` keyword dropped from every line but
          // the first -- producing uncompilable code. A real keyword prefix or
          // any embedded space now poisons the match, leaving such lines alone.
          HasComma:= Pos(',', Names) > 0;
          if HasComma then
          begin
            NameTokens:= Names.Split([',']);
            for k:= 0 to High(NameTokens) do
            begin
              Body:= Trim(NameTokens[k]);
              if Body = '' then begin HasComma:= False; Break; end;
              for Col:= 1 to Length(Body) do
                if not (AnsiChar(Body[Col]) in IdentChars) then
                begin HasComma:= False; Break; end;
              if not HasComma then
                Break;
            end;
          end; // if

          // Route the split: a case-arm body obeys BreakCaseLabels; a real
          // declaration obeys SplitMultiVarDecls. When the governing flag is
          // off the line falls through and is emitted unchanged.
          if CaseArmLikeBody(Names, TypePart) then
            DoSplit:= ASplitCaseLabels
          else
          begin
            DoSplit:= ASplitDecls;
            // A genuine type never carries a top-level `;`. If TypePart does,
            // the line packs a SECOND declaration ("A, B: T1; C: T2;") -- the
            // scan ran the type to the last `;`, so splitting would duplicate
            // the tail ("Q: T2" onto every line). Leave such lines alone.
            if Pos(';', TypePart) > 0 then
              DoSplit:= False;
            // An ANONYMOUS structured type (array/record/set/file/packed/class/
            // object/procedure/function/reference, or a typed pointer) has a
            // DISTINCT identity per declaration, so splitting "A, B: array of
            // Integer" makes two incompatible types and changes semantics
            // (E2008). Never split these; NAMED types (TFoo, Integer) still do.
            if TypePartIsAnonymousStructured(TypePart) then
              DoSplit:= False;
          end; // else
          // A block comment left OPEN at the end of the line continues on the
          // next line; it cannot be re-attached to a single split line, so
          // leave such lines alone.
          if St.InBlockComment then
            DoSplit:= False;
          if HasComma and (TypePart <> '') and DoSplit then
          begin
            NameTokens:= Names.Split([','], TStringSplitOptions.ExcludeEmpty);
            for k:= 0 to High(NameTokens) do
            begin
              if k = 0 then
              begin
                if Tail <> '' then
                  Out_.AppendLine(Indent + Trim(NameTokens[k]) + ': ' + TypePart + '; ' + Tail)
                else
                  Out_.AppendLine(Indent + Trim(NameTokens[k]) + ': ' + TypePart + ';');
              end
              else
                Out_.AppendLine(Indent + Trim(NameTokens[k]) + ': ' + TypePart + ';');
            end; // for
            Continue; // line replaced
          end; // if
        end; // if

        // No match (or rejected) -- emit line unchanged.
        Out_.Append(Line);
        Out_.Append(CRLF);
      end; // for
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // function

// v1.0.3: align the trailing `;` on consecutive declaration lines
// (lines that contain a top-level `:` and end with `;`). Runs AFTER
// Bracket depth at the START of each line, tracked ACROSS lines (string- and
// comment-aware). A line whose start-depth > 0 sits inside a multi-line `( )`
// or `[ ]` group -- an enum body, a multi-line array literal, or a split
// parameter list. Those lines must be excluded from the top-level declaration
// alignment passes; otherwise enum members and array internals get their
// `=` / `:` / `;` aligned as if they were real declarations (and the trailing
// `//` comments shift with them).
// (Implementation moved to YADF.LineScan.ComputeLineStartDepths -- the
// shared scanner; the doc comment above still describes the contract.)

// AlignByAnchor(':') so the colons are already in their final column;
// this pass just adds spaces before the `;` so the right edge lines up.
// Runs of fewer than 2 declaration lines are left untouched.
function AlignDeclarationSemicolons(const S: string; AMaxColumn: Integer): string;
var
  Lines   : TStringList    ;
  Out_    : TStringBuilder ;
  i       : Integer        ;
  j       : Integer        ;
  ColonAt : TArray<Integer>;
  SemiAt  : TArray<Integer>;
  Depths  : TArray<Integer>;
  RunStart: Integer        ;
  RunEnd  : Integer        ;
  Target  : Integer        ;
  k       : Integer        ;
  Pad     : Integer        ;
  Line    : string         ;

  function HasDeclShape(const ALine: string; out AColon, ASemi: Integer): Boolean;
  var
    p   : Integer       ;
    sCol: Integer       ;
    St  : TLineScanState;
    Done: Boolean       ;
  begin
    AColon:= 0; ASemi:= 0;
    St.Reset;
    Done:= False;
    p   := 1;
    while not Done do
    case St.SkipNonCode(ALine, p) of
      seEndOfLine, seLineComment: Done:= True;
      seCode                    :
      begin
        if (St.Depth = 0) and (ALine[p] = ':') and not ((p < Length(ALine)) and (ALine[p + 1] = '=')) then
        begin
          if AColon = 0 then
            AColon:= p;
          Inc(p);
        end
        else if (St.Depth = 0) and (ALine[p] = ';') then
        begin
          ASemi:= p;
          Inc(p);
        end
        else
          St.StepCode(ALine, p);
      end; // case
    end; // case
    // The line must have a top-level `:` and a `;` that lives AFTER
    // the colon (i.e., this really is a `name : type;` declaration).
    // We also require that nothing non-whitespace follows the `;`
    // except an optional line comment.
    Result:= (AColon > 0) and (ASemi > AColon);
    if Result then
    begin
      sCol:= ASemi + 1;
      while (sCol <= Length(ALine)) and CharInSet(ALine[sCol], [' ', #9]) do
        Inc(sCol);
      if sCol <= Length(ALine) then
      begin
        // Only line comments allowed after the `;`.
        if not ((sCol < Length(ALine)) and (ALine[sCol] = '/') and (ALine[sCol + 1] = '/')) then
          Result:= False;
      end;
    end; // if
  end; // function

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;

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
          Out_.Append(CRLF);
          Inc(i);
          Continue;
        end;
        RunStart:= i;
        RunEnd  := i;
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
            if SemiAt[k] > Target then
              Target:= SemiAt[k];
          if Target > AMaxColumn then Target:= 0; // skip if too wide
          if Target > 0 then
          begin
            for k:= RunStart to RunEnd do
            begin
              Line:= Lines[k];
              Pad:= Target - SemiAt[k];
              if Pad > 0 then
                Line:= Copy(Line, 1, SemiAt[k] - 1) + StringOfChar(' ', Pad) + Copy(Line, SemiAt[k], MaxInt);
              Out_.Append(Line);
              Out_.Append(CRLF);
            end;
          end // if
          else
            for k:= RunStart to RunEnd do
            begin
              Out_.Append(Lines[k]);
              Out_.Append(CRLF);
            end;
        end // if
        else
        begin
          Out_.Append(Lines[i]);
          Out_.Append(CRLF);
        end;
        i:= RunEnd + 1;
      end; // while
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // begin

function AlignByAnchor(const S, AAnchor: string; AMaxColumn: Integer): string;
var
  Anchors : TArray<Integer>;
  Depths  : TArray<Integer>;
  i       : Integer        ;
  j       : Integer        ;
  Line    : string         ;
  Lines   : TStringList    ;
  Out_    : TStringBuilder ;
  Pad     : Integer        ;
  RunCols : TArray<Integer>;
  RunLines: TArray<string> ;
  StartIdx: Integer        ;
  Target  : Integer        ;
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    SetLength(Anchors, Lines.Count);
    for i:= 0 to Lines.Count - 1 do
      Anchors[i]:= FindAnchorAtTopLevel(Lines[i], AAnchor);
    // Exclude lines inside a multi-line ()/[] group (enum bodies, array
    // literals, split parameter lists): they must not be aligned as if they
    // were top-level const/var/type declarations.
    Depths:= ComputeLineStartDepths(Lines);
    for i:= 0 to Lines.Count - 1 do
      if Depths[i] > 0 then
        Anchors[i]:= 0;
    Out_:= TStringBuilder.Create;
    try
      i:= 0;
      while i < Lines.Count do
      begin
        if (Anchors[i] = 0) or StartsBlockBoundary(Lines[i]) then
        begin
          Out_.Append(Lines[i]);
          Out_.Append(CRLF);
          Inc(i);
          Continue;
        end;
        StartIdx:= i;
        j:= i + 1;
        while (j < Lines.Count) and (Anchors[j] > 0) and not StartsBlockBoundary(Lines[j]) do
          Inc(j);
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
        end // if
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
            Out_.Append(CRLF);
          end; // for
        end // if
        else
          for i:= StartIdx to j - 1 do
          begin
            Out_.Append(Lines[i]);
            Out_.Append(CRLF);
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
    Cols     : TArray<Integer>     ;
    HasAssign: Boolean             ;
  end;

  // Builds the TLineShape for a single line by re-lexing it.
  // Identifiers, literals, whitespace, and comments are filtered out so
  // only the structural skeleton remains; that skeleton is what gets
  // compared between adjacent lines to decide whether they're alignment
  // peers.
function ComputeLineShape(const ALine: string): TLineShape;
var
  Cols : TList<Integer>     ;
  Lex  : TmwPasLex          ;
  Shape: TList<TptTokenKind>;
  Tok  : TptTokenKind       ;
begin
  Result.HasAssign:= False;
  SetLength(Result.Shape, 0);
  SetLength(Result.Cols , 0);
  Lex:= TmwPasLex.Create;
  Shape:= TList<TptTokenKind>.Create;
  Cols := TList<Integer     >.Create;
  try
    Lex.Origin:= ALine;
    while Lex.TokenID <> ptNull do
    begin
      Tok:= Lex.TokenID;
      if Tok = ptAssign then
        Result.HasAssign:= True;
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
  if Length(A) <> Length(B) then
    Exit(False);
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
  St: TLineScanState;
  i : Integer       ;
begin
  Result:= 0;
  St.Reset;
  i:= 1;
  while True do
  case St.SkipNonCode(ALine, i) of
    seEndOfLine  : Exit                 ;
    seLineComment: Exit(i)              ;
    seCode       : St.StepCode(ALine, i);
  end;
end; // function

function SmartAlignAssignments(const S: string; AMaxCol: Integer; AMatchShapes: Boolean; AMinAnchors, ACommentMaxShift: Integer): string;
var
  AnyOver  : Boolean                ;
  ColCols  : TArray<Integer>        ;
  ColLines : TArray<string>         ;
  i        : Integer                ;
  Info     : TArray<TLineShape>     ;
  InUses   : TArray<Boolean>        ;
  j        : Integer                ;
  k        : Integer                ;
  Lines    : TStringList            ;
  Out_     : TStringBuilder         ;
  Pad      : Integer                ;
  Target   : Integer                ;
  WorkCols : TArray<TArray<Integer>>;
  WorkLine : TArray<string>         ;
  L        : Integer                ; // hoisted from inline `for var L` (XE8/D10 compat)
  M        : Integer                ; // hoisted from inline `for var M`
  AllHaveCo: Boolean                ; // hoisted from inline vars in the comment-align block
  MaxCoCol : Integer                ;
  MaxShift : Integer                ;

  // A line whose structural skeleton starts with a block keyword (end,
  // begin, try, finally, ...) is NOT an alignment peer. ComputeLineShape
  // treats those keywords as anchors, so two `end;` lines at different
  // nesting depths would otherwise count as a matching shape and get their
  // keyword column aligned -- pulling the indented one into column 0.
  function StructuralLead(k: TptTokenKind): Boolean;
  begin
    Result:= k in [ptEnd, ptBegin, ptTry, ptFinally, ptExcept, ptElse, ptRepeat, ptUntil, ptCase, ptRecord, ptClass, ptObject, ptInterface, ptInitialization, ptFinalization,
      ptAsm];
  end;

  // Section keywords that can never occur inside a well-formed uses clause.
  // Used only as a bail-out, so an unterminated clause in malformed source
  // cannot switch alignment off for the whole rest of the file.
  function SectionLead(k: TptTokenKind): Boolean;
  begin
    Result:= k in [ptInterface, ptImplementation, ptInitialization, ptFinalization, ptType, ptVar, ptConst, ptBegin, ptEnd, ptProcedure, ptFunction, ptConstructor,
      ptDestructor];
  end;

  // A uses clause is ONE statement spread over many lines, and each qualified
  // unit name (System.Win.Registry) is ONE identifier -- the dots inside it are
  // not a column layout. ComputeLineShape hands every `.` to the aligner as an
  // anchor, so two comma-first entries sharing a [, . .] skeleton had their dots
  // padded into columns (`System.Win     .Registry`); the 1.0.13.1 self-format
  // pass wrote exactly that into YADF's own uses clauses. Flag every line from
  // the `uses` keyword through its terminating `;` so Eligible can refuse them.
  // Reading the flags off Info (not the raw text) makes this lexer-accurate: a
  // `uses` inside a comment or a string never reaches the shape at all.
  procedure MarkUsesLines;
  var
    n   : Integer;
    Open: Boolean;
    p   : Integer;
    Semi: Boolean;
  begin
    SetLength(InUses, Lines.Count);
    Open:= False;
    for n:= 0 to Lines.Count - 1 do
    begin
      if Length(Info[n].Shape) > 0 then
        if not Open then
          Open:= Info[n].Shape[0] = ptUses
        else if SectionLead(Info[n].Shape[0]) then
          Open:= False;
      InUses[n]:= Open;
      if Open then
      begin
        Semi:= False;
        for p:= 0 to High(Info[n].Shape) do if Info[n].Shape[p] = ptSemiColon then
        begin
          Semi:= True;
          Break;
        end;
        if Semi then
          Open:= False;
      end;
    end; // for
  end; // procedure

  function Eligible(AIdx: Integer): Boolean;
  var
    AInfo: TLineShape;
  begin
    // A uses clause never participates in column alignment (see MarkUsesLines).
    if InUses[AIdx] then
      Exit(False);
    AInfo:= Info[AIdx];
    Result:= AInfo.HasAssign or
    (AMatchShapes and (Length(AInfo.Shape) >= AMinAnchors) and (Length(AInfo.Shape) > 0) and (AInfo.Shape[0] <> ptColon) and not StructuralLead(AInfo.Shape[0]));
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    SetLength(Info, Lines.Count);
    for i:= 0 to Lines.Count - 1 do
      Info[i]:= ComputeLineShape(Lines[i]);
    MarkUsesLines;

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
        if not Eligible(i) then
        begin
          // A uses-clause line is alignment-INELIGIBLE but must still be
          // TIGHTENED. Eligible lines get TightenAnchorSpacingInLine inside the
          // run below; skipping the run entirely would leave padding that an
          // earlier YADF baked into the source (`System      .Generics`) to be
          // merely collapsed to one space by CollapseInteriorSpaces -- never
          // removed. Tighten here so a uses clause converges on tight dots.
          if InUses[i] then
            Out_.Append(TightenAnchorSpacingInLine(Lines[i]))
          else
            Out_.Append(Lines[i]);
          Out_.Append(CRLF);
          Inc(i);
          Continue;
        end;
        j:= i + 1;
        while (j < Lines.Count) and Eligible(j) and ShapesMatch(Info[i].Shape, Info[j].Shape) do
          Inc(j);
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
            if (k = High(Info[i].Shape)) and (Info[i].Shape[k] = ptSemiColon) then
              Continue;
            for L:= 0 to (j - i) - 1 do
            begin
              ColLines[L]:= WorkLine[L] ;
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
            for L:= 0 to (j - i) - 1 do
            begin
              Pad:= Target - WorkCols[L][k];
              if Pad > 0 then
                WorkLine[L]:= Copy(WorkLine[L], 1, WorkCols[L][k] - 1) + StringOfChar(' ', Pad) + Copy(WorkLine[L], WorkCols[L][k], MaxInt)
              else if Pad < 0 then
                WorkLine[L]:= Copy(WorkLine[L], 1, WorkCols[L][k] - 1 + Pad) + Copy(WorkLine[L], WorkCols[L][k], MaxInt);
              if Pad <> 0 then
                for M:= k to High(WorkCols[L]) do
                  WorkCols[L][M]:= WorkCols[L][M] + Pad;
            end;
          end; // for

          // Operator padding overflowed AMaxCol: drop it and fall
          // back to the raw lines. The run is still a shape-matched
          // peer group, so trailing-comment alignment below may yet
          // apply to the originals.
          if AnyOver then
            for k:= 0 to (j - i) - 1 do
              WorkLine[k]:= Lines[i + k];

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
            AllHaveCo:= True;
            MaxCoCol := 0;
            SetLength(ColCols, j - i);
            for k:= 0 to (j - i) - 1 do
            begin
              ColCols[k]:= TopLevelLineCommentCol(WorkLine[k]);
              if ColCols[k] = 0 then
              begin
                AllHaveCo:= False;
                Break;
              end;
              if ColCols[k] > MaxCoCol then
                MaxCoCol:= ColCols[k];
            end;
            if AllHaveCo then
            begin
              MaxShift:= 0;
              for k:= 0 to (j - i) - 1 do
                if MaxCoCol - ColCols[k] > MaxShift then
                  MaxShift:= MaxCoCol - ColCols[k];
              if (MaxShift > 0) and (MaxShift <= ACommentMaxShift) and (MaxCoCol <= AMaxCol) then
                for k:= 0 to (j - i) - 1 do
                begin
                  Pad:= MaxCoCol - ColCols[k];
                  if Pad > 0 then
                    WorkLine[k]:= Copy(WorkLine[k], 1, ColCols[k] - 1) + StringOfChar(' ', Pad) + Copy(WorkLine[k], ColCols[k], MaxInt);
                end;
            end; // if
          end; // if

          for k:= 0 to (j - i) - 1 do
          begin
            Out_.Append(WorkLine[k]);
            Out_.Append(CRLF);
          end;
          i:= j;
        end // if
        else
        begin
          Out_.Append(Lines[i]);
          Out_.Append(CRLF);
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
function ReflowLineBreaks(const S: string; AMaxLen: Integer; APackShortBodies: Boolean = False): string;

// True iff ALine starts with AWord, case-insensitively, with a
// non-identifier boundary after the word (so `class` matches but
// `classes` does not).
  function StartsWordCI(const ALine, AWord: string): Boolean;
  var
    Trimmed: string;
  begin
    Trimmed:= TrimLeft(ALine);
    if Length(Trimmed) < Length(AWord) then
      Exit(False);
    if not SameText(Copy(Trimmed, 1, Length(AWord)), AWord) then
      Exit(False);
    if Length(Trimmed) > Length(AWord) then
      Result:= not (((Trimmed[Length(AWord) + 1] >= 'a') and (Trimmed[Length(AWord) + 1] <= 'z')) or
        ((Trimmed[Length(AWord) + 1] >= 'A') and (Trimmed[Length(AWord) + 1] <= 'Z')) or ((Trimmed[Length(AWord) + 1] >= '0') and (Trimmed[Length(AWord) + 1] <= '9')) or
        (Trimmed[Length(AWord) + 1] = '_'))
    else
      Result:= True;
  end; // function

// True iff ALine ends with AWord, case-insensitively, with a
// non-identifier boundary before the word.
  function EndsWordCI(const ALine, AWord: string): Boolean;
  var
    Trimmed: string ;
    EndPos : Integer;
  begin
    Trimmed:= TrimRight(ALine);
    if Length(Trimmed) < Length(AWord) then
      Exit(False);
    EndPos:= Length(Trimmed) - Length(AWord) + 1;
    if not SameText(Copy(Trimmed, EndPos, Length(AWord)), AWord) then
      Exit(False);
    if EndPos > 1 then
      Result:= not (((Trimmed[EndPos - 1] >= 'a') and (Trimmed[EndPos - 1] <= 'z')) or ((Trimmed[EndPos - 1] >= 'A') and (Trimmed[EndPos - 1] <= 'Z')) or
        ((Trimmed[EndPos - 1] >= '0') and (Trimmed[EndPos - 1] <= '9')) or (Trimmed[EndPos - 1] = '_'))
    else
      Result:= True;
  end; // function

// True if ALine contains a `//` line comment at top level or leaves
// a `{...}` / `(*...*)` block open at end-of-line. Either case
// forbids merging the next line into this one -- a line comment
// would swallow it, and an open block makes "where does this end"
// ambiguous.
  function HasLineCommentOrOpenBlock(const ALine: string): Boolean;
  var
    St: TLineScanState;
    i : Integer       ;
  begin
    Result:= False;
    St.Reset;
    i:= 1;
    while True do
    case St.SkipNonCode(ALine, i) of
      seEndOfLine  : Exit(St.InBlockComment);
      seLineComment: Exit(True)             ;
      seCode       : St.StepCode(ALine, i)  ;
    end;
  end; // function

// Detects `... class(TFoo, IBar)` / `... interface(IBaz)` style
// lines -- where the parenthesised ancestor list is the actual end
// of the line. Used to block merging the next member declaration
// onto the class header line, which would look terrible.
  function EndsWithTypeAncestorList(const ALine: string): Boolean;
  var
    R    : string ;
    Head : string ;
    i    : Integer;
    Level: Integer;
  begin
    R:= TrimRight(ALine);
    if (R = '') or (R[Length(R)] <> ')') then
      Exit(False);
    Level:= 0;
    i:= Length(R);
    while i > 0 do
    begin
      if R[i] = ')' then
        Inc(Level)
      else if R[i] = '(' then
      begin
        Dec(Level);
        if Level = 0 then
          Break;
      end;
      Dec(i);
    end;
    if i <= 1 then
      Exit(False);
    Head:= TrimRight(Copy(R, 1, i - 1));
    Result:= EndsWordCI(Head, 'class') or EndsWordCI(Head, 'object') or EndsWordCI(Head, 'interface') or EndsWordCI(Head, 'dispinterface');
  end; // function

// True iff ALine starts with a control-statement keyword whose own body
// would dangle if it were pulled onto a preceding `then`/`do` header --
// pulling it up is the "half-merge" we never want. begin/asm count too:
// a begin block belongs on its own line under its `if`.
  function StartsControlHeader(const ALine: string): Boolean;
  begin
    Result:= StartsWordCI(ALine, 'if') or StartsWordCI(ALine, 'while') or StartsWordCI(ALine, 'for') or StartsWordCI(ALine, 'with') or
    StartsWordCI(ALine, 'case') or StartsWordCI(ALine, 'repeat') or StartsWordCI(ALine, 'try') or StartsWordCI(ALine, 'begin') or StartsWordCI(ALine, 'asm');
  end;

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
    if HasLineCommentOrOpenBlock(ALine) then
      Exit(True);
    if EndsWithTypeAncestorList (ALine) then
      Exit(True);
    R:= TrimRight(ALine);
    if R = '' then
      Exit(True);
    if R[Length(R)] = ';' then
      Exit(True);
    if R[Length(R)] = '.' then
      Exit(True);
    if R[Length(R)] = '}' then
      Exit(True);
    // A closed `(*...*)` tail comment ends the line exactly like a `}` tail
    // does (the `*)` pair cannot occur in code outside a comment). Without
    // this, `C, D: Integer; (* note *)` merged with the following line.
    if (Length(R) >= 2) and (R[Length(R) - 1] = '*') and (R[Length(R)] = ')') then
      Exit(True);
    // A line ending in `:` is a case-arm (or goto) label. Keep its body on the
    // next line unless body-packing is on -- then a short arm collapses onto
    // the label. (`:=` ends in `=`, so it is not caught here.)
    if (R[Length(R)] = ':') and not APackShortBodies then
      Exit(True);
    // A line ending in an unclosed `(` / `[` is the opener of a multi-line
    // group that the structural emitter chose NOT to inline (it overflows or
    // contains a line comment -- e.g. an enum/array body). Pulling the first
    // member up onto the opener re-creates the half-merged enum bug, so keep
    // the break.
    if (R[Length(R)] = '(') or (R[Length(R)] = '[') then
      Exit(True);
    if EndsWordCI(R, 'begin' ) then
      Exit(True);
    if EndsWordCI(R, 'end' ) then
      Exit(True);
    if EndsWordCI(R, 'asm' ) then
      Exit(True);
    if EndsWordCI(R, 'try' ) then
      Exit(True);
    if EndsWordCI(R, 'finally' ) then
      Exit(True);
    if EndsWordCI(R, 'except' ) then
      Exit(True);
    if EndsWordCI(R, 'repeat' ) then
      Exit(True);
    if EndsWordCI(R, 'of' ) then
      Exit(True);
    if EndsWordCI(R, 'class' ) then
      Exit(True);
    if EndsWordCI(R, 'object' ) then
      Exit(True);
    if EndsWordCI(R, 'record' ) then
      Exit(True);
    if EndsWordCI(R, 'interface' ) then
      Exit(True);
    if EndsWordCI(R, 'dispinterface' ) then
      Exit(True);
    if EndsWordCI(R, 'implementation') then
      Exit(True);
    if EndsWordCI(R, 'initialization') then
      Exit(True);
    if EndsWordCI(R, 'finalization' ) then
      Exit(True);
    if EndsWordCI(R, 'private' ) then
      Exit(True);
    if EndsWordCI(R, 'public' ) then
      Exit(True);
    if EndsWordCI(R, 'protected' ) then
      Exit(True);
    if EndsWordCI(R, 'published' ) then
      Exit(True);
    // A `then`/`do` header keeps its body on the next line unless body-packing
    // is enabled. Even when it is, a nested control header (if/case/begin/...)
    // is never pulled up -- that produces the half-merged `for..do if..then`
    // shape. Only a short, simple body merges.
    if EndsWordCI(R, 'then') or EndsWordCI(R, 'do') then
    begin
      if not APackShortBodies then
        Exit(True);
      if StartsControlHeader(TrimLeft(ANext)) then
        Exit(True);
    end;
    if EndsWordCI(R, 'else') then
    begin
      // `else if ...` always chains onto one line. Otherwise the else body
      // stays on its own line, unless body-packing is on and the body is a
      // short simple statement (a control header is never pulled up).
      if not StartsWordCI(TrimLeft(ANext), 'if') then
      begin
        if not APackShortBodies then
          Exit(True);
        if StartsControlHeader(TrimLeft(ANext)) then
          Exit(True);
      end;
    end;
    if EndsWordCI(R, 'uses' ) then
      Exit(True);
    if EndsWordCI(R, 'contains') then
      Exit(True);
    if EndsWordCI(R, 'requires') then
      Exit(True);
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
    if T = '' then
      Exit(True);
    if T.StartsWith('//') then
      Exit(True);
    if T.StartsWith('{$') then
      Exit(True);
    if StartsWordCI(T, 'begin' ) then
      Exit(True);
    if StartsWordCI(T, 'end' ) then
      Exit(True);
    if StartsWordCI(T, 'else' ) then
      Exit(True);
    if StartsWordCI(T, 'until' ) then
      Exit(True);
    if StartsWordCI(T, 'finally' ) then
      Exit(True);
    if StartsWordCI(T, 'except' ) then
      Exit(True);
    if StartsWordCI(T, 'interface' ) then
      Exit(True);
    if StartsWordCI(T, 'implementation') then
      Exit(True);
    if StartsWordCI(T, 'initialization') then
      Exit(True);
    if StartsWordCI(T, 'finalization' ) then
      Exit(True);
    if StartsWordCI(T, 'type' ) then
      Exit(True);
    if StartsWordCI(T, 'var' ) then
      Exit(True);
    if StartsWordCI(T, 'const' ) then
      Exit(True);
    if StartsWordCI(T, 'procedure' ) then
      Exit(True);
    if StartsWordCI(T, 'function' ) then
      Exit(True);
    if StartsWordCI(T, 'constructor' ) then
      Exit(True);
    if StartsWordCI(T, 'destructor' ) then
      Exit(True);
    if StartsWordCI(T, 'private' ) then
      Exit(True);
    if StartsWordCI(T, 'public' ) then
      Exit(True);
    if StartsWordCI(T, 'protected' ) then
      Exit(True);
    if StartsWordCI(T, 'published' ) then
      Exit(True);
    if StartsWordCI(T, 'uses' ) then
      Exit(True);
    if T.StartsWith(',') then
      Exit(True);
    if T.StartsWith(';') then
      Exit(True);
    Result:= False;
  end; // function

// Returns a Boolean[Lines.Count] where Locked[i] = True iff line i
// is "inside" a block comment that was already open at the start of
// that line, OR opens a new block comment that stays open at end of
// line. Locked lines never participate in merge decisions, so block
// comment interiors pass through verbatim.
// (Body moved to YADF.LineScan.ComputeBlockCommentLock -- the shared
// scanner. The contract is unchanged; see the doc comment above.)

var
  CommentLocked: TArray<Boolean>;
  Cur          : string         ;
  i            : Integer        ;
  Joined       : string         ;
  k            : Integer        ;
  Leading      : string         ;
  Lines        : TStringList    ;
  NextLn       : string         ;
  Out_         : TStringBuilder ;
  CurR         : string         ; // hoisted from inline vars in the merge loop (XE8/D10)
  NextT        : string         ;
  Sep          : string         ;
  InUses       : Boolean        ; // inside a uses/contains/requires clause (pre-formatted)
begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Out_:= TStringBuilder.Create;
    try
      CommentLocked:= ComputeBlockCommentLock(Lines);
      i     := 0;
      InUses:= False;
      while i < Lines.Count do
      begin
        Cur:= Lines[i];
        // A uses/contains/requires clause is already laid out by RenderUsesGroup
        // (comma-first OR comma-last); its lines must never be reflowed back
        // together. Comma-first continuation lines start with `,` (caught by
        // NextBlocksMerge); comma-last lines END with `,`, which nothing else
        // guards -- so hold a clause flag from the keyword line to the closing `;`.
        if StartsWordCI(TrimLeft(Cur), 'uses') or StartsWordCI(TrimLeft(Cur), 'contains') or StartsWordCI(TrimLeft(Cur), 'requires') then
          InUses:= True;
        while i + 1 < Lines.Count do
        begin
          if InUses then
            Break;
          NextLn:= Lines[i + 1];
          if Trim(NextLn) = '' then
            Break;
          if CommentLocked[i] or CommentLocked[i + 1] then
            Break;
          if CurBlocksMerge(Cur, NextLn) then
            Break;
          if NextBlocksMerge(NextLn) then
            Break;
          k      := 1;
          Leading:= '';
          while (k <= Length(Cur)) and ((Cur[k] = ' ') or (Cur[k] = #9)) do
          begin
            Leading:= Leading + Cur[k];
            Inc(k);
          end;
          CurR := TrimRight(Cur   );
          NextT:= Trim     (NextLn);
          Sep:= ' ';
          if (CurR <> '') and CharInSet(CurR[Length(CurR)], ['(', '[']) then
            Sep:= '';
          if (NextT <> '') and CharInSet(NextT[1], [')', ']', ',', ';', '.']) then
            Sep:= '';
          Joined:= CurR + Sep + NextT;
          if Length(Joined) > AMaxLen then
            Break;
          Cur:= Joined;
          Inc(i);
        end; // while
        if InUses and TrimRight(Cur).EndsWith(';') then
          InUses:= False;
        Out_.Append(Cur );
        Out_.Append(CRLF);
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

// Collapses a short control-statement begin..end block onto one line when it
// fits. Targets the common idiom -- an if/for/while/with/else header whose body
// is a begin..end of nothing but simple `;`-terminated statements:
//   if X then              ->  if X then begin A := 1; B := 2; end;
//   begin
//     A := 1;
//     B := 2;
//   end;
// Conservative and string-safe by design:
//   * fires ONLY when the line before `begin` is a control header ending in
//     then/do/else (a routine body -- `procedure Foo;` / `begin..end;` -- is
//     deliberately left alone),
//   * every body line must be a single complete `;`-terminated statement with
//     no comment characters and not inside a block comment; anything else
//     (a multi-line statement, a nested expanded block, a comment) bails the
//     whole collapse,
//   * the matching `end` is the first `end`-word line (body lines never start
//     with the `end` word),
//   * the resulting one-liner must fit AMaxLen,
//   * interior runs of spaces (column-alignment padding) are squeezed to one,
//     string-aware (doubled-quote escapes handled), so literals are untouched.
// Runs as the FINAL pass so it never feeds joined lines back through the column
// passes, and preserves the header's already-correct indent. Idempotent: a
// collapsed line presents no bare `begin` line to re-match.
/// <summary>Forces the body of a single-line control statement onto its own
/// indented line: for/while/with `... do Stmt;` (BreakLoopBody / BreakWithBody)
/// and if `... then A else B;` (BreakIfBody, added later). Structural mirror of
/// CollapseShortBlocks. Content-neutral (inserts only CRLF + whitespace);
/// ReindentByDepth (called by the pipeline right after) fixes the body depth.
/// A begin block, a body starting with a nested control header, or a line with a
/// top-level line comment / open block comment is left unchanged. Idempotent.</summary>
function BreakControlBodies(const S: string; const AOpts: TYadfOptions): string;
var
  Lines : TStringList    ;
  Lock  : TArray<Boolean>;
  Out_  : TStringBuilder ;
  i     : Integer        ;
  Cur   : string         ;
  T     : string         ;
  Indent: string         ;
  W     : TArray<string> ;
  BefP  : TArray<Integer>;
  AftP  : TArray<Integer>;
  Disq  : Boolean        ;
  M     : Integer        ;
  DoIx  : Integer        ;
  Header: string         ;
  Body  : string         ;
  Segs  : TStringList    ;
  isElse: Boolean        ;
  Cursor: Integer        ;
  k     : Integer        ;
  Ok    : Boolean        ;
  s2    : Integer        ;

  function StartsWordCI(const L, Wd: string): Boolean;
  var
    Tr: string;
  begin
    Tr:= TrimLeft(L);
    if Length(Tr) < Length(Wd) then
      Exit(False);
    if not SameText(Copy(Tr, 1, Length(Wd)), Wd) then
      Exit(False);
    if Length(Tr) > Length(Wd) then
      Result:= not CharInSet(Tr[Length(Wd) + 1], ['a'..'z', 'A'..'Z', '0'..'9', '_'])
    else
      Result:= True;
  end;

  function IsSimpleBody(const B: string): Boolean;
  var
    Tb: string;
  begin
    Tb:= TrimLeft(B);
    if Tb = '' then
      Exit(False);
    if StartsWordCI(Tb, 'begin' ) or StartsWordCI(Tb, 'asm' ) then
      Exit(False);
    if StartsWordCI(Tb, 'if' ) or StartsWordCI(Tb, 'while' ) or StartsWordCI(Tb, 'for' ) or StartsWordCI(Tb, 'with' ) or StartsWordCI(Tb, 'case' ) or StartsWordCI(Tb, 'repeat') or
    StartsWordCI(Tb, 'try' ) then Exit(False);
    Result:= True;
  end;

  procedure ScanTop(const L: string; out AW: TArray<string>; out ABef, AAft: TArray<Integer>; out ADisq: Boolean);
  var
    p    : Integer;
    n    : Integer;
    ws   : Integer;
    Depth: Integer;
    inStr: Boolean;
    inBlk: Boolean;
    inPar: Boolean;
    wrd  : string ;
    cnt  : Integer;

    function IsIdent(ch: Char): Boolean;
    begin
      Result:= CharInSet(ch, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
    end;

    procedure AddHit(const AWord: string; ABp, AAp: Integer);
    begin
      if cnt = Length(AW) then
      begin
        SetLength(AW  , cnt * 2 + 4);
        SetLength(ABef, cnt * 2 + 4);
        SetLength(AAft, cnt * 2 + 4);
      end;
      AW[cnt]:= AWord; ABef[cnt]:= ABp; AAft[cnt]:= AAp; Inc(cnt);
    end;

  begin
    ADisq:= False;
    cnt  := 0;
    SetLength(AW, 0); SetLength(ABef, 0); SetLength(AAft, 0);
    n:= Length(L);
    p:= 1; Depth:= 0; inStr:= False; inBlk:= False; inPar:= False;
    while p <= n do
    begin
      if inStr then
      begin
        if L[p] = '''' then
          if (p < n) and (L[p + 1] = '''') then
            Inc(p)
          else
            inStr:= False;
        Inc(p); Continue;
      end;
      if inBlk then
      begin
        if L[p] = '}' then
          inBlk:= False;
        Inc(p); Continue;
      end;
      if inPar then
      begin
        if (L[p] = '*') and (p < n) and (L[p + 1] = ')') then begin inPar:= False; Inc(p); end;
        Inc(p); Continue;
      end;
      if L[p] = '''' then begin inStr:= True; Inc(p); Continue; end;
      if L[p] = '{'  then begin inBlk:= True; Inc(p); Continue; end;
      if (L[p] = '(') and (p < n) and (L[p + 1] = '*') then begin inPar:= True; Inc(p, 2); Continue; end;
      if (L[p] = '/') and (p < n) and (L[p + 1] = '/') then begin ADisq:= True; Exit; end;
      if (L[p] = '(') or (L[p] = '[') then begin Inc(Depth); Inc(p); Continue; end;
      if (L[p] = ')') or (L[p] = ']') then begin if Depth > 0 then Dec(Depth); Inc(p); Continue; end;
      if IsIdent(L[p]) and ((p = 1) or not IsIdent(L[p - 1])) then
      begin
        ws := p;
        wrd:= '';
        while (p <= n) and IsIdent(L[p]) do begin wrd:= wrd + L[p]; Inc(p); end;
        if (Depth = 0) and (SameText(wrd, 'do') or SameText(wrd, 'then') or SameText(wrd, 'else')) then
          AddHit(LowerCase(wrd), ws, p);
        Continue;
      end;
      Inc(p);
    end; // while
    if inBlk or inPar then
      ADisq:= True;
    SetLength(AW, cnt); SetLength(ABef, cnt); SetLength(AAft, cnt);
  end; // begin

  procedure OutLine(const L: string);
  begin
    Out_.Append(L); Out_.Append(CRLF);
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Lock:= ComputeBlockCommentLock(Lines);
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Cur:= Lines[i];
        T:= TrimLeft(Cur);
        Indent:= Copy(Cur, 1, Length(Cur) - Length(T));
        // Loops / with: split after the first top-level `do`.
        if (not Lock[i]) and ( ((StartsWordCI(T, 'for') or StartsWordCI(T, 'while')) and AOpts.BreakLoopBody) or (StartsWordCI(T, 'with') and AOpts.BreakWithBody) ) then
        begin
          ScanTop(Cur, W, BefP, AftP, Disq);
          if not Disq then
          begin
            DoIx:= -1;
            for M:= 0 to High(W) do if W[M] = 'do' then begin DoIx:= M; Break; end;
            if DoIx >= 0 then
            begin
              Header:= TrimRight(Copy(Cur, 1, AftP[DoIx] - 1));
              Body:= Trim(Copy(Cur, AftP[DoIx], Length(Cur)));
              if IsSimpleBody(Body) then
              begin
                OutLine(Header);
                OutLine(Indent + Body);
                Continue;
              end;
            end;
          end; // if
        end; // if
        // if / else: split after `then`, before/after each top-level `else`;
        // "else if ... then" stays glued as one header line.
        isElse:= StartsWordCI(T, 'else');
        if (not Lock[i]) and AOpts.BreakIfBody and (StartsWordCI(T, 'if') or isElse) then
        begin
          ScanTop(Cur, W, BefP, AftP, Disq);
          if not Disq then
          begin
            Segs:= TStringList.Create;
            try
              Segs.LineBreak:= CRLF;
              Ok    := True;
              k     := 0; // set on every Ok:=True path below; init silences W1036 + defends the else
              Cursor:= 0;
              // Establish the first header segment + cursor.
              if not isElse then
              begin
                if (Length(W) = 0) or (W[0] <> 'then') then
                  Ok:= False
                else
                begin
                  Segs.Add(Trim(Copy(Cur, 1, AftP[0] - 1))); // "if COND then"
                  Cursor:= AftP[0];
                  k:= 1;
                end;
              end
              else if (Length(W) >= 2) and (W[0] = 'else') and (W[1] = 'then') then
              begin
                Segs.Add(Trim(Copy(Cur, 1, AftP[1] - 1))); // "else if COND then"
                Cursor:= AftP[1];
                k:= 2;
              end
              else if (Length(W) >= 1) and (W[0] = 'else') then
              begin
                Segs.Add(Copy(Cur, BefP[0], AftP[0] - BefP[0])); // preserve source `else` casing
                Cursor:= AftP[0];
                k:= 1;
              end
              else
                Ok:= False;
              // Walk the remaining else hits.
              while Ok and (k <= High(W)) do
              begin
                if W[k] <> 'else' then begin Ok:= False; Break; end; // stray then = nested if body
                Body:= Trim(Copy(Cur, Cursor, BefP[k] - Cursor));
                if not IsSimpleBody(Body) then begin Ok:= False; Break; end;
                Segs.Add(Body);
                if (k + 1 <= High(W)) and (W[k + 1] = 'then') then
                begin
                  Segs.Add(Trim(Copy(Cur, BefP[k], AftP[k + 1] - BefP[k]))); // "else if COND then"
                  Cursor:= AftP[k + 1];
                  k:= k + 2;
                end
                else
                begin
                  Segs.Add(Copy(Cur, BefP[k], AftP[k] - BefP[k])); // preserve source `else` casing
                  Cursor:= AftP[k];
                  k:= k + 1;
                end;
              end; // while
              if Ok then
              begin
                Body:= Trim(Copy(Cur, Cursor, Length(Cur))); // trailing body
                if IsSimpleBody(Body) then
                  Segs.Add(Body)
                else
                  Ok:= False;
              end;
              if Ok and (Segs.Count >= 2) then
              begin
                for s2:= 0 to Segs.Count - 1 do
                  OutLine(Indent + Segs[s2]);
                Continue; // line handled; skip fallthrough
              end;
            finally
              Segs.Free;
            end; // try
          end; // if
        end; // if
        OutLine(Cur);
      end; // for
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // function

/// <summary>Collapses a routine header the source split across lines back onto
/// one physical line: function/procedure/constructor/destructor/operator
/// declarations (interface forward decls AND implementation headers, nested
/// routines) and procedure-type / anonymous-method headers (inline
/// `procedure(`/`function(`). Detection keys off PAREN DEPTH -- a split header
/// always breaks inside an unclosed '(' -- gated on a leading routine keyword
/// or an inline procedure/function keyword so multi-line CALLS are left alone.
/// Accumulation stops at (and includes) the line that returns paren depth to 0;
/// it never crosses a depth-0 line break, and it aborts (emitting the span
/// unchanged) if a true block/section keyword (`begin`, `asm`, `type`,
/// `label`, `case`, `while`, `for`, `if`, `repeat`, `with`, `try`) starts a
/// continuation line while a paren is still open -- the signature of an
/// anonymous method's own body passed as a call argument. Ordinary parameter
/// modifiers (`const`, `var`) are deliberately NOT in that set -- they
/// routinely start a continuation line of a real parameter list and are
/// joined like any other token; only a genuine block/section opener aborts
/// the join. It bails the same way -- leaving the header split, unjoined --
/// if a `//` line comment is reached while a paren is still open (start line
/// or any continuation line): joining
/// would fold the remaining header tokens into that comment and delete them
/// from the emitted text. Content-neutral (tokens copied verbatim, only
/// whitespace/line breaks change) so Guard-safe and casing-preserving. If the
/// joined line exceeds AOpts.MaxLen, the nested WrapHeaderLine greedy-breaks
/// it AFTER the rightmost top-level ';'/',' that still fits the budget,
/// continuing at (leading indent + AOpts.Indent); its scan also stops at a
/// `//` comment, so a trailing note on the header's last line is never split.
/// Idempotent (including the wrap: a re-joined, re-scanned wrapped header
/// re-wraps to the same shape). Always-on standard behavior; runs regardless
/// of ReflowLines.</summary>
function JoinRoutineHeaders(const S: string; const AOpts: TYadfOptions): string;
var
  Lines  : TStringList   ;
  Out_   : TStringBuilder;
  St     : TLineScanState;
  i      : Integer       ;
  j      : Integer       ;
  Joined : string        ;
  Aborted: Boolean       ;
  CmtOpen: Boolean       ;
  CmtBail: Boolean       ;

  // True iff X begins with the whole word Wd (case-insensitive, ident boundary after).
  function LeadWord(const X, Wd: string): Boolean;
  begin
    Result:= (Length(X) >= Length(Wd)) and SameText(Copy(X, 1, Length(Wd)), Wd) and
    ((Length(X) = Length(Wd)) or not CharInSet(X[Length(Wd) + 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']));
  end;

// True iff position p in L starts the whole word Kw (ident boundary before AND
// after) and the next non-space char after the word is '(' -- an inline routine
// header keyword like `procedure(` / `function(`.
  function KwParenAt(const L, Kw: string; p: Integer): Boolean;
  var
    q: Integer;
  begin
    Result:= False;
    if not SameText(Copy(L, p, Length(Kw)), Kw) then
      Exit;
    if (p > 1) and CharInSet(L[p - 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
      Exit;
    q:= p + Length(Kw);
    if (q <= Length(L)) and CharInSet(L[q], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
      Exit;
    while (q <= Length(L)) and (L[q] = ' ') do
      Inc(q);
    Result:= (q <= Length(L)) and (L[q] = '(');
  end;

// True iff L, at top level (outside strings/comments), is the first line of a
// joinable header: a leading routine keyword, or an inline procedure(/function(.
  function IsHeaderStart(const L: string): Boolean;
  var
    Tr   : string ;
    p    : Integer;
    n    : Integer;
    inStr: Boolean;
    inBlk: Boolean;
    inPar: Boolean;
  begin
    Tr:= TrimLeft(L);
    if LeadWord(Tr, 'class') then
      Tr:= TrimLeft(Copy(Tr, 6, MaxInt));
    if LeadWord(Tr, 'generic') then
      Tr:= TrimLeft(Copy(Tr, 8, MaxInt));
    if LeadWord(Tr, 'function') or LeadWord(Tr, 'procedure') or LeadWord(Tr, 'constructor') or LeadWord(Tr, 'destructor') or LeadWord(Tr, 'operator') then
      Exit(True);
    // Case B: inline `procedure(` / `function(` scanned at top level.
    n:= Length(L); p:= 1; inStr:= False; inBlk:= False; inPar:= False;
    while p <= n do
    begin
      if inStr then begin if L[p] = '''' then begin if (p < n) and (L[p + 1] = '''') then Inc(p) else inStr:= False; end; Inc(p); Continue; end;
      if inBlk then begin if L[p] = '}' then inBlk:= False; Inc(p); Continue; end;
      if inPar then begin if (L[p] = '*') and (p < n) and (L[p + 1] = ')') then begin inPar:= False; Inc(p); end; Inc(p); Continue; end;
      if L[p] = '''' then begin inStr:= True; Inc(p); Continue; end;
      if L[p] = '{'  then begin inBlk:= True; Inc(p); Continue; end;
      if (L[p] = '(') and (p < n) and (L[p + 1] = '*') then begin inPar:= True; Inc(p, 2); Continue; end;
      if (L[p] = '/') and (p < n) and (L[p + 1] = '/') then
        Break;
      if KwParenAt(L, 'procedure', p) or KwParenAt(L, 'function', p) then
        Exit(True);
      Inc   (p   );
    end; // while
    Result:= False;
  end; // function

// Advance the shared cross-line scanner St across one physical line L.
// ACmtWhileOpen reports whether L's `//` comment (if any) was reached while
// a paren was still open (St.Depth > 0) -- the tell-tale that joining would
// fold the following lines into that comment and silently delete them.
  procedure ScanLine(const L: string; out ACmtWhileOpen: Boolean);
  var
    Col : Integer;
    Done: Boolean;
  begin
    ACmtWhileOpen:= False;
    St.BeginLine;
    Col:= 1; Done:= False;
    while not Done do
    case St.SkipNonCode(L, Col) of
      seEndOfLine  : Done:= True                                                      ;
      seLineComment: begin if St.Depth > 0 then ACmtWhileOpen:= True; Done:= True; end;
      seCode       : St.StepCode(L, Col)                                              ;
    end;
  end; // procedure

// Greedy break of an over-long joined header AFTER top-level ';' / ',' :
// pick the rightmost separator whose position <= MaxLen, emit head incl. the
// separator, continue the tail at (leading indent + AOpts.Indent). If no
// separator fits, leave the line long (better than an invalid mid-token break).
  function WrapHeaderLine(const ALine: string): string;
  var
    Indent   : string        ;
    NewIndent: string        ;
    Cur      : string        ;
    W        : TLineScanState;
    Col      : Integer       ;
    Best     : Integer       ;
    Done     : Boolean       ;
    OutB     : TStringBuilder;
  begin
    if Length(ALine) <= AOpts.MaxLen then
      Exit(ALine);
    Col:= 1;
    while (Col <= Length(ALine)) and CharInSet(ALine[Col], [' ', #9]) do
      Inc(Col);
    Indent:= Copy(ALine, 1, Col - 1);
    NewIndent:= Indent + StringOfChar(' ', AOpts.Indent);
    OutB:= TStringBuilder.Create;
    try
      Cur:= ALine;
      while Length(Cur) > AOpts.MaxLen do
      begin
        // Find the rightmost top-level ';' or ',' at position <= MaxLen.
        // "Top-level" here means Depth <= 1, NOT Depth = 0: a routine header
        // has exactly one enclosing '(' around its whole parameter list, so
        // every parameter-separating ';'/',' sits at Depth 1 (Depth 0 is only
        // reached again after the closing ')', e.g. between trailing
        // directives like `; overload; deprecated;`). Depth 1 is the correct
        // baseline for "not nested inside a parameter's own type/default" --
        // Depth >= 2 (an array/generic bracket or a nested paren within one
        // parameter) is deliberately excluded so a break never lands inside
        // those.
        Best:= 0;
        W.Reset; W.ClampDepth:= True; W.BeginLine;
        Col:= 1; Done:= False;
        while not Done do
        case W.SkipNonCode(Cur, Col) of
          seEndOfLine, seLineComment: Done:= True;
          seCode                    :
          begin
            if (W.Depth <= 1) and CharInSet(Cur[Col], [';', ',']) then
            begin
              if Col <= AOpts.MaxLen then Best:= Col // break AFTER this sep
              else Done:= True; // past budget: stop scanning
            end;
            if not Done then
              W.StepCode(Cur, Col);
          end;
        end; // case
        // Don't break at the very last char (nothing to move down) or before indent.
        if (Best <= Length(Indent)) or (Best >= Length(TrimRight(Cur))) then
          Break;
        OutB.Append(TrimRight(Copy(Cur, 1, Best)));
        OutB.Append(CRLF);
        Cur:= NewIndent + TrimLeft(Copy(Cur, Best + 1, MaxInt));
      end; // while
      OutB.Append(Cur);
      Result:= OutB.ToString;
    finally
      OutB.Free;
    end; // try
  end; // function

// True iff the trimmed line begins a block/statement keyword that can never
// appear inside a routine-header parameter list -- the tell-tale that an open
// paren belongs to a call wrapping an anonymous method, not to a header.
// Deliberately EXCLUDES const/var: those are ordinary parameter modifiers
// (e.g. `const D: TSomeType`) that routinely start a continuation line of a
// real header, so including them here used to bail real headers that never
// joined at all. begin/asm alone are sufficient to catch an anonymous
// method's own body -- every routine body reaches one of them eventually.
  function StartsBlockKeyword(const L: string): Boolean;
  var
    Tr: string;
  begin
    Tr:= TrimLeft(L);
    Result:= LeadWord(Tr, 'begin') or LeadWord(Tr, 'asm') or LeadWord(Tr, 'type') or LeadWord(Tr, 'label') or LeadWord(Tr, 'case') or LeadWord(Tr, 'while') or
    LeadWord(Tr, 'for') or LeadWord(Tr, 'if') or LeadWord(Tr, 'repeat') or LeadWord(Tr, 'with') or LeadWord(Tr, 'try');
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Out_:= TStringBuilder.Create;
    try
      St.Reset;
      St.ClampDepth:= True;
      i:= 0;
      while i < Lines.Count do
      begin
        // A joinable header starts only at top level (not mid-paren / mid-comment).
        if (St.Depth = 0) and (not St.InBlockComment) and IsHeaderStart(Lines[i]) then
        begin
          ScanLine(Lines[i], CmtOpen);
          if St.Depth = 0 then
          begin
            // Header already complete on this single physical line -- emit as-is.
            Out_.Append(Lines[i]); Out_.Append(CRLF);
            Inc(i); Continue;
          end;
          if CmtOpen then
          begin
            // The header's own start line ends in a `//` comment while a
            // paren is still open -- joining would fold every following line
            // into that comment (silently deleting the rest of the header).
            // Leave it split: emit the start line verbatim; the continuation
            // lines then flow through below as ordinary top-level lines.
            Out_.Append(Lines[i]); Out_.Append(CRLF);
            Inc(i); Continue;
          end;
          // Multi-line header: accumulate until a line returns depth to 0.
          Joined:= TrimRight(Lines[i]);
          Aborted:= False;
          CmtBail:= False;
          j:= i + 1;
          while j < Lines.Count do
          begin
            if StartsBlockKeyword(Lines[j]) then begin Aborted:= True; Break; end;
            ScanLine(Lines[j], CmtOpen);
            if CmtOpen then begin CmtBail:= True; Break; end;
            if Trim(Lines[j]) <> '' then
              Joined:= Joined + ' ' + Trim(Lines[j]);
            if St.Depth = 0 then Break; // closing line reached (inclusive)
            Inc(j);
          end;
          if CmtBail then
          begin
            // Bail (comment variant): unlike the block-keyword bail below --
            // which Breaks BEFORE its ScanLine call, leaving line j unscanned
            // -- this fires AFTER ScanLine(Lines[j]) already advanced St
            // across line j. So line j must be emitted HERE (inclusive) and
            // never re-scanned by the top-level loop's own ScanLine call;
            // otherwise St.Depth double-counts line j's brackets (ClampDepth
            // only floors decrements, so a net-open bracket on line j -- e.g.
            // a split set/array default -- could leave Depth stuck above 0
            // and silently suppress every later header-join in the file).
            for var k:= i to j do begin Out_.Append(Lines[k]); Out_.Append(CRLF); end;
            i:= j + 1; Continue;
          end; // if
          if Aborted or (j >= Lines.Count) then
          begin
            // Bail (block-keyword / ran-out-of-lines): emit the original span
            // verbatim. Line j itself is UNSCANNED here (StartsBlockKeyword
            // trips before its ScanLine call), so it is excluded from this
            // range and left for the top-level loop to scan fresh.
            for var k:= i to j - 1 do begin Out_.Append(Lines[k]); Out_.Append(CRLF); end;
            i:= j; Continue;
          end;
          Out_.Append(WrapHeaderLine(Joined)); Out_.Append(CRLF);
          i:= j + 1; Continue;
        end // if
        else
        begin
          ScanLine(Lines[i], CmtOpen); // keep cross-line St correct
          Out_.Append(Lines[i]); Out_.Append(CRLF);
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

function CollapseShortBlocks(const S: string; AMaxLen: Integer): string;
var
  Lines : TStringList    ;
  Lock  : TArray<Boolean>;
  Out_  : TStringBuilder ;
  i     : Integer        ;
  j     : Integer        ;
  Tj    : string         ;
  Body  : string         ;
  EndLn : string         ;
  Indent: string         ;
  Joined: string         ;
  Ok    : Boolean        ;

  function StartsWordCI(const L, W: string): Boolean;
  var
    T: string;
  begin
    T:= TrimLeft(L);
    if Length(T) < Length(W) then
      Exit(False);
    if not SameText(Copy(T, 1, Length(W)), W) then
      Exit(False);
    if Length(T) > Length(W) then
      Result:= not (CharInSet(T[Length(W) + 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']))
    else
      Result:= True;
  end;

  function EndsWordCI(const L, W: string): Boolean;
  var
    T: string ;
    p: Integer;
  begin
    T:= TrimRight(L);
    if Length(T) < Length(W) then
      Exit(False);
    p:= Length(T) - Length(W) + 1;
    if not SameText(Copy(T, p, Length(W)), W) then
      Exit(False);
    if p > 1 then
      Result:= not (CharInSet(T[p - 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']))
    else
      Result:= True;
  end;

// ends in a control header (then/do/else) that legally precedes a begin block
  function IsHeaderEnd(const L: string): Boolean;
  begin
    Result:= EndsWordCI(L, 'then') or EndsWordCI(L, 'do') or EndsWordCI(L, 'else');
  end;

// True iff L contains AWord as a whole word anywhere. Used to reject a body
// line that itself holds an inline begin/end (an already-collapsed inner
// block or an anonymous method): folding it into an OUTER block would make
// the pass non-idempotent (the outer would only collapse on a second run)
// and over-nest a one-liner. Keeping the collapse strictly leaf-level fixes
// both. Not string-aware on purpose -- a literal 'begin' merely declines the
// collapse, which is safe and still deterministic (idempotent).
  function ContainsWordCI(const L, AWord: string): Boolean;
  var
    p   : Integer;
    n   : Integer;
    Good: Boolean;
  begin
    n:= Length(AWord);
    p:= 1;
    while p <= Length(L) - n + 1 do
    begin
      if SameText(Copy(L, p, n), AWord) then
      begin
        Good:= True;
        if (p > 1) and CharInSet(L[p - 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
          Good:= False;
        if (p + n <= Length(L)) and CharInSet(L[p + n], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then
          Good:= False;
        if Good then
          Exit(True);
      end;
      Inc(p);
    end;
    Result:= False;
  end; // function

// any comment involvement on the line forbids collapse (over-conservative on
// `//` inside a string -- safe: we just decline to collapse that block)
  function HasCommentChars(const L: string): Boolean;
  var
    p: Integer;
  begin
    for p:= 1 to Length(L) do
    begin
      if L[p] = '{' then
        Exit(True);
      if (p < Length(L)) and (L[p] = '(') and (L[p + 1] = '*') then
        Exit(True);
      if (p < Length(L)) and (L[p] = '/') and (L[p + 1] = '/') then
        Exit(True);
    end;
    Result:= False;
  end;

// Squeeze runs of spaces to one, OUTSIDE string literals (handles the
// doubled-quote escape so a string's interior is preserved byte-for-byte).
  function Squeeze(const L: string): string;
  var
    p     : Integer       ;
    inStr : Boolean       ;
    Sb    : TStringBuilder;
  begin
    Sb:= TStringBuilder.Create;
    try
      inStr:= False;
      p    := 1;
      while p <= Length(L) do
      begin
        if inStr then
        begin
          Sb.Append(L[p]);
          if L[p] = '''' then
          begin
            if (p + 1 <= Length(L)) and (L[p + 1] = '''') then
            begin
              Sb.Append(L[p + 1]);
              Inc(p, 2);
              Continue;
            end
            else
              inStr:= False;
          end;
          Inc(p);
        end // if
        else if L[p] = '''' then
        begin
          inStr:= True;
          Sb.Append(L[p]);
          Inc(p);
        end
        else if L[p] = ' ' then
        begin
          Sb.Append(' ');
          while (p <= Length(L)) and (L[p] = ' ') do
            Inc(p);
        end
        else
        begin
          Sb.Append(L[p]);
          Inc(p);
        end;
      end; // while
      Result:= Sb.ToString;
    finally
      Sb.Free;
    end; // try
  end; // function

  function LeadingWS(const L: string): string;
  var
    p: Integer;
  begin
    p:= 1;
    while (p <= Length(L)) and ((L[p] = ' ') or (L[p] = #9)) do
      Inc(p);
    Result:= Copy(L, 1, p - 1);
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    // Per-line "inside a block comment" flags (a multi-line { } / (* *)
    // interior never participates) -- the shared scanner's lock helper.
    Lock:= ComputeBlockCommentLock(Lines);
    Out_:= TStringBuilder.Create;
    try
      i:= 0;
      while i < Lines.Count do
      begin
        // trigger: control header, then a `begin`-only line
        if (not Lock[i]) and IsHeaderEnd(Lines[i]) and (not HasCommentChars(Lines[i])) and (Pos('__YADF_ML', Lines[i]) = 0)
          and (i + 1 < Lines.Count) and (not Lock[i + 1]) and SameText(Trim(Lines[i + 1]), 'begin') then
        begin
          j:= i + 2;
          Ok  := True;
          Body:= '';
          while True do
          begin
            if j >= Lines.Count then begin Ok:= False; Break; end;
            if Lock[j] then begin Ok:= False; Break; end;
            Tj:= Trim(Lines[j]);
            if StartsWordCI(Tj, 'end') then Break; // matching end
            // a shielded multi-line string/comment sentinel would re-expand to
            // several lines after unshield -- never fold one into a one-liner
            if (Tj = '') or HasCommentChars(Lines[j]) or (Tj[Length(Tj)] <> ';') or (Pos('__YADF_ML', Lines[j]) > 0)
              or ContainsWordCI(Tj, 'begin') or ContainsWordCI(Tj, 'end') then
            begin Ok:= False; Break; end;
            Body:= Body + ' ' + Tj;
            Inc(j);
          end; // while
          if Ok and (j < Lines.Count) then
          begin
            EndLn := Trim     (Lines[j]);
            Indent:= LeadingWS(Lines[i]);
            Joined:= Indent + Squeeze(Trim(Lines[i]) + ' begin' + Body + ' ' + EndLn);
            if Length(Joined) <= AMaxLen then
            begin
              Out_.Append(Joined);
              Out_.Append(CRLF  );
              i:= j + 1;
              Continue;
            end;
          end; // if
        end; // if
        Out_.Append(Lines[i]);
        Out_.Append(CRLF);
        Inc(i);
      end; // while
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end; // try
  finally
    Lines.Free;
  end; // try
end; // function

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
    if Length(Trimmed) < Length(AWord) then
      Exit(False);
    if not SameText(Copy(Trimmed, 1, Length(AWord)), AWord) then
      Exit(False);
    if Length(Trimmed) > Length(AWord) then
      Result:= not (((Trimmed[Length(AWord) + 1] >= 'a') and (Trimmed[Length(AWord) + 1] <= 'z')) or
        ((Trimmed[Length(AWord) + 1] >= 'A') and (Trimmed[Length(AWord) + 1] <= 'Z')) or ((Trimmed[Length(AWord) + 1] >= '0') and (Trimmed[Length(AWord) + 1] <= '9')) or
        (Trimmed[Length(AWord) + 1] = '_'))
    else
      Result:= True;
  end; // function

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
    // BlanksBeforeMethod targets TOP-LEVEL routine declarations only. A method
    // declared INSIDE a class / record / interface type block is indented (this
    // pass runs after ReindentByDepth, so leading whitespace is canonical), so a
    // leading space/tab marks it as a member -- never separate those with blank
    // lines, which would corrupt the interface section. (Bug repro 2026-06-19.)
    if (ALine <> '') and CharInSet(ALine[1], [' ', #9]) then
      Exit(False);
    T:= TrimLeft(ALine);
    Result:= StartsWordCI(T, 'procedure') or StartsWordCI(T, 'function') or StartsWordCI(T, 'constructor') or StartsWordCI(T, 'destructor');
    if Result and StartsWordCI(T, 'class') then
      Result:= False;
  end; // function

var
  Have : Integer       ;
  i    : Integer       ;
  j    : Integer       ;
  Lines: TStringList   ;
  Need : Integer       ;
  Out_ : TStringBuilder;
begin
  if (AOpts.BlanksBeforeSection <= 0) and (AOpts.BlanksBeforeMethod <= 0) and (AOpts.BlanksBeforeType <= 0) then
    Exit(S);
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Need:= 0;
        if (AOpts.BlanksBeforeSection > 0) and IsSectionKw(Lines[i]) then
          Need:= AOpts.BlanksBeforeSection;
        if (AOpts.BlanksBeforeType > 0) and IsTypeKw(Lines[i]) then
          if AOpts.BlanksBeforeType > Need then
            Need:= AOpts.BlanksBeforeType;
        if (AOpts.BlanksBeforeMethod > 0) and IsMethodDecl(Lines[i]) then
          if AOpts.BlanksBeforeMethod > Need then
            Need:= AOpts.BlanksBeforeMethod;
        if (Need > 0) and (i > 0) then
        begin
          Have:= 0;
          j:= i - 1;
          while (j >= 0) and (Trim(Lines[j]) = '') do
          begin
            Inc(Have);
            Dec(j   );
          end;
          while Have < Need do
          begin
            Out_.Append(CRLF);
            Inc(Have);
          end;
        end; // if
        Out_.Append(Lines[i]);
        Out_.Append(CRLF);
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
  Blanks : Integer       ;
  i      : Integer       ;
  IsBlank: Boolean       ;
  Lines  : TStringList   ;
  Out_   : TStringBuilder;
begin
  if AMax < 0 then
    Exit(S);
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
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
        Out_.Append(CRLF);
      end; // for
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
function ReindentByDepth(const ASrc: string; AIndent: Integer; AIndentComments: Boolean = True): string;
var
  AfterCRLF         : Boolean            ;
  PendingCtrl       : Integer            ; // accumulated then/do/else/case-`:` body levels
  CtrlCarried       : Integer            ; // control levels locked into open begin/case/try blocks
  CtrlStack         : TList<Integer>     ; // carried-control per Stack entry (parallel to Stack)
  CurLineLast       : TptTokenKind       ;
  EffectiveDepth    : Integer            ;
  ExpectSectionDecl : Boolean            ;
  i                 : Integer            ;
  InInterfaceSection: Boolean            ;
  InUsesClause      : Boolean            ;
  InVisibility      : Boolean            ;
  VisOnThisLine     : Boolean            ;
  IsProcBody        : TList<Boolean>     ;
  DirDepths         : TList<Integer>     ;
  OpenProcRegions   : Integer            ;
  Out_              : TStringBuilder     ;
  ParensDepth       : Integer            ;
  PendingProcStack  : TList<Boolean>     ;
  PendingWS         : string             ;
  PrevNonKind       : TptTokenKind       ;
  Stack             : TList<TptTokenKind>;
  T                 : TToken             ;
  Tokens            : TTokenList         ;

  function StackContainsCaseAtTop: Boolean;
  var
    k: Integer;
  begin
    for k:= Stack.Count - 1 downto 0 do case Stack[k] of
      ptCase                                                         : Exit(True) ;
      ptBegin, ptRecord, ptTry, ptAsm, ptObject, ptClass, ptInterface: Exit(False);
    end;
    Result:= False;
  end;

  function StackTop: TptTokenKind;
  begin
    if Stack.Count = 0 then
      Result:= ptUnknown
    else
      Result:= Stack[Stack.Count - 1];
  end;

  function InClassOrRecord: Boolean;
  var
    k: Integer;
  begin
    for k:= 0 to Stack.Count - 1 do if Stack[k] in [ptClass, ptObject, ptInterface, ptRecord] then
      Exit(True);
    Result:= False;
  end;

// Records how many pending control levels this block carries (the levels
// ABOVE its immediate controller). 0 in declaration contexts (PendingCtrl
// is 0 there), nonzero only for a begin/case/try opened as a nested
// then/do/else/case-arm body. Released when the block pops.
  procedure PushCtrlCarry;
  var
    Carry: Integer;
  begin
    Carry:= Max(0, PendingCtrl - 1);
    CtrlStack.Add(Carry);
    Inc(CtrlCarried, Carry);
    PendingCtrl:= 0;
  end;

  procedure StackPush(k: TptTokenKind);
  begin
    PushCtrlCarry;
    Stack     .Add(k    );
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
    PushCtrlCarry;
    Stack     .Add(ptBegin);
    IsProcBody.Add(IsBody );
  end; // procedure

  procedure StackPop;
  begin
    if Stack.Count > 0 then
    begin
      if CtrlStack.Count > 0 then
      begin
        Dec(CtrlCarried, CtrlStack[CtrlStack.Count - 1]);
        CtrlStack.Delete(CtrlStack.Count - 1);
      end;
      if (IsProcBody.Count > 0) and IsProcBody[IsProcBody.Count - 1] then
        if OpenProcRegions > 0 then
          Dec(OpenProcRegions);
      if IsProcBody.Count > 0 then
        IsProcBody.Delete(IsProcBody.Count - 1);
      Stack       .Delete(Stack     .Count - 1);
    end; // if
  end; // procedure

  procedure CloseSectionIfOpen;
  begin
    if StackTop in [ptType, ptVar, ptConst] then
      StackPop;
  end;

// True when a `case` met at the current stack state is the VARIANT PART of
// a record/object declaration: the nearest non-section stack entry --
// probing past an open var/const/type section, which shares this stack
// (advanced records may declare `var A: Integer;` before the variant part)
// -- is a record/object block. Group-level twin: YADF.Groups.IsVariantPartCase.
  function CaseIsVariantPart: Boolean;
  var
    k: Integer;
  begin
    k:= Stack.Count - 1;
    while (k >= 0) and (Stack[k] in [ptType, ptVar, ptConst]) do
      Dec(k);
    Result:= (k >= 0) and (Stack[k] in [ptRecord, ptObject]);
  end;

// True when token AIdx is the `class` of a class-static section header
// `class var` / `class const` / `class type` -- i.e. `class` immediately
// followed by a section keyword. Such a line starts a section, so it must
// dedent like a bare `var`/`const`/`type` even though its first token is `class`.
  function IsClassSectionLine(AIdx: Integer): Boolean;
  var
    j: Integer;
  begin
    Result:= False;
    if (AIdx < 0) or (AIdx >= Tokens.Count) or (Tokens[AIdx].Kind <> ptClass) then
      Exit;
    j:= AIdx + 1;
    while (j < Tokens.Count) and (Tokens[j].Kind in [ptSpace, ptCRLF, ptCRLFCo]) do
      Inc(j);
    Result:= (j < Tokens.Count) and (Tokens[j].Kind in [ptVar, ptConst, ptType]);
  end;

begin
  Tokens:= LoadTokensFromString(ASrc);
  try
    Out_:= TStringBuilder.Create;
    Stack           := TList<TptTokenKind>.Create;
    IsProcBody      := TList<Boolean     >.Create;
    PendingProcStack:= TList<Boolean     >.Create;
    DirDepths       := TList<Integer     >.Create;
    CtrlStack       := TList<Integer     >.Create;
    try
      PrevNonKind       := ptUnknown;
      InVisibility      := False;
      VisOnThisLine     := False;
      AfterCRLF         := False;
      ParensDepth       := 0;
      PendingWS         := '';
      CurLineLast       := ptUnknown;
      PendingCtrl       := 0;
      CtrlCarried       := 0;
      InUsesClause      := False;
      OpenProcRegions   := 0;
      InInterfaceSection:= False;
      ExpectSectionDecl := False;
      for i:= 0 to Tokens.Count - 1 do
      begin
        T:= Tokens[i];

        if T.Kind in [ptCRLF, ptCRLFCo] then
        begin
          Out_.Append(T.Text);
          AfterCRLF    := True;
          PendingWS    := '';
          VisOnThisLine:= False;
          // Accumulate / clear the controlled-statement level. then/do/else
          // and a case-arm `:` each add a level for the body on the following
          // line(s); a top-level `;` ends a simple statement chain; opening or
          // closing a block clears it (the block carries its own level). For
          // `else` the paired then-level was already consumed when the `else`
          // token was seen, so the +1 here re-establishes the else body's level.
          case CurLineLast of
            ptThen, ptDo, ptElse: Inc(PendingCtrl);
            ptColon             : if StackContainsCaseAtTop then
              Inc(PendingCtrl);
            ptSemiColon: if ParensDepth = 0 then
              PendingCtrl:= 0;
            ptEnd, ptBegin, ptCase, ptRecord, ptTry, ptAsm, ptObject, ptRepeat, ptUntil: PendingCtrl:= 0;
          end;
          CurLineLast      := ptUnknown;
          ExpectSectionDecl:= False;
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
          while (Out_.Length > 0) and (Out_.Chars[Out_.Length - 1] = ' ') do
            Out_.Length:= Out_.Length - 1;
          Out_.Append(CRLF);
          AfterCRLF        := True;
          PendingWS        := '';
          CurLineLast      := ptUnknown;
          ExpectSectionDecl:= False;
        end;

        if AfterCRLF and (InUsesClause or (T.Kind in [
              ptPlus, ptMinus, ptStar, ptSlash, ptComma, ptOr, ptAnd, ptXor, ptDiv, ptMod, ptShl, ptShr, ptEqual, ptLower, ptGreater, ptLowerEqual, ptGreaterEqual, ptNotEqual,
              ptDotDot, ptPoint, ptThen, ptDo, ptOf])) then
        begin
          Out_.Append(PendingWS);
          PendingWS:= '';
          AfterCRLF:= False;
        end
        else if AfterCRLF and (T.Kind in [ptSlashesComment, ptBorComment, ptAnsiComment]) and ((not AIndentComments) or (Copy(T.Text, 1, 3) = '//.')) then
        begin
          // Comment-only line, with comment-indenting disabled (IndentComments
          // = false) OR a `//.`-pinned line: keep the author's leading
          // whitespace verbatim instead of re-deriving it from code depth.
          // PendingWS holds that original indentation (accumulated above).
          Out_.Append(PendingWS);
          PendingWS:= '';
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
          // A class/record `end` that follows an open var/const/type section
          // implicitly closes that section, so dedent past it to align the `end`
          // with the class/record opener (sections have no `end` of their own).
          if (T.Kind = ptEnd) and (StackTop in [ptType, ptVar, ptConst]) then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if T.Kind in [ptExcept, ptFinally] then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if ((T.Kind in [ptType, ptVar, ptConst]) or IsClassSectionLine(i)) and (StackTop in [ptType, ptVar, ptConst]) then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if (T.Kind = ptBegin) and (not InClassOrRecord) and (StackTop in [ptType, ptVar, ptConst]) then
            EffectiveDepth:= Max(0, EffectiveDepth - 1);
          if (T.Kind in [ptProcedure, ptFunction, ptConstructor, ptDestructor]) and (not InClassOrRecord) and (ParensDepth = 0) then
            // ParensDepth = 0: only a REAL proc/function declaration snaps to the
            // proc-region column. An anonymous method inside an expression
            // (ParensDepth > 0, e.g. List.Sort(function ... end)) keeps the normal
            // expression depth so its header lines up under the call argument
            // (matches the ParensDepth = 0 guard on the push side below).
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
          // Controlled-statement indent, composing across nesting:
          //   CtrlCarried  = levels locked into enclosing begin/case/try blocks
          //   PendingCtrl  = levels pending for this line from then/do/else/`:`
          // A block opener (begin/case/...), an `else`, or a closing end/until
          // ALIGNS with its controller -> it takes one less than the full
          // pending (so `begin` lines up under its `if`, and a same-line
          // `else if` ladder stays flat). Every other statement -- crucially a
          // nested `if` used as a body -- takes the full pending, so it indents
          // one level under its owner instead of sitting flat beside it.
          if T.Kind in [ptBegin, ptCase, ptTry, ptAsm, ptRecord, ptObject, ptElse, ptEnd, ptUntil] then
            Inc(EffectiveDepth, CtrlCarried + Max(0, PendingCtrl - 1))
          else
            Inc(EffectiveDepth, CtrlCarried + PendingCtrl);
          if (OpenProcRegions > 1) and not ((T.Kind in [ptProcedure, ptFunction, ptConstructor, ptDestructor]) and (not InClassOrRecord)) then
            Inc(EffectiveDepth, OpenProcRegions - 1);
          // Conditional compiler directives: align {$ELSE}/{$ENDIF} with their
          // matching {$IF}/{$IFDEF} by mirroring the depth recorded for the opener.
          // This keeps a directive group consistent in ANY context; it deliberately
          // does NOT indent the code between the directives (that would break inline
          // directives inside uses clauses / field lists / statement blocks).
          if T.Kind in [ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect] then
            DirDepths.Add(EffectiveDepth)
          else if (T.Kind in [ptElseDirect, ptElseIfDirect]) and (DirDepths.Count > 0) then
            EffectiveDepth:= DirDepths[DirDepths.Count - 1]
          else if (T.Kind in [ptEndIfDirect, ptIfEndDirect]) and (DirDepths.Count > 0) then
          begin
            EffectiveDepth:= DirDepths[DirDepths.Count - 1];
            DirDepths.Delete(DirDepths.Count - 1);
          end;
          Out_.Append(StringOfChar(' ', EffectiveDepth * AIndent));
          AfterCRLF:= False;
        end; // if

        Out_.Append(T.Text);

        if not (T.Kind in [ptAnsiComment, ptBorComment, ptSlashesComment]) then
        begin
          case T.Kind of
            ptRoundOpen, ptSquareOpen  : Inc(ParensDepth)                        ;
            ptRoundClose, ptSquareClose: if ParensDepth > 0 then Dec(ParensDepth);
            ptType, ptVar, ptConst     : if (ParensDepth = 0) and not (StackTop in [ptBegin, ptCase, ptTry, ptAsm]) then
            begin
              CloseSectionIfOpen;
              StackPush(T.Kind);
              // A var/const/type section inside a class/record must NOT clear the
              // visibility level -- it belongs to the current private/protected/...
              // group, so its fields (and any following section) keep that level
              // (#333). EXCEPTION: when the section keyword shares the line with the
              // visibility specifier (`public type` / `class var` after `private`...,
              // i.e. VisOnThisLine), the section push already provides the level, so
              // we clear it to avoid double-indenting the members (e.g. constset.pas).
              // Outside a class InVisibility is already False, so this is a no-op there.
              if (not InClassOrRecord) or VisOnThisLine then
                InVisibility   := False;
              ExpectSectionDecl:= True;
            end; // if
            ptProcedure, ptFunction, ptConstructor, ptDestructor: if (not InClassOrRecord) and (ParensDepth = 0) and (PrevNonKind <> ptEqual) and (PrevNonKind <> ptTo)
              and (PrevNonKind <> ptColon) then
              // ParensDepth = 0 distinguishes a real procedure/function
              // declaration from an inline anonymous method expression
              // (e.g. CallSomething(procedure(X) begin ... end)). The
              // anonymous form's inner begin/end is balanced on its own,
              // so we must NOT push a pending-proc marker for it -- if
              // we did, that marker would never be consumed, leaving
              // OpenProcRegions elevated and over-indenting every line
              // after the call. (Bug repro: inline anon proc, 2026-05-15.)
              // PrevNonKind <> ptEqual excludes a procedural / method-pointer
              // TYPE (`T = procedure(...)` / `T = function(...) of object`),
              // PrevNonKind <> ptTo the anonymous-method-reference TYPE
              // (`T = reference to function(...) stdcall`), and
              // PrevNonKind <> ptColon a procedural-type VARIABLE / field decl
              // (`A, B: procedure of object;` / `F: function: Integer;`) -- none
              // of these is a real routine, so they must NOT close the
              // surrounding type section or open a proc region (else the
              // routine's own begin/end over-indents). (Bug repro: leading
              // procedure/function var type, 2026-06-18.)
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
              if (not InClassOrRecord) then
                CloseSectionIfOpen;
              StackPushBegin;
              InVisibility:= False;
            end;
            ptRecord, ptTry, ptAsm, ptRepeat:
            begin
              StackPush(T.Kind);
              InVisibility:= False;
            end;
            ptCase:
            begin
              // The VARIANT PART of a record/object (`case Tag: T of` inside
              // the declaration, possibly nested inside the variant parens)
              // has NO end of its own -- the record's end closes it. Pushing a
              // block here made the record's end close the case instead,
              // leaving the record open and creeping every declaration after
              // it one level right (variant_record.pas fixture). The parens
              // are not on this stack, so probing past section entries down to
              // a record/object identifies the variant part in the direct, the
              // nested, and the after-a-var-section (advanced record) position.
              // Like `end`, the variant part closes any open var/const/type
              // section: the case line dedents back to the record level.
              if CaseIsVariantPart then
                CloseSectionIfOpen
              else
                StackPush(T.Kind);
              InVisibility:= False;
            end; // begin
            ptUntil:
            begin
              StackPop;
              InVisibility:= False;
            end;
            // `else` pairs with the nearest open then-level and consumes it
            // (the then-body is finished). The else's own line already aligned
            // with its `if` using the pre-consume value; the CRLF handler then
            // re-adds one level for the else body.
            ptElse           : PendingCtrl:= Max(0, PendingCtrl - 1);
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
              while Stack.Count > 0 do
                StackPop;
              InVisibility      := False;
              InInterfaceSection:= True;
              OpenProcRegions   := 0;
              PendingProcStack.Clear;
            end;
            ptImplementation, ptInitialization, ptFinalization:
            begin
              while Stack.Count > 0 do
                StackPop;
              InVisibility      := False;
              InInterfaceSection:= False;
              OpenProcRegions   := 0;
              PendingProcStack.Clear;
            end;
            ptEnd:
            begin
              CloseSectionIfOpen; // an open var/const/type section is closed by this end
              StackPop; // then pop the begin/class/record/... block itself
              InVisibility:= False;
            end;
            ptPrivate, ptPublic, ptProtected, ptPublished: begin InVisibility:= True; VisOnThisLine:= True; end;
            ptUses, ptContains, ptRequires               : InUsesClause:= True                                 ;
            ptSemiColon                                  : if (ParensDepth = 0) and InUsesClause then
              InUsesClause:= False;
            ptForward, ptExternal: if (not InClassOrRecord) and (PendingProcStack.Count > 0) then
            begin
              PendingProcStack.Delete(PendingProcStack.Count - 1);
              if OpenProcRegions > 0 then
                Dec(OpenProcRegions);
            end;
          end; // case
          if T.ExID in [ptPrivate, ptPublic, ptProtected, ptPublished] then
          begin
            InVisibility := True;
            VisOnThisLine:= True;
          end;
          if (T.ExID in [ptForward, ptExternal]) and (not InClassOrRecord) and (PendingProcStack.Count > 0) then
          begin
            PendingProcStack.Delete(PendingProcStack.Count - 1);
            if OpenProcRegions > 0 then
              Dec(OpenProcRegions);
          end;
          PrevNonKind:= T.Kind;
          CurLineLast:= T.Kind;
        end; // if
      end; // for
      Result:= Out_.ToString;
    finally
      PendingProcStack.Free;
      IsProcBody.Free;
      DirDepths.Free;
      CtrlStack.Free;
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
  CurText: string       ;
  i      : Integer      ;
  Items  : TList<string>;
  T      : TToken       ;
begin
  Items:= TList<string>.Create;
  try
    AHasInClause:= False;
    CurText     := '';
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
  BaseCol  : Integer       ;
  HasIn    : Boolean       ;
  i        : Integer       ;
  Indent   : string        ;
  InlineLen: Integer       ;
  Items    : TArray<string>;
  Joined   : string        ;
  OpenTok  : TToken        ;
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
    Sb.Append(OpenTok.Pre );
    Sb.Append(OpenTok.Text);
    if AOpts.UsesCommaLast then
    begin
      // Comma-LAST: each unit carries a trailing comma; the closing ';' sits on
      // the last unit's line.
      //     uses
      //       System.SysUtils,
      //       System.Classes;
      for i:= 0 to High(Items) do
      begin
        Sb.Append(CRLF  );
        Sb.Append(Indent);
        Sb.Append(Items[i]);
        if i < High(Items) then
          Sb.Append(',')
        else
          Sb.Append(';');
      end;
    end // if
    else
    begin
      // Comma-FIRST (default): leading comma per unit, ';' on its own line.
      for i:= 0 to High(Items) do
      begin
        Sb.Append(CRLF  );
        Sb.Append(Indent);
        if i = 0 then
          Sb.Append(Items[i])
        else
        begin
          Sb.Append(', ');
          Sb.Append(Items[i]);
        end;
      end; // for
      Sb.Append(CRLF  );
      Sb.Append(Indent);
      Sb.Append(';'   );
    end; // else
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
  HasContent: Boolean       ;
  i         : Integer       ;
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
    end; // for
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
    if (Pos(LF, ATokens[i].Text) > 0) or (Pos(CR, ATokens[i].Text) > 0) then
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
    First   : Integer;
    Last    : Integer;
    CmtFirst: Integer;
    CmtLast : Integer;
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
  CmtF     : Integer          ;
  CmtL     : Integer          ;
  CommaLine: Integer          ;
  CurFirst : Integer          ;
  CurLast  : Integer          ;
  Depth    : Integer          ;
  i        : Integer          ;
  Item     : TItemRange       ;
  Items    : TList<TItemRange>;
  k        : Integer          ;
  T        : TToken           ;
begin
  Items:= TList<TItemRange>.Create;
  try
    Depth:= 0;
    while (AOpenIdx + 1 <= ACloseIdx - 1) and (ATokens[AOpenIdx + 1].Kind in [ptSpace, ptCRLF]) do
      Inc(AOpenIdx);
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
          while (k <= ACloseIdx - 1) and (ATokens[k].Kind = ptSpace) do
            Inc(k);
          if (k <= ACloseIdx - 1) and IsCommentKind(ATokens[k].Kind) and (ATokens[k].Line = CommaLine) then
          begin
            if CmtF < 0 then
              CmtF:= k;
            CmtL  := k;
            Inc(k);
            Continue;
          end;
          Break;
        end; // while
        if CurLast < CurFirst then
          CurLast:= i - 1;
        Item.First   := CurFirst;
        Item.Last    := CurLast;
        Item.CmtFirst:= CmtF;
        Item.CmtLast := CmtL;
        Items.Add(Item);
        while (k <= ACloseIdx - 1) and (ATokens[k].Kind in [ptSpace, ptCRLF]) do
          Inc(k);
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
  i    : Integer     ;
  k    : TptTokenKind;
  Limit: Integer     ;
begin
  case ATokens[AOpenIdx].Kind of
    ptRecord: Exit('record');
    ptCase  : Exit('case')  ;
    ptTry   : Exit('try')   ;
    ptAsm   : Exit('asm')   ;
    ptObject: Exit('object');
  end;
  i:= AOpenIdx - 1;
  Limit:= 300;
  while (i >= 0) and (Limit > 0) do
  begin
    Dec(Limit);
    k:= ATokens[i].Kind;
    if k in [
      ptSpace, ptCRLF, ptCRLFCo, ptAnsiComment, ptBorComment, ptSlashesComment, ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect,
      ptIfEndDirect] then
    begin
      Dec(i);
      Continue;
    end;
    case k of
      ptDo, ptThen    :                       ;
      ptElse          : Exit('else')          ;
      ptProcedure     : Exit('procedure')     ;
      ptFunction      : Exit('function')      ;
      ptConstructor   : Exit('constructor')   ;
      ptDestructor    : Exit('destructor')    ;
      ptWhile         : Exit('while')         ;
      ptFor           : Exit('for')           ;
      ptIf            : Exit('if')            ;
      ptCase          : Exit('case')          ;
      ptTry           : Exit('try')           ;
      ptInitialization: Exit('initialization');
      ptFinalization  : Exit('finalization')  ;
      ptEnd           : Exit('begin')         ;
    end; // case
    Dec(i);
  end; // while
  Result:= 'begin';
end; // function

// Multi-line ATOMS -- ('''...''') string literals AND multi-line block
// comments ({...}, (*...*)) -- must survive Stage 3/4 byte-for-byte: their
// interior is data/prose, not code, so re-indent/reflow/align must never
// touch it. The Stage 3/4 line-based passes re-lex each output line in
// ISOLATION, so an interior line of a multi-line atom (which carries no
// opening delimiter) is mistaken for code: its alignment whitespace gets
// collapsed and ReindentByDepth's depth tracker would scan its interior for
// begin/end and corrupt the indentation of real code that follows.
// ShieldMultilineTokens replaces each such TOKEN with a single-line sentinel
// of the MATCHING kind -- a one-line string for a string literal, a one-line
// brace comment for a block comment -- so every line-based pass treats it as
// one inert atom (and both forms are safe to sit mid-line, before/after real
// code). UnshieldMultilineTokens puts the originals back verbatim as the very
// last step. We shield at the TOKEN level -- the lexer has already found the
// exact boundaries (lone apostrophes in '''...''', nested-looking braces in a
// comment) -- and every render path (WalkGroup, EmitTokenRange,
// InlineRenderRange) reads Token.Text, so swapping the text shields all of
// them at once. Single-line block comments are NOT shielded: they are one
// token on their own line and the per-line re-lex already preserves them.
function MlStrSentinel(AIdx: Integer): string;
begin
  Result:= '''__YADF_ML_' + IntToStr(AIdx) + '__''';
end;

function MlComSentinel(AIdx: Integer): string;
begin
  Result:= '{__YADF_MLC_' + IntToStr(AIdx) + '__}';
end;

procedure ShieldMultilineTokens(const ATokens: TTokenList; const AMap: TStringList);
var
  i: Integer;
  T: TToken ;
begin
  AMap.Clear;
  for i:= 0 to ATokens.Count - 1 do
  begin
    T:= ATokens[i];
    if (Pos(LF, T.Text) = 0) and (Pos(CR, T.Text) = 0) then
      Continue;
    if T.Kind in [ptStringConst, ptStringDQConst] then
    begin
      AMap.Add(T.Text);
      T.Text:= MlStrSentinel(AMap.Count - 1);
      ATokens[i]:= T;
    end
    else if T.Kind in [ptBorComment, ptAnsiComment] then
    begin
      AMap.Add(T.Text);
      T.Text:= MlComSentinel(AMap.Count - 1);
      ATokens[i]:= T;
    end;
  end; // for
end; // procedure

function UnshieldMultilineTokens(const S: string; const AMap: TStringList): string;
var
  i: Integer;
begin
  Result:= S;
  // Reverse order so sentinel N can never be a prefix-match inside sentinel NN.
  // Only one sentinel form exists per index (string vs comment); the other
  // StringReplace is a harmless no-op.
  for i:= AMap.Count - 1 downto 0 do
  begin
    Result:= StringReplace(Result, MlStrSentinel(i), AMap[i], [rfReplaceAll]);
    Result:= StringReplace(Result, MlComSentinel(i), AMap[i], [rfReplaceAll]);
  end;
end; // function

// Delphi 10.2.3 compatibility: hoist inline `var` declarations into a classic
// top-of-routine `var` block so the code builds on pre-10.3 compilers. A
// self-contained token->token pass run before ParseGroups (so it cannot
// invalidate the group tree). Active only when AOpts.Delphi10Compat is set;
// downgrades inline var/const and untyped `for var`, flagging any residual
// construct it cannot rewrite with a TODO comment.
procedure DowngradeInlineVars(const ATokens: TTokenList; const AOpts: TYadfOptions);
type
  TInlineKind = (ikExplicitInit, ikExplicitNoInit, ikForExplicit, ikFallbackTodo);
  TInlineRec  = record
    Kind     : TInlineKind   ;
    NameIdx  : Integer       ; // identifier token (the var name)
    AssignIdx: Integer       ; // ptAssign index (statement init forms; else -1)
    SemiIdx  : Integer       ; // terminating ptSemiColon (statement forms; else -1)
    Sep      : Integer       ; // for-var: resume index (the `:=` or `in` token)
    SepIsIn  : Boolean       ; // for-var: True when Sep is `in`
    DeclLines: TArray<string>; // hoisted 'Name: Type;' lines (one per name)
    Names    : TArray<string>; // hoisted names (parallel to DeclLines)
    TypeStr  : string        ; // shared type of the hoisted names (collision check)
    Comment  : string        ; // fallback: trailing '// TODO -oYADF ...' text
  end; // record
var
  Root       : TGroup                                 ;
  Outp       : TTokenList                             ;
  Inlines    : TDictionary<Integer, TInlineRec>       ; // key = inline `var` token index
  BodyDecls  : TObjectDictionary<Integer, TStringList>; // key = routine `begin` token index
  BodyConst  : TObjectDictionary<Integer, TStringList>; // hoisted inline-CONST decls per routine `begin`
  ForTodos   : TDictionary<Integer, string>           ; // non-inferable for-var -> TODO before the `for`
  RNames     : TDictionary<string, string>            ; // per-routine name -> hoisted type
  BlkAnon    : TList<Boolean>                         ; // open blocks in body; True = anon-method body
  BlkKind    : TList<TptTokenKind>                    ; // opener kinds, index-aligned to BlkAnon
  G          : TGroup                                 ;
  i          : Integer                                ;
  k          : Integer                                ;
  pv         : Integer                                ;
  AnonCount  : Integer                                ;
  PendingAnon: Boolean                                ;
  IsAnon     : Boolean                                ;
  Ki         : TptTokenKind                           ;
  Rec        : TInlineRec                             ;
  constDecl  : string                                 ;
  todoText   : string                                 ;
  flagTok    : TToken                                 ;

  function NextSig(AFrom: Integer): Integer;
  begin
    Result:= AFrom;
    while (Result < ATokens.Count) and (ATokens[Result].Kind in [ptSpace, ptCRLF, ptCRLFCo]) do
      Inc(Result);
  end;

  function PrevSig(AFrom: Integer): Integer;
  begin
    Result:= AFrom;
    while (Result >= 0) and (ATokens[Result].Kind in [ptSpace, ptCRLF, ptCRLFCo]) do
      Dec(Result);
  end;

// True when the statement ending at ASemi already carries a `// ... YADF ...`
// marker -- i.e. we flagged it on a previous run. Keeps the pass idempotent and
// stops us re-touching a statement the user was asked to resolve manually.
  function AlreadyFlagged(ASemi: Integer): Boolean;
  var
    nx: Integer;
  begin
    nx:= NextSig(ASemi + 1);
    Result:= (nx < ATokens.Count) and (ATokens[nx].Kind = ptSlashesComment) and (Pos('YADF', ATokens[nx].Text) > 0);
  end;

  function EnsureBodyDecls(ABeginIdx: Integer): TStringList;
  begin
    if not BodyDecls.ContainsKey(ABeginIdx) then
      BodyDecls.Add(ABeginIdx, TStringList.Create);
    Result:= BodyDecls[ABeginIdx];
  end;

  function EnsureBodyConst(ABeginIdx: Integer): TStringList;
  begin
    if not BodyConst.ContainsKey(ABeginIdx) then
      BodyConst.Add(ABeginIdx, TStringList.Create);
    Result:= BodyConst[ABeginIdx];
  end;

  function MakeTok(AKind: TptTokenKind; const AText: string): TToken;
  begin
    Result.Kind:= AKind; Result.ExID:= ptUnknown; Result.Text:= AText;
    Result.Pre := ''   ; Result.Line:= 0        ; Result.Col := 0;
  end;

// Terminating ptSemiColon for a statement scanned from AFrom, tracking () and
// [] depth. Reports the first top-level ptAssign into AAssign (-1 if none).
  function FindStmtEnd(AFrom: Integer; out AAssign: Integer): Integer;
  var
    j    : Integer;
    Depth: Integer;
  begin
    AAssign:= -1; Result:= -1; Depth:= 0; j:= AFrom;
    while j < ATokens.Count do
    begin
      case ATokens[j].Kind of
        ptRoundOpen, ptSquareOpen  : Inc(Depth)                                       ;
        ptRoundClose, ptSquareClose: if Depth > 0 then Dec(Depth)                     ;
        ptAssign                   : if (Depth = 0) and (AAssign < 0) then AAssign:= j;
        ptSemiColon                : if Depth = 0 then begin Result:= j; Exit; end    ;
      end;
      Inc(j);
    end;
  end; // function

// Single-name, explicitly-typed inline var at ptVar index AVar.
  function TryParseExplicit(AVar: Integer; out ARec: TInlineRec): Boolean;
  var
    firstName: Integer       ;
    p        : Integer       ;
    ci       : Integer       ;
    ao       : Integer       ;
    semi     : Integer       ;
    typeEnd  : Integer       ;
    n        : Integer       ;
    ty       : string        ;
    Names    : TArray<string>;
  begin
    Result:= False;
    firstName:= NextSig(AVar + 1);
    if (firstName >= ATokens.Count) or (ATokens[firstName].Kind <> ptIdentifier) then
      Exit;
    SetLength(Names, 1); Names[0]:= ATokens[firstName].Text;
    // Collect any comma-separated additional names (`var A, B: T;`).
    p:= NextSig(firstName + 1);
    while (p < ATokens.Count) and (ATokens[p].Kind = ptComma) do
    begin
      p:= NextSig(p + 1);
      if (p >= ATokens.Count) or (ATokens[p].Kind <> ptIdentifier) then
        Exit;
      SetLength(Names, Length(Names) + 1); Names[High(Names)]:= ATokens[p].Text;
      p:= NextSig(p + 1);
    end;
    ci:= p;
    if (ci >= ATokens.Count) or (ATokens[ci].Kind <> ptColon) then Exit; // inferred types: later
    semi:= FindStmtEnd(ci + 1, ao);
    if semi < 0 then
      Exit;
    if AlreadyFlagged(semi) then Exit; // left for the user on a previous run
    // A multi-name inline var cannot carry an initializer, so init applies only to
    // the single-name case.
    if (Length(Names) = 1) and (ao >= 0) and (ao < semi) then
    begin
      typeEnd:= ao - 1; ARec.Kind:= ikExplicitInit; ARec.AssignIdx:= ao;
    end
    else
    begin
      typeEnd:= semi - 1; ARec.Kind:= ikExplicitNoInit; ARec.AssignIdx:= -1;
    end;
    ty:= Trim(InlineRenderRange(ATokens, ci + 1, typeEnd));
    if ty = '' then
      Exit;
    SetLength(ARec.DeclLines, Length(Names));
    for n:= 0 to High(Names) do
      ARec.DeclLines[n]:= Names[n] + ': ' + ty + ';';
    ARec.Names  := Names;
    ARec.TypeStr:= ty;
    ARec.NameIdx:= firstName;
    ARec.SemiIdx:= semi;
    ARec.Sep:= -1;
    ARec.SepIsIn:= False;
    Result:= True;
  end; // function

// First `:=` or `in` at depth 0 from AFrom; bounded by `do`/`;`. The loop
// header separator that ends a `for var Name: Type ...` declaration.
  function FindForSep(AFrom: Integer; out ASep: Integer): Boolean;
  var
    j    : Integer;
    Depth: Integer;
  begin
    Result:= False; ASep:= -1; Depth:= 0; j:= AFrom;
    while j < ATokens.Count do
    begin
      case ATokens[j].Kind of
        ptRoundOpen, ptSquareOpen  : Inc(Depth)                                       ;
        ptRoundClose, ptSquareClose: if Depth > 0 then Dec(Depth)                     ;
        ptAssign, ptIn             : if Depth = 0 then begin ASep:= j; Exit(True); end;
        ptSemiColon, ptDo          : if Depth = 0 then Exit(False)                    ;
      end;
      Inc(j);
    end;
  end; // function

// Single-name, explicitly-typed `for var Name: Type := ...` / `... in ...`.
  function TryParseForExplicit(AVar: Integer; out ARec: TInlineRec): Boolean;
  var
    ni : Integer;
    ci : Integer;
    Sep: Integer;
    ty : string ;
  begin
    Result:= False;
    ni:= NextSig(AVar + 1);
    if (ni >= ATokens.Count) or (ATokens[ni].Kind <> ptIdentifier) then
      Exit;
    ci:= NextSig(ni + 1);
    if (ci >= ATokens.Count) or (ATokens[ci].Kind <> ptColon) then Exit; // explicit only
    if not FindForSep(ci + 1, Sep) then
      Exit;
    ty:= Trim(InlineRenderRange(ATokens, ci + 1, Sep - 1));
    if ty = '' then
      Exit;
    ARec.Kind   := ikForExplicit;
    ARec.NameIdx:= ni;
    ARec.AssignIdx:= -1;
    ARec.SemiIdx  := -1;
    ARec.Sep:= Sep;
    ARec.SepIsIn:= ATokens[Sep].Kind = ptIn;
    SetLength(ARec.DeclLines, 1);
    ARec.DeclLines[0]:= ATokens[ni].Text + ': ' + ty + ';';
    SetLength(ARec.Names, 1);
    ARec.Names[0]:= ATokens[ni].Text;
    ARec.TypeStr:= ty;
    Result:= True;
  end; // function

// Single-name, UNTYPED `for var Name := lo to hi do` -- infer the loop type
// from an integer literal lower bound (the overwhelmingly common `0/1 to N`).
// The `in` form (element type) and non-literal bounds are not inferred and are
// left untouched -- a conservative miss, never a wrong type.
  function TryParseForInferred(AVar: Integer; out ARec: TInlineRec): Boolean;
  var
    ni : Integer;
    ci : Integer;
    Sep: Integer;
    lo : Integer;
    ty : string ;
  begin
    Result:= False;
    ni:= NextSig(AVar + 1);
    if (ni >= ATokens.Count) or (ATokens[ni].Kind <> ptIdentifier) then
      Exit;
    ci:= NextSig(ni + 1);
    if (ci < ATokens.Count) and (ATokens[ci].Kind = ptColon) then Exit; // typed: TryParseForExplicit
    if not FindForSep(ni + 1, Sep) then
      Exit;
    if ATokens[Sep].Kind <> ptAssign then Exit; // `in` form -> not inferable
    lo:= NextSig(Sep + 1);
    if (lo < ATokens.Count) and (ATokens[lo].Kind = ptIntegerConst) then
      ty:= 'Integer'
    else Exit; // non-literal bound -> leave as-is
    ARec.Kind   := ikForExplicit; // reuse the for rewrite (strip `var`)
    ARec.NameIdx:= ni;
    ARec.AssignIdx:= -1;
    ARec.SemiIdx  := -1;
    ARec.Sep    := Sep;
    ARec.SepIsIn:= False;
    SetLength(ARec.DeclLines, 1);
    ARec.DeclLines[0]:= ATokens[ni].Text + ': ' + ty + '; // YADF Delphi10: inferred loop type, verify';
    SetLength(ARec.Names, 1);
    ARec.Names[0]:= ATokens[ni].Text;
    ARec.TypeStr:= ty;
    Result:= True;
  end; // function

// Literal-only type inference over an expression token span. Returns '' when
// the type cannot be safely determined (-> fallback). Deliberately conservative:
// no typecast inference (Ident(expr) is indistinguishable from a function call).
  function InferLiteralType(AFrom, ATo: Integer): string;
  var
    S     : Integer;
    e     : Integer;
    j     : Integer;
    dotIdx: Integer;
  begin
    Result:= '';
    S:= NextSig(AFrom);
    e:= ATo;
    while (e >= S) and (ATokens[e].Kind in [ptSpace, ptCRLF, ptCRLFCo]) do
      Dec(e);
    if (S > e) or (S >= ATokens.Count) then
      Exit;
    if S = e then
    begin
      case ATokens[S].Kind of
        ptIntegerConst                : Exit('Integer') ;
        ptFloat                       : Exit('Extended');
        ptStringConst, ptStringDQConst: Exit('string')  ;
      end;
      if SameText(ATokens[S].Text, 'True') or SameText(ATokens[S].Text, 'False') then
        Exit('Boolean');
      Exit;
    end;
    // Constructor call: <type-chain> . Create [ ( ... ) ] -> the type chain.
    for j:= S to e do
      if (ATokens[j].Kind = ptIdentifier) and SameText(ATokens[j].Text, 'Create') then
      begin
        dotIdx:= PrevSig(j - 1);
        if (dotIdx >= S) and (ATokens[dotIdx].Kind = ptPoint) then
        begin
          Result:= Trim(InlineRenderRange(ATokens, S, dotIdx - 1));
          if Result <> '' then
            Exit;
        end;
      end;
  end; // function

// `var Name := Expr;` with no explicit type -- infer from a literal initializer.
// Reuses the explicit-init rewrite (Name := Expr) but annotates the hoisted
// declaration with a verify comment quoting the original line.
  function TryParseInferred(AVar: Integer; out ARec: TInlineRec): Boolean;
  var
    ni      : Integer;
    ao      : Integer;
    semi    : Integer;
    dummy   : Integer;
    ty      : string ;
    origLine: string ;
  begin
    Result:= False;
    ni:= NextSig(AVar + 1);
    if (ni >= ATokens.Count) or (ATokens[ni].Kind <> ptIdentifier) then
      Exit;
    ao:= NextSig(ni + 1);
    if (ao >= ATokens.Count) or (ATokens[ao].Kind <> ptAssign) then
      Exit;
    semi:= FindStmtEnd(ao + 1, dummy);
    if semi < 0 then
      Exit;
    origLine:= Trim(InlineRenderRange(ATokens, AVar, semi));
    ARec.NameIdx  := ni;
    ARec.AssignIdx:= ao;
    ARec.SemiIdx  := semi;
    ARec.Sep:= -1;
    ARec.SepIsIn:= False;
    ty:= InferLiteralType(ao + 1, semi - 1);
    if ty <> '' then
    begin
      ARec.Kind:= ikExplicitInit;
      SetLength(ARec.DeclLines, 1);
      ARec.DeclLines[0]:= ATokens[ni].Text + ': ' + ty + '; // YADF Delphi10: inferred type, verify -- was: ' + origLine;
      SetLength(ARec.Names, 1);
      ARec.Names[0]:= ATokens[ni].Text;
      ARec.TypeStr:= ty;
    end
    else
    begin
      // Not inferable: leave the inline var in place + a TODO marker -- unless it
      // was already flagged on a previous run (keeps the pass idempotent).
      if AlreadyFlagged(semi) then
        Exit;
      ARec.Kind:= ikFallbackTodo;
      SetLength(ARec.DeclLines, 0);
      SetLength(ARec.Names    , 0);
      ARec.TypeStr:= '';
      ARec.Comment:= ' // TODO -oYADF : add an explicit type to hoist for Delphi 10 -- was: ' + origLine;
    end;
    Result:= True;
  end; // function

// Record an inline-var action, applying the per-routine name-collision guard:
// a name already hoisted with the SAME type drops its duplicate declaration; a
// name hoisted with a DIFFERENT type converts a statement var to a leave-in-place
// TODO (we will not silently shadow/retype). ABeginIdx = routine begin index,
// AVarIdx = the inline `var` token index (the Inlines key).
  procedure CommitInline(ABeginIdx, AVarIdx: Integer; var ARec: TInlineRec);
  var
    M       : Integer       ;
    collide : Boolean       ;
    keep    : TArray<string>;
    nm      : string        ;
    origLine: string        ;
    cname   : string        ;
  begin
    collide:= False;
    SetLength(keep, 0);
    for M:= 0 to High(ARec.Names) do
    begin
      nm:= ARec.Names[M];
      if RNames.ContainsKey(nm) then
      begin
        if not SameText(RNames[nm], ARec.TypeStr) then
          collide:= True;
        // same-type duplicate: omit the second declaration, keep the assignment
      end
      else
      begin
        RNames.Add(nm, ARec.TypeStr);
        SetLength(keep, Length(keep) + 1);
        keep[High(keep)]:= ARec.DeclLines[M];
      end;
    end; // for
    if collide and (ARec.Kind in [ikExplicitInit, ikExplicitNoInit]) then
    begin
      origLine:= Trim(InlineRenderRange(ATokens, AVarIdx, ARec.SemiIdx));
      cname:= '';
      for M:= 0 to High(ARec.Names) do
        if RNames.ContainsKey(ARec.Names[M]) and not SameText(RNames[ARec.Names[M]], ARec.TypeStr) then
        begin cname:= ARec.Names[M]; Break; end;
      ARec.Kind:= ikFallbackTodo;
      ARec.Comment:= ' // TODO -oYADF : name ''' + cname + ''' already hoisted with a different type; resolve manually for Delphi 10 -- was: ' + origLine;
      Inlines.Add(AVarIdx, ARec);
      Exit;
    end; // if
    Inlines.Add(AVarIdx, ARec);
    for M:= 0 to High(keep) do
      EnsureBodyDecls(ABeginIdx).Add(keep[M]);
  end; // procedure

// An inline var inside an anonymous method body: we will not hoist it (its
// scope is the anon method, not the enclosing routine). Leave it in place +
// a TODO. Statement vars only; for-vars/already-flagged are left untouched.
  function TryAnonFallback(AVar: Integer; out ARec: TInlineRec): Boolean;
  var
    ni      : Integer;
    semi    : Integer;
    dummy   : Integer;
    origLine: string ;
  begin
    Result:= False;
    ni:= NextSig(AVar + 1);
    if (ni >= ATokens.Count) or (ATokens[ni].Kind <> ptIdentifier) then
      Exit;
    semi:= FindStmtEnd(AVar + 1, dummy);
    if semi < 0 then
      Exit;
    if AlreadyFlagged(semi) then
      Exit;
    origLine:= Trim(InlineRenderRange(ATokens, AVar, semi));
    ARec.Kind   := ikFallbackTodo;
    ARec.NameIdx:= ni;
    ARec.AssignIdx:= -1;
    ARec.SemiIdx:= semi;
    ARec.Sep:= -1;
    ARec.SepIsIn:= False;
    SetLength(ARec.DeclLines, 0);
    SetLength(ARec.Names    , 0);
    ARec.TypeStr:= '';
    ARec.Comment:= ' // TODO -oYADF : inline var inside an anonymous method is not auto-hoisted for Delphi 10 -- was: ' + origLine;
    Result:= True;
  end; // function

// Inline `const Name = expr;` / `const Name: Type = expr;` in a statement
// section (a 10.3+ feature). The whole declaration is constant, so it moves
// verbatim to a routine-level `const` section -- no inference needed. ARec is
// set to drop the inline line; ADecl returns the section text.
  function TryParseInlineConst(AConst: Integer; out ARec: TInlineRec; out ADecl: string): Boolean;
  var
    ni   : Integer;
    semi : Integer;
    dummy: Integer;
  begin
    Result:= False; ADecl:= '';
    ni:= NextSig(AConst + 1);
    if (ni >= ATokens.Count) or (ATokens[ni].Kind <> ptIdentifier) then
      Exit;
    semi:= FindStmtEnd(AConst + 1, dummy);
    if semi < 0 then
      Exit;
    ADecl:= Trim(InlineRenderRange(ATokens, ni, semi)); // 'Name = expr;' / 'Name: T = expr;'
    if ADecl = '' then
      Exit;
    ARec.Kind   := ikExplicitNoInit; // the rewrite drops the whole inline line
    ARec.NameIdx:= ni;
    ARec.AssignIdx:= -1;
    ARec.SemiIdx:= semi;
    ARec.Sep:= -1;
    ARec.SepIsIn:= False;
    SetLength(ARec.DeclLines, 0);
    SetLength(ARec.Names    , 0);
    ARec.TypeStr:= '';
    Result:= True;
  end; // function

// An inline `const` inside an anonymous method body: its scope is the anon
// method, not the enclosing routine, so we will not hoist it. Leave it in
// place with a TODO (reuses the ikFallbackTodo rewrite -- const has a `;`).
  function TryFlagAnonConst(AConst: Integer; out ARec: TInlineRec): Boolean;
  var
    ni      : Integer;
    semi    : Integer;
    dummy   : Integer;
    origLine: string ;
  begin
    Result:= False;
    ni:= NextSig(AConst + 1);
    if (ni >= ATokens.Count) or (ATokens[ni].Kind <> ptIdentifier) then
      Exit;
    semi:= FindStmtEnd(AConst + 1, dummy);
    if semi < 0 then
      Exit;
    if AlreadyFlagged(semi) then
      Exit;
    origLine:= Trim(InlineRenderRange(ATokens, AConst, semi));
    ARec.Kind   := ikFallbackTodo;
    ARec.NameIdx:= ni;
    ARec.AssignIdx:= -1;
    ARec.SemiIdx:= semi;
    ARec.Sep:= -1;
    ARec.SepIsIn:= False;
    SetLength(ARec.DeclLines, 0);
    SetLength(ARec.Names    , 0);
    ARec.TypeStr:= '';
    ARec.Comment:= ' // TODO -oYADF : inline const inside an anonymous method is not auto-hoisted for Delphi 10 -- was: ' + origLine;
    Result:= True;
  end; // function

begin
  Root:= ParseGroups(ATokens);
  Inlines:= TDictionary<Integer, TInlineRec>.Create;
  BodyDecls:= TObjectDictionary<Integer, TStringList>.Create([doOwnsValues]);
  BodyConst:= TObjectDictionary<Integer, TStringList>.Create([doOwnsValues]);
  ForTodos:= TDictionary<Integer, string>.Create;
  RNames:= TDictionary<string, string>.Create;
  BlkAnon:= TList<Boolean     >.Create;
  BlkKind:= TList<TptTokenKind>.Create;
  try
    // 1) Analyse. A routine body is a gkBlock opened by `begin` that is a direct
    //    child of Root (top-level proc/func/method bodies AND nested-routine
    //    bodies all sit at Root; statement blocks nest deeper). Scan each body's
    //    token range for inline `var` statements.
    for G in Root.Children do
    begin
      if (G.Kind <> gkBlock) or (G.OpenerKind <> ptBegin) then
        Continue;
      if G.CloseIdx <= G.OpenIdx then
        Continue;
      RNames.Clear; // names are scoped per routine
      BlkAnon.Clear;
      BlkKind.Clear;
      AnonCount  := 0;
      PendingAnon:= False;
      i:= G.OpenIdx + 1;
      while i < G.CloseIdx do
      begin
        Ki:= ATokens[i].Kind;
        // A procedure/function keyword inside a body opens an anonymous method
        // (named nested routines live in the decl section, before `begin`).
        if Ki in [ptProcedure, ptFunction] then
        begin PendingAnon:= True; Inc(i); Continue; end;
        if Ki in [ptBegin, ptRecord, ptCase, ptTry, ptAsm, ptObject] then
        begin
          // `of object` (method-pointer type in an inline var) is a modifier,
          // not a block opener -- same exclusion ParseGroups applies. Without
          // it, `var P: procedure of object;` would push a dangling entry
          // that both mis-pairs the next `end` and makes the variant-part
          // guard below swallow a genuine `case` statement.
          if Ki = ptObject then
          begin
            pv:= PrevSig(i - 1);
            if (pv >= 0) and (ATokens[pv].Kind = ptOf) then
            begin Inc(i); Continue; end;
          end;
          // Variant-part `case` inside a local record/object declaration
          // shares the record's end -- pushing an entry for it would leave the
          // record's entry dangling and skew the anon accounting for the rest
          // of the body (same rule as ReindentByDepth / ParseGroups).
          if (Ki = ptCase) and (BlkKind.Count > 0) and (BlkKind[BlkKind.Count - 1] in [ptRecord, ptObject]) then
          begin Inc(i); Continue; end;
          IsAnon:= PendingAnon and (Ki = ptBegin);
          BlkAnon.Add(IsAnon);
          BlkKind.Add(Ki    );
          if IsAnon then
            Inc(AnonCount);
          PendingAnon:= False;
          Inc(i); Continue;
        end; // if
        if Ki = ptEnd then
        begin
          if BlkAnon.Count > 0 then
          begin
            if BlkAnon[BlkAnon.Count - 1] then
              Dec(AnonCount);
            BlkAnon.Delete(BlkAnon.Count - 1);
            BlkKind.Delete(BlkKind.Count - 1);
          end;
          Inc(i); Continue;
        end;
        if Ki = ptVar then
        begin
          // A `var` in an anon method's own decl section (seen before its begin)
          // is a classic var section, not an inline var -- leave it.
          if PendingAnon then begin Inc(i); Continue; end;
          pv:= PrevSig(i - 1);
          if AnonCount > 0 then
          begin
            if ((pv < 0) or (ATokens[pv].Kind <> ptFor)) and TryAnonFallback(i, Rec) then
            begin
              Inlines.Add(i, Rec);
              i:= Rec.SemiIdx + 1;
              Continue;
            end;
          end
          else if (pv >= 0) and (ATokens[pv].Kind = ptFor) then
          begin
            if TryParseForExplicit(i, Rec) or TryParseForInferred(i, Rec) then
            begin CommitInline(G.OpenIdx, i, Rec); i:= Rec.Sep + 1; Continue; end;
            // Non-inferable inline loop var (e.g. `for var X in Coll`): can't
            // downgrade without the element/bound type. Flag a TODO before the
            // `for`. Idempotent: skip if the line above is already a YADF flag.
            if not ForTodos.ContainsKey(pv) then
            begin
              k:= PrevSig(pv - 1);
              if not ((k >= 0) and (ATokens[k].Kind = ptSlashesComment) and (Pos('YADF', ATokens[k].Text) > 0)) then
                ForTodos.Add(pv, '// TODO -oYADF : inline loop var cannot be type-inferred for Delphi 10 -- declare a classic var and use a plain for');
            end;
          end // if
          else if TryParseExplicit(i, Rec) or TryParseInferred(i, Rec) then
          begin CommitInline(G.OpenIdx, i, Rec); i:= Rec.SemiIdx + 1; Continue; end;
        end; // if
        if Ki = ptConst then
        begin
          // A `const` in an anon method's own decl section (before its begin) is
          // a classic const section -- leave it. Otherwise, an inline const in
          // THIS routine's statement section (AnonCount = 0) hoists to a const
          // block; one inside a nested anon body has a different scope, so it is
          // left untouched.
          if PendingAnon then begin Inc(i); Continue; end;
          if AnonCount = 0 then
          begin
            if TryParseInlineConst(i, Rec, constDecl) then
            begin
              Inlines.Add(i, Rec);
              EnsureBodyConst(G.OpenIdx).Add(constDecl);
              i:= Rec.SemiIdx + 1;
              Continue;
            end;
          end
          else if TryFlagAnonConst(i, Rec) then
          begin Inlines.Add(i, Rec); i:= Rec.SemiIdx + 1; Continue; end;
        end; // if
        Inc(i);
      end; // while
    end; // for

    if (Inlines.Count = 0) and (ForTodos.Count = 0) then
      Exit;

    // 2) Rebuild the token list in one forward pass.
    Outp:= TTokenList.Create;
    try
      i:= 0;
      while i < ATokens.Count do
      begin
        // Prepend a TODO line before a flagged non-inferable inline for-var.
        // Emit the comment + an explicit CRLF so the `for` drops to the next
        // line (whitespace is tokenised here, so Pre alone won't break the
        // line); the re-indent pass fixes the exact columns afterwards.
        if ForTodos.TryGetValue(i, todoText) then
        begin
          flagTok:= MakeTok(ptSlashesComment, todoText);
          Outp.Add(flagTok);
          Outp.Add(MakeTok(ptCRLF, CRLF));
        end;
        // Inject the hoisted `const` then `var` block immediately before a
        // routine's `begin` (const first so it can be referenced by the vars).
        if BodyConst.ContainsKey(i) then
        begin
          Outp.Add(MakeTok(ptConst, 'const'));
          Outp.Add(MakeTok(ptCRLF , CRLF   ));
          for k:= 0 to BodyConst[i].Count - 1 do
          begin
            Outp.Add(MakeTok(ptIdentifier, BodyConst[i][k]));
            Outp.Add(MakeTok(ptCRLF, CRLF));
          end;
        end;
        if BodyDecls.ContainsKey(i) then
        begin
          Outp.Add(MakeTok(ptVar , 'var'));
          Outp.Add(MakeTok(ptCRLF, CRLF ));
          for k:= 0 to BodyDecls[i].Count - 1 do
          begin
            Outp.Add(MakeTok(ptIdentifier, BodyDecls[i][k]));
            Outp.Add(MakeTok(ptCRLF, CRLF));
          end;
        end;

        if Inlines.TryGetValue(i, Rec) then
        begin
          case Rec.Kind of
            ikExplicitInit:
            begin
              Outp.Add(ATokens[Rec.NameIdx]); // Name
              if not AOpts.AssignNoSpaceBefore then
                Outp.Add(MakeTok(ptSpace, ' '));
              for k:= Rec.AssignIdx to Rec.SemiIdx do
                Outp.Add(ATokens[k]); // := Expr ;
              i:= Rec.SemiIdx + 1;
            end;
            ikExplicitNoInit: // drop the whole line
            begin
              i:= Rec.SemiIdx + 1;
              if (i < ATokens.Count) and (ATokens[i].Kind in [ptCRLF, ptCRLFCo]) then
                Inc(i);
            end;
            ikForExplicit:
            begin
              Outp.Add(ATokens[Rec.NameIdx]); // for Name
              if Rec.SepIsIn or (not AOpts.AssignNoSpaceBefore) then
                Outp.Add(MakeTok(ptSpace, ' '));
              i:= Rec.Sep; // resume at := / in
            end;
            ikFallbackTodo: // leave in place + TODO
            begin
              for k:= i to Rec.SemiIdx do
                Outp.Add(ATokens[k]);
              Outp.Add(MakeTok(ptSlashesComment, Rec.Comment));
              i:= Rec.SemiIdx + 1;
            end;
          end; // case
          Continue;
        end; // if

        Outp.Add(ATokens[i]);
        Inc(i);
      end; // while

      ATokens.Clear;
      ATokens.AddRange(Outp);
    finally
      Outp.Free;
    end; // try
  finally
    Inlines.Free;
    BodyDecls.Free;
    BodyConst.Free;
    ForTodos.Free;
    RNames.Free;
    BlkAnon.Free;
    BlkKind.Free;
    Root.Free;
  end; // try
end; // procedure

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
function FormatSource(const ASource: string; const AOpts: TYadfOptions; out ADeclineReason: string): string;
var
  CurCol      : Integer       ;
  CurLine     : Integer       ;
  Cursor      : Integer       ;
  PendingLabel: string        ;
  Root        : TGroup        ;
  Sb          : TStringBuilder;
  Tokens      : TTokenList    ;
  MLMap       : TStringList   ;
  EffMaxBlanks: Integer       ; // hoisted from inline var in the pipeline (XE8/D10)

  // Updates CurCol/CurLine after every text emission. Tabs are
  // counted as TabWidth columns; CR is ignored (column reset happens
  // on LF). Plain ASCII characters all count as one column -- we
  // don't try to handle ambiguous-width Unicode here because the
  // input is Pascal source.
  procedure UpdateColumn(const S: string);
  var
    i: Integer;
  begin
    for i:= 1 to Length(S) do if S[i] = LF then
    begin
      CurCol:= 0;
      Inc(CurLine);
    end
    else if S[i] = #9 then
      Inc(CurCol, AOpts.TabWidth)
    else if S[i] <> CR then
      Inc(CurCol);
  end; // procedure

// Appends S to the output StringBuilder, flushing any PendingLabel
// first. If S contains a line break, the label is spliced in BEFORE
// the break -- e.g. `end;` + pending `// while` + `\r\n` becomes
// `end; // while\r\n`. CurCol/CurLine are kept in sync via
// UpdateColumn so subsequent walker decisions remain accurate.
  procedure EmitText(const S: string);
  var
    i   : Integer;
    k   : Integer;
    Pre : string ;
    Lbl : string ;
    Post: string ;
  begin
    if PendingLabel <> '' then
    begin
      k:= 0;
      for i:= 1 to Length(S) do if (S[i] = CR) or (S[i] = LF) then
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
      end; // if
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
      EmitText(Tokens[j].Pre );
      EmitText(Tokens[j].Text);
    end;
  end;

  function ParensContentInlineWidth(G: TGroup): Integer;
  begin
    Result:= Length(InlineRenderRange(Tokens, G.OpenIdx + 1, G.CloseIdx - 1));
  end;

  function CurrentLineLeadingWS: string;
  var
    S        : string ;
    i        : Integer;
    LineStart: Integer;
  begin
    S:= Sb.ToString;
    LineStart:= 1;
    for i:= Length(S) downto 1 do if (S[i] = LF) or (S[i] = CR) then
    begin
      LineStart:= i + 1;
      Break;
    end;
    Result:= '';
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
    LineWS  : string            ;
    Indent  : string            ;
    Inner   : string            ;
    i       : Integer           ;
    SubGroup: TGroup            ;
  begin
    Items:= CollectParensItems(Tokens, G.OpenIdx, G.CloseIdx);
    LineWS:= CurrentLineLeadingWS;
    Indent:= LineWS + StringOfChar(' ', AOpts.Indent * 2);
    EmitText(Tokens[G.OpenIdx].Text);
    for i:= 0 to High(Items) do
    begin
      EmitText(CRLF  );
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
      end; // else
      if i < High(Items) then
        EmitText(',');
      if Items[i].CmtFirst >= 0 then
      begin
        EmitText(' ');
        EmitText(Trim(InlineRenderRange(Tokens, Items[i].CmtFirst, Items[i].CmtLast)));
      end;
    end; // for
    EmitText(CRLF  );
    EmitText(LineWS);
    EmitText(Tokens[G.CloseIdx].Text);
  end; // procedure

  function BlockAlreadyLabeled(G: TGroup): Boolean;
  var
    EndLine: Integer;
    k      : Integer;
  begin
    EndLine:= Tokens[G.CloseIdx].Line;
    k:= G.CloseIdx + 1;
    while (k < Tokens.Count) and (Tokens[k].Line = EndLine) do
    begin
      if Tokens[k].Kind = ptSlashesComment then
        Exit(True);
      Inc   (k   );
    end;
    Result:= False;
  end; // function

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
    Child     : TGroup ;
    GroupEnd  : Integer;
    InlineW   : Integer;
    Marker    : string ;
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
          EmitText(CRLF + Marker);
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
    Positions: TList<Integer>;
    i        : Integer       ;
    St       : TLineScanState;
    Done     : Boolean       ;
    procedure AddIfWord(Idx, Wlen: Integer; const W: string);
    begin
      if (Idx + Wlen - 1 > Length(Line)) then
        Exit;
      if not SameText(Copy(Line, Idx, Wlen), W) then
        Exit;
      if (Idx > 1) and IsAlphaNum(Line[Idx - 1]) then
        Exit;
      if (Idx + Wlen <= Length(Line)) and IsAlphaNum(Line[Idx + Wlen]) then
        Exit;
      Positions.Add(Idx);
    end;
  begin
    Positions:= TList<Integer>.Create;
    try
      St.Reset;
      Done:= False;
      i   := 1;
      while not Done do
      case St.SkipNonCode(Line, i) of
        seEndOfLine, seLineComment: Done:= True;
        seCode                    :
        begin
          if CharInSet(Line[i], ['(', '[', ')', ']']) then
          begin
            St.StepCode(Line, i);
            Continue;
          end;
          if (i > 1) and (Line[i - 1] = ' ') then
          begin
            if CharInSet(Line[i], ['+', '-']) and (i + 1 <= Length(Line)) and (Line[i + 1] = ' ') then
            begin
              Positions.Add(i);
              Inc(i);
              Continue;
            end;
            AddIfWord(i, 2, 'or' );
            AddIfWord(i, 3, 'and');
            AddIfWord(i, 3, 'xor');
          end; // if
          if (Line[i] = ',') and (St.Depth > 0) and (i + 1 <= Length(Line)) and (Line[i + 1] = ' ') then
          begin
            Positions.Add(i + 2);
            Inc(i);
            Continue;
          end;
          Inc(i);
        end; // case
      end; // case
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
    while (i <= Length(Line)) and ((Line[i] = ' ') or (Line[i] = #9)) do
      Inc(i);
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
    BestIdx   : Integer        ;
    Indent    : string         ;
    NewIndent : string         ;
    CurLine   : string         ;
    Out_      : TStringBuilder ;
    p         : Integer        ;
    MinBreakAt: Integer        ;
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
        Out_.Append(CRLF);
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
    Lines : TStringList    ;
    i     : Integer        ;
    Locked: TArray<Boolean>;
  begin
    Lines:= TStringList.Create;
    try
      Lines.LineBreak:= CRLF;
      Lines.Text     := ASrc;
      Locked:= ComputeBlockCommentLock(Lines);
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
  ADeclineReason:= '';
  Tokens:= LoadTokensFromString(ASource);
  MLMap:= TStringList.Create;
  try
    // Stage 1: token-level passes (mutate Tokens in place).
    ApplyCapitalization   (Tokens, AOpts);
    NormalizeAssignSpacing(Tokens, AOpts);
    if AOpts.SpaceAroundOperators then
      NormalizeOperatorSpacing(Tokens, AOpts);
    // Delphi 10 compatibility transform (opt-in): hoist inline vars. Runs before
    // ParseGroups so it can mutate the token list freely.
    if AOpts.Delphi10Compat then
      DowngradeInlineVars(Tokens, AOpts);
    // Shield multi-line string-literal tokens before structure/emission so
    // every later pass sees a one-line atom; restored verbatim at Stage 5.
    ShieldMultilineTokens(Tokens, MLMap);
    Root:= ParseGroups(Tokens);
    try
      Sb:= TStringBuilder.Create;
      try
        // Stage 2: structural emission. WalkGroup writes into Sb.
        Cursor      := 0;
        CurCol      := 0;
        CurLine     := 1;
        PendingLabel:= '';
        WalkGroup(Root);
        // A trailing PendingLabel (block-end label on the last block
        // of the file) needs an explicit CRLF to flush.
        if PendingLabel <> '' then
        begin
          EmitText(CRLF);
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
        Result:= ReindentByDepth (Result, AOpts.Indent, AOpts.IndentComments);
        Result:= EnforceBlankLines(Result, AOpts);
        Result:= BreakLongLines(Result);
        if AOpts.ReflowLines then
        begin
          Result:= ReflowLineBreaks(Result, AOpts.MaxLen, AOpts.PackShortBodies);
          Result:= ReindentByDepth (Result, AOpts.Indent, AOpts.IndentComments );
        end
        else
        begin
          // Case-arm joining is part of body-packing: only pull a short arm
          // onto its `label:` line when PackShortBodies is on. Default leaves
          // each arm body on its own line.
          if AOpts.PackShortBodies then
            Result:= JoinShortCaseAlts(Result, AOpts.MaxLen);
          // JoinShortCaseAlts may pull a `label:` onto its body line; re-indent
          // so the merged line's body depth is recomputed for the new shape
          // (otherwise a case arm whose body is a nested `if` keeps the depth
          // computed for the un-merged form -- a non-idempotency). Mirrors the
          // reflow path, which already re-indents after ReflowLineBreaks.
          Result:= ReindentByDepth(Result, AOpts.Indent, AOpts.IndentComments);
        end; // else
        // Break single-line control-statement bodies onto their own line when
        // any Break* flag is on. Runs after the reflow/pack block (so it acts on
        // the settled line shape and wins over PackShortBodies) and before the
        // Stage-4 alignment passes (splitting changes line adjacency). Re-indent
        // so the freed body gets its structural +1 depth.
        if AOpts.BreakLoopBody or AOpts.BreakWithBody or AOpts.BreakIfBody then
        begin
          Result:= BreakControlBodies(Result, AOpts);
          Result:= ReindentByDepth(Result, AOpts.Indent, AOpts.IndentComments);
        end;
        // Join routine headers the source split across lines back onto one line.
        // Always-on standard behavior (no option). Runs after BreakControlBodies (acts
        // on the settled line shape) and before Stage-4 alignment. Content-neutral, so
        // no re-indent is needed: the header keeps the start line's (already-correct)
        // indent and its own continuation indent.
        Result:= JoinRoutineHeaders(Result, AOpts);
        EffMaxBlanks:= AOpts.MaxBlankLines;
        if AOpts.BlanksBeforeSection > EffMaxBlanks then
          EffMaxBlanks:= AOpts.BlanksBeforeSection;
        if AOpts.BlanksBeforeMethod > EffMaxBlanks then
          EffMaxBlanks:= AOpts.BlanksBeforeMethod;
        if AOpts.BlanksBeforeType > EffMaxBlanks then
          EffMaxBlanks:= AOpts.BlanksBeforeType;
        Result:= CollapseBlankLines(Result, EffMaxBlanks);

        // Stage 4: column alignment (Pass 2). CollapseInteriorSpaces
        // normalises spacing so anchor columns are predictable.
        // SplitMultiVarDecls runs first so the alignment sees one
        // declaration per line.
        if AOpts.SplitMultiVarDecls or AOpts.BreakCaseLabels then
          Result:= SplitMultiVarDeclarations(Result, AOpts.SplitMultiVarDecls, AOpts.BreakCaseLabels);
        if AOpts.AlignTypeColon or AOpts.AlignConstEquals or AOpts.AlignSmartAssign then
          Result:= CollapseInteriorSpaces(Result);
        if AOpts.AlignTypeColon then
          Result:= AlignByAnchor(Result, ':', AOpts.AlignMaxColumn);
        if AOpts.AlignDeclSemicolons then
          Result:= AlignDeclarationSemicolons(Result, AOpts.AlignMaxColumn);
        if AOpts.AlignConstEquals then
          Result:= AlignByAnchor(Result, '=', AOpts.AlignMaxColumn);
        if AOpts.AlignSmartAssign then
          Result:= SmartAlignAssignments(Result, AOpts.AlignMaxColumn, AOpts.AlignMatchingShapes, AOpts.AlignShapeMinAnchors, AOpts.AlignCommentMaxShift);

        // Final pass: fold a short control-statement begin..end body onto one
        // line. Runs after alignment (so it never feeds joined lines back
        // through the column passes) but before unshield (so multi-line string
        // sentinels are still single-line and can be detected + skipped).
        if AOpts.CollapseShortBlocks then
          Result:= CollapseShortBlocks(Result, AOpts.MaxLen);

        // Stage 5: restore shielded multi-line strings and block comments verbatim.
        Result:= UnshieldMultilineTokens(Result, MLMap);

        // Stage 6: content-preservation safety net (see YADF.Guard). If any
        // user content -- a string literal, a comment, a compiler directive --
        // was dropped or altered by the passes above, DECLINE to format and
        // return the input unchanged, reporting WHY via ADeclineReason. This
        // converts any future corruption bug in the line passes into a
        // harmless (and now visible) "file left as-is" instead of a shipped
        // source-mangling edit. BreakCaseLabels legitimately duplicates arm
        // bodies, so string duplication is tolerated exactly when it is on.
        if not FormatPreservesContent(ASource, Result, AOpts.BreakCaseLabels, ADeclineReason) then
          Result:= ASource;
      finally
        Sb.Free;
      end; // try
    finally
      Root.Free;
    end; // try
  finally
    Tokens.Free;
    MLMap.Free;
  end; // try
end; // begin

function FormatSource(const ASource: string; const AOpts: TYadfOptions): string;
var
  Reason: string;
begin
  Result:= FormatSource(ASource, AOpts, Reason);
end;

end.


