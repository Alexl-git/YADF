{
  YADF -- Yet Another Delphi Formatter

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  Post-format safety net. FormatSource's line passes re-derive lexical
  facts from raw strings, and historically every shipped corruption bug
  (dropped $I include directives, comment merge/loss, multiline-string
  interior damage) was a failure of exactly that re-derivation. This unit re-lexes
  the formatter's OUTPUT and verifies that all user CONTENT survived:

    * string literals  -- byte-exact, same order, same count;
    * comments         -- text-exact (modulo trailing spaces / newline
                          style), same order; the formatter may ADD
                          comments (block labels, --d10 TODO flags) but
                          never drop or alter one;
    * compiler directives -- same order and count, compared with case and
                          whitespace normalized (UpperDirectives and the
                          ifdef-spacing pass legitimately touch those).

    * code tokens      -- (extended overload only, see TGuardCodeMode) the
                          lowercased stream of every token that is not
                          layout/comment/directive/literal/asm body must be
                          identical (gcStrict), or -- for the passes that
                          legitimately re-spell declarations
                          (SplitMultiVarDeclarations, BreakCaseLabels,
                          DowngradeInlineVars) -- a bounded transformation of
                          it (gcSplit / gcD10).
}

unit YADF.Guard;   // dl:shared YADF, YADFOT, YADFSetup

interface

const
  /// <summary>Start of every `//` TODO the --d10 path (Delphi10Compat) inserts:
  /// `// TODO -oYADF -cd10 : ...` (owner decision 2026-11-02, task 11).</summary>
  /// <remarks>YADF owns these flags: a run without --d10 removes exactly the comments
  /// that start with this text, and FormatPreservesContent ignores them on the
  /// original side, so that removal -- and no other comment loss -- passes.</remarks>
  D10_TODO_MARKER = '// TODO -oYADF -cd10 :';

/// <summary>Verifies that AFormatted preserves all user content of AOriginal:
/// every string literal byte-exact and in order, every comment present
/// unaltered and in order (formatter-added comments are allowed), and every
/// compiler directive present in order (case/whitespace-insensitive).</summary>
/// <param name="AOriginal">Source text before formatting.</param>
/// <param name="AFormatted">Candidate formatter output to validate.</param>
/// <returns>True when the content is fully preserved; False when anything was
/// dropped or altered -- the caller should then discard AFormatted and keep
/// AOriginal (decline to format rather than corrupt).</returns>
/// <remarks>
/// Pure and thread-safe; lexes both inputs once. If lexing the inputs
/// raises, the guard fails CLOSED (returns False).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: YADF.Guard.FormatPreservesContent/5</para>
/// <para>Returns: FormatPreservesContent(AOriginal, AFormatted, False, False, Reason)</para>
/// <para>Overload 1 of 4</para>
/// <para>Directives: overload</para>
/// <seealso cref="YADF.Guard.FormatPreservesContent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string): Boolean; overload;

type
  /// <summary>How strictly the guard compares the CODE-token stream: every token
  /// that is not whitespace or a comment, compared case-insensitively, with each
  /// compiler directive and each string/char literal kept as a POSITION marker
  /// (their text is compared by the directive / string streams). Asm bodies are
  /// covered by the asm-line stream; `asm` and its `end` stay in this one.</summary>
  /// <remarks>
  /// gcNone: code tokens are not compared (historic behaviour of the 2- and
  /// 5-argument overloads). gcStrict: the sequences must be identical -- any
  /// reordered, lost or duplicated token, or code moved across a directive,
  /// declines. gcSplit: SplitMultiVarDecls / BreakCaseLabels /
  /// BreakParamsOnePerLine legitimately re-spell `A, B: T` as `A: T; B: T` (and a
  /// parameter `const A, B: T` as `const A: T; const B: T`); BOTH streams are put
  /// in that expanded canonical form first and must then be identical -- the
  /// expected transform, not a relaxation. gcD10: the Delphi10Compat hoist moves
  /// `name: Type` out of the statements (deduplicating a same-type redeclaration);
  /// per conditional-compilation branch, every original token outside a
  /// declaration (ignoring commas, semicolons, var/const and the names a `var`
  /// declares) must occur in the output at least as often, and every `: Type`
  /// annotation must still occur in the SAME branch -- a declaration hoisted out
  /// of its {$IFDEF} declines. Order: with the declarations taken out, the source
  /// code stream must be a subsequence of the output's (task 10) -- the hoist adds
  /// declarations but never reorders code.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [YADF]declaration (YADF.Guard.pas), [YADF]YADF.Guard.CodeStreamReason (YADF.Guard.pas), [YADF]YADF.Guard.FormatPreservesContent/6 (YADF.Guard.pas), [YADF]YADF.Guard.FormatPreservesContent/7 (YADF.Guard.pas), [YADF]YADF.Layout.FormatSourceOnce (YADF.Layout.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGuardCodeMode = (gcNone, gcStrict, gcSplit, gcD10);

  /// <summary>One re-casing of a code token that the active options license.</summary>
  /// <remarks>
  /// gkKeywordsLower: a reserved word may become all-lowercase (LowercaseKeywords).
  /// gkFirstOccurrence: an identifier may take the spelling of its FIRST occurrence
  /// in the original (FirstOccCasing) -- except where the spelling reaches the binary
  /// (YADF.Tokens.SpellingSensitiveIdents: enum members, `external` names), which
  /// must stay exactly as written. gkUpperHex: a numeric literal may change case
  /// (UpperHexNumbers). gkAnyCase: no casing check at all (the historic
  /// lowercase-only comparison of the overloads without ACasing).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (YADF.Guard.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGuardCasingRule = (gkKeywordsLower, gkFirstOccurrence, gkUpperHex, gkAnyCase);

  /// <summary>The set of re-casings the guard accepts; [] = every code token must
  /// keep its exact spelling.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (YADF.Guard.pas), YADF.Guard.CasingReasonByPosition (YADF.Guard.pas), YADF.Guard.CasingReasonUnordered (YADF.Guard.pas), YADF.Guard.CodeStreamReason (YADF.Guard.pas), YADF.Guard.FormatPreservesContent/7 (YADF.Guard.pas), YADF.Layout.FormatSourceOnce (YADF.Layout.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGuardCasing = set of TGuardCasingRule;

/// <summary>As the 5-argument overload, plus the code-token comparison selected
/// by ACodeMode (see TGuardCodeMode).</summary>
/// <param name="AOriginal">Source text before formatting.</param>
/// <param name="AFormatted">Candidate formatter output to validate.</param>
/// <param name="AAllowStringDuplication">True when statements may be duplicated.</param>
/// <param name="AAllowLabelRemoval">True when stale block-end markers may be removed.</param>
/// <param name="ACodeMode">Strictness of the code-token comparison.</param>
/// <param name="AReason">'' when preserved; otherwise the decline cause.</param>
/// <returns>True when the content is fully preserved.</returns>
/// <remarks>
/// Same purity/fail-closed contract as the other overloads.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: [YADF]YADF.Guard.FormatPreservesContent/5 (YADF.Guard.pas)</para>
/// <para>Calls: YADF.Guard.FormatPreservesContent/7</para>
/// <para>Returns: FormatPreservesContent(AOriginal, AFormatted, AAllowStringDuplication, AAllowLabelRemoval, ACodeMode, [gkAnyCase], AReason)</para>
/// <para>Overload 2 of 4</para>
/// <para>Directives: overload</para>
/// <seealso cref="YADF.Guard.FormatPreservesContent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; ACodeMode: TGuardCodeMode; out AReason: string): Boolean; overload;

/// <summary>As the ACodeMode overload, plus the exact SPELLING of every code token:
/// a token may differ from the original only by a re-casing listed in ACasing
/// (see TGuardCasingRule). This is the check FormatSource runs.</summary>
/// <param name="AOriginal">Source text before formatting.</param>
/// <param name="AFormatted">Candidate formatter output to validate.</param>
/// <param name="AAllowStringDuplication">True when statements may be duplicated.</param>
/// <param name="AAllowLabelRemoval">True when stale block-end markers may be removed.</param>
/// <param name="ACodeMode">Strictness of the code-token comparison.</param>
/// <param name="ACasing">The re-casings the active options license.</param>
/// <param name="AReason">'' when preserved; otherwise the decline cause.</param>
/// <returns>True when the content is fully preserved.</returns>
/// <remarks>
/// Same purity/fail-closed contract as the other overloads. Under gcStrict and
/// gcSplit the spelling is checked position by position; under gcD10 (no order)
/// every output spelling must be one the original used for that name, and every
/// spelling-sensitive or (without gkFirstOccurrence) every identifier spelling
/// must occur in the output at least as often as in the original.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: YADF.Guard.FormatPreservesContent/6 (YADF.Guard.pas), YADF.Layout.FormatSourceOnce (YADF.Layout.pas)</para>
/// <para>Calls: YADF.Guard.CodeStreamReason, YADF.Guard.CountOccurrences, YADF.Guard.DropD10Todos, YADF.Guard.DropFlagged, YADF.Guard.ExtractContent, YADF.Guard.FirstUnmatched, YADF.Guard.IsSubsequence, YADF.Guard.SameSequence</para>
/// <para>Returns: False; AReason = ''</para>
/// <para>Overload 3 of 4</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Mutates: AReason (out)</para>
/// <para>Directives: overload</para>
/// <seealso cref="YADF.Guard.CodeStreamReason"/>
/// <seealso cref="YADF.Guard.CountOccurrences"/>
/// <seealso cref="YADF.Guard.DropD10Todos"/>
/// <seealso cref="YADF.Guard.DropFlagged"/>
/// <seealso cref="YADF.Guard.ExtractContent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; ACodeMode: TGuardCodeMode; ACasing: TGuardCasing;
  out AReason: string): Boolean; overload;

/// <summary>Extended check used by FormatSource. AAllowStringDuplication
/// relaxes the string comparison from exact-sequence to ordered-subsequence:
/// BreakCaseLabels legitimately DUPLICATES a case-arm body (one copy per
/// label), string literals included, so with that option on the original
/// string sequence need only survive IN ORDER inside the formatted one --
/// a lost or altered literal still fails. AReason receives '' on success or
/// a short human-readable cause on failure (which stream diverged + a
/// preview of the first unpreserved element), so callers can REPORT a
/// decline instead of silently returning the input.</summary>
/// <param name="AOriginal">Source text before formatting.</param>
/// <param name="AFormatted">Candidate formatter output to validate.</param>
/// <param name="AAllowStringDuplication">True when the active options may
/// legitimately duplicate statements (BreakCaseLabels).</param>
/// <param name="AAllowLabelRemoval">True when the active options may legitimately
/// DELETE a block-end marker (LabelLongBlocks). Deliberately minimal: comments that
/// are EXACTLY the marker this formatter would itself have written for the block
/// whose <c>end</c> they trail (YADF.Groups.CollectBlockLabelComments) are dropped
/// from BOTH streams before comparing, because that text is formatter-owned, not the
/// user's. Everything left over -- every other comment, plus all strings and
/// directives -- is checked exactly as strictly as with the flag off. A marker
/// naming a different construct, one without the space after <c>//</c>, one with
/// trailing prose, and a brace comment are all NOT markers and stay protected.</param>
/// <param name="AReason">'' when preserved; otherwise the decline cause.</param>
/// <returns>True when the content is fully preserved.</returns>
/// <remarks>
/// Same purity/fail-closed contract as the two-argument overload.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: [YADF]YADF.Guard.FormatPreservesContent/2 (YADF.Guard.pas)</para>
/// <para>Calls: YADF.Guard.FormatPreservesContent/6</para>
/// <para>Returns: FormatPreservesContent(AOriginal, AFormatted, AAllowStringDuplication, AAllowLabelRemoval, gcNone, AReason)</para>
/// <para>Overload 4 of 4</para>
/// <para>Directives: overload</para>
/// <seealso cref="YADF.Guard.FormatPreservesContent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; out AReason: string): Boolean; overload;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , SimpleParser.Lexer.Types
  , YADF.Groups
  , YADF.Tokens
  ;

// Number of non-overlapping occurrences of ASub in AText (case-sensitive).
function CountOccurrences(const ASub, AText: string): Integer;
var
  P: Integer;
begin
  Result:= 0;
  P:= Pos(ASub, AText);
  while P > 0 do
  begin
    Inc(Result);
    P:= PosEx(ASub, AText, P + Length(ASub));
  end;
end; // function

// Newline-style differences (LF-only input emitted as CRLF) are not content
// damage; fold every newline flavor to #10 before comparing.
function NormalizeNewlines(const S: string): string;
begin
  Result:= StringReplace(S     , #13#10, #10, [rfReplaceAll]);
  Result:= StringReplace(Result, #13   , #10, [rfReplaceAll]);
end;

// Directive comparison key: lowercase, every whitespace run collapsed to ONE
// space, and the padding just inside the delimiters (`{$ `, ` }`, `(*$ `,
// ` *)`) stripped. UpperDirectives rewrites `{$ifdef}` as `{$IFDEF}` and the
// ifdef-spacing normalization rewrites `{$IFDEF  x }` as `{$IFDEF x}`; neither
// is damage. Whitespace INSIDE the argument is kept as a single space (it used
// to be deleted outright, which made `{$I a b.inc}` equal `{$I ab.inc}` -- a
// different file name the guard could not see).
function DirectiveKey(const S: string): string;
var
  Sb     : TStringBuilder;
  C      : Char          ;
  PrevSp : Boolean       ;
begin
  Sb:= TStringBuilder.Create;
  try
    PrevSp:= False;
    for C in S do
      if C > ' ' then
      begin
        Sb.Append(C);
        PrevSp:= False;
      end
      else if not PrevSp then
      begin
        Sb.Append(' ');
        PrevSp:= True;
      end;
    Result:= LowerCase(Sb.ToString);
  finally
    Sb.Free;
  end;
  Result:= StringReplace(Result, '{$ ', '{$', []);
  Result:= StringReplace(Result, '(*$ ', '(*$', []);
  if Result.EndsWith('}') then
    Result:= TrimRight(Copy(Result, 1, Length(Result) - 1)) + '}'
  else if Result.EndsWith('*)') then
    Result:= TrimRight(Copy(Result, 1, Length(Result) - 2)) + '*)';
end; // function

const
  DirectiveKinds = [
    ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect, ptElseDirect, ptElseIfDirect, ptEndIfDirect, ptIfEndDirect, ptDefineDirect, ptUndefDirect, ptIncludeDirect,
    ptResourceDirect, ptCompDirect, ptScopedEnumsDirect];
  CommentKinds = [ptAnsiComment, ptBorComment, ptSlashesComment];
  // Not part of the code-token stream: layout, plus the literal kinds that the
  // string stream already compares byte-exact.
  CodeSkipKinds = [ptSpace, ptCRLF, ptCRLFCo, ptNull, ptAsciiChar];
  StringKinds  = [ptStringConst, ptStringDQConst];
  // Text the formatter's own shields insert and must remove again: the
  // include-directive suffix (YADF.Tokens.IncSentinel) and the multi-line /
  // asm placeholders (YADF.Layout `__YADF[k]_ML_n__`, `__YADF[k]_MLC_n__`, ... where the
  // layout picks k so the prefix is absent from the source). A leak is detected by COUNT
  // (more occurrences in the output than the input). Source text containing `ZQYADF` (the
  // include-shield word, fixed in YADF.Tokens) is a known, safe decline.
  SHIELD_MARKERS: array[0..1] of string = ('ZQYADF', '__YADF');
  // Code-stream keys of the position markers (never a real token's text).
  DIRECTIVE_KEY = '{$';
  STRING_KEY    = '''';
  CondOpenKinds  = [ptIfDirect, ptIfDefDirect, ptIfNDefDirect, ptIfOptDirect];
  CondElseKinds  = [ptElseDirect, ptElseIfDirect];
  CondCloseKinds = [ptEndIfDirect, ptIfEndDirect];

type
  TCodeClass = (ccOther, ccIdent, ccKeyword, ccNumber, ccDirective, ccString);

  // One entry of the code-token stream. Key is what order/identity compares
  // (lowercased text, or a marker); Text the exact spelling; Ctx the
  // conditional-compilation branch it sits in (`3/7` = inside the branch opened
  // or switched by directive #3, then #7); Sensitive = spelling reaches the
  // binary (original side only).
  TCodeTok = record
    Key      : string    ;
    Text     : string    ;
    Cls      : TCodeClass;
    Sensitive: Boolean   ;
    Ctx      : string    ;
  end;

  TCodeList = TList<TCodeTok>;

function IsAlphaWord(const S: string): Boolean;
var
  C: Char;
begin
  Result:= S <> '';
  for C in S do
    if not CharInSet(C, ['a'..'z', 'A'..'Z']) then
      Exit(False);
end;

function MakeCodeTok(const AKey, AText: string; ACls: TCodeClass; const ACtx: string): TCodeTok;
begin
  Result.Key      := AKey;
  Result.Text     := AText;
  Result.Cls      := ACls;
  Result.Sensitive:= False;
  Result.Ctx      := ACtx;
end;

// Appends T (a code token, not layout/comment/literal/directive) to ACode.
procedure AddCodeToken(const ACode: TCodeList; const T: TToken; ASensitive: Boolean; const ACtx: string);
var
  C  : TCodeTok  ;
  Cls: TCodeClass;
begin
  // Mirrors YADF.Layout.ApplyCapitalization: identifiers follow FirstOccCasing,
  // other all-letter tokens (reserved words) LowercaseKeywords.
  Cls:= if T.Kind = ptIdentifier then ccIdent else if T.Kind in [ptIntegerConst, ptFloat] then ccNumber else if IsAlphaWord(T.Text) then ccKeyword else ccOther;
  C:= MakeCodeTok(LowerCase(T.Text), T.Text, Cls, ACtx);
  C.Sensitive:= ASensitive;
  ACode.Add(C);
end;

// True when ATokens[AIdx] is a decimal number ending in an exponent marker
// (`1E`) glued to a sign and a number (`-9`): one real literal `1E-9`.
function IsSplitExponent(const ATokens: TTokenList; AIdx: Integer): Boolean;
var
  S: string;
begin
  Result:= False;
  if (AIdx + 2 >= ATokens.Count) or (ATokens[AIdx].Kind not in [ptIntegerConst, ptFloat]) then
    Exit;
  S:= ATokens[AIdx].Text;
  Result:= CharInSet(S[1], ['0'..'9']) and CharInSet(S[Length(S)], ['e', 'E']) and (ATokens[AIdx + 1].Kind in [ptMinus, ptPlus]) and (ATokens[AIdx + 2].Kind in [ptIntegerConst, ptFloat]);
end;

// Tracks the conditional-compilation branch across a directive token: an
// {$IF...} opens a branch, {$ELSE}/{$ELSEIF} switches it, {$ENDIF}/{$IFEND}
// closes it. AOrd is the directive's ordinal, identical on both sides because
// the directive stream must match exactly.
procedure StepCondContext(const AStack: TList<string>; AKind: TptTokenKind; AOrd: Integer; var ACtx: string);
begin
  if AKind in CondOpenKinds then
    AStack.Add(IntToStr(AOrd))
  else if (AKind in CondElseKinds) and (AStack.Count > 0) then
    AStack[AStack.Count - 1]:= IntToStr(AOrd)
  else if (AKind in CondCloseKinds) and (AStack.Count > 0) then
    AStack.Delete(AStack.Count - 1)
  else
    Exit;
  ACtx:= string.Join('/', AStack.ToArray);
end;

  // Extracts the three ordered content streams from ASource in one lex. When
  // ACommentIsLabel is supplied it receives one flag per COMMENT, marking the
  // ones the formatter is licensed to delete (Rule 3: exactly the marker it
  // would itself have written for that block); that costs an extra group parse,
  // so callers that do not need it pass nil.
// Appends the instruction LINES of every `asm ... end` body to AAsmLines: each
// physical line's text with whitespace runs collapsed to one space and
// trimmed, empty lines skipped. BASM separates instructions by line break and
// is NOT free-form Pascal, so joining, splitting or re-spelling an instruction
// line changes meaning (or breaks the build) while leaving every string,
// comment and directive intact -- the other three streams cannot see it.
procedure AddAsmLines(const ATokens: TTokenList; var AIdx: Integer; const AAsmLines: TList<string>);
var
  Line: string;

  procedure Flush;
  var
    S: string;
  begin
    S:= Trim(Line);
    while S.Contains('  ') do
      S:= StringReplace(S, '  ', ' ', [rfReplaceAll]);
    if S <> '' then
      AAsmLines.Add(S);
    Line:= '';
  end;

begin
  Line:= '';
  Inc(AIdx); // past `asm`
  while (AIdx < ATokens.Count) and not IsAsmBlockEnd(ATokens, AIdx) do
  begin
    if ATokens[AIdx].Kind in [ptCRLF, ptCRLFCo] then
      Flush
    else
      Line:= Line + StringReplace(ATokens[AIdx].Text, #9, ' ', [rfReplaceAll]);
    Inc(AIdx);
  end;
  Flush;
  Dec(AIdx); // the caller's loop steps onto the closing `end`
end; // procedure

procedure ExtractContent(const ASource: string; const AStrings, AComments, ADirectives: TList<string>; const ACommentIsLabel: TList<Boolean> = nil;
  const AAsmLines: TList<string> = nil; const ACode: TCodeList = nil);
var
  Tokens : TTokenList     ;
  T      : TToken         ;
  IsLbl  : TArray<Boolean>;
  Sens   : TArray<Boolean>;
  CondStk: TList<string>  ;
  Ctx    : string         ;
  DirOrd : Integer        ;
  i      : Integer        ;
  AsmLast: Integer        ;
begin
  AsmLast:= -1;
  DirOrd := 0;
  Ctx    := '';
  Tokens:= LoadTokensFromString(ASource);
  CondStk:= TList<string>.Create;
  try
    if ACommentIsLabel <> nil then
      IsLbl:= CollectBlockLabelComments(Tokens);
    if ACode <> nil then
      Sens:= SpellingSensitiveIdents(Tokens);
    i:= 0;
    while i < Tokens.Count do
    begin
      T:= Tokens[i];
      if (T.Kind = ptAsm) and (AAsmLines <> nil) then
      begin
        // Strings / comments / directives inside the body are still collected
        // below, so walk the body twice: once for its lines, once for content.
        var j:= i;
        AddAsmLines(Tokens, j, AAsmLines);
      end;
      if (T.Kind = ptAsm) and (ACode <> nil) then
      begin
        // BASM bodies are not free-form Pascal and are covered by AAsmLines;
        // keep `asm` and the closing `end` in the code stream, skip the body.
        AsmLast:= i;
        while (AsmLast + 1 < Tokens.Count) and not IsAsmBlockEnd(Tokens, AsmLast + 1) do
          Inc(AsmLast);
      end;
      if T.Kind in DirectiveKinds then
      begin
        Inc(DirOrd);
        StepCondContext(CondStk, T.Kind, DirOrd, Ctx);
      end;
      // Directives and literals take part as POSITION markers: their text is
      // compared by their own streams, their place among the code tokens here
      // (a declaration moved across an {$IFDEF} changes nothing else).
      if (ACode <> nil) and ((i > AsmLast) or (T.Kind = ptAsm)) then
        if T.Kind in DirectiveKinds then
          ACode.Add(MakeCodeTok(DIRECTIVE_KEY, '', ccDirective, Ctx))
        else if T.Kind in StringKinds + [ptAsciiChar] then
          ACode.Add(MakeCodeTok(STRING_KEY, '', ccString, Ctx))
        else if IsSplitExponent(Tokens, i) then
        begin
          // The lexer cuts `1E-9` into `1E` `-` `9`; spacing inside it (`1E -9`,
          // E2053) would leave those three tokens unchanged, so the guard keys
          // the adjacent run as ONE number.
          T.Text:= T.Text + Tokens[i + 1].Text + Tokens[i + 2].Text;
          AddCodeToken(ACode, T, False, Ctx);
          Inc(i, 2);
        end
        else if (T.Kind not in CommentKinds + CodeSkipKinds) and (T.Text <> '') then
          AddCodeToken(ACode, T, Sens[i], Ctx);
      if T.Kind in StringKinds then
        AStrings.Add(NormalizeNewlines(T.Text))
      else if T.Kind = ptAsciiChar then
      begin
        // `#$AB` vs `#$ab` is a legitimate hex-case normalization -- but the
        // lexer also files a one-character literal ('A') under ptAsciiChar,
        // and 'A' -> 'a' is a real change, so only #-forms are case-folded.
        if (T.Text <> '') and (T.Text[1] = '#') then
          AStrings.Add(LowerCase(T.Text))
        else
          AStrings.Add(T.Text);
      end
      else if T.Kind in CommentKinds then
      begin
        // TrimRight: the trailing-whitespace pass may trim spaces at the end
        // of a `// comment` line; that is not content damage.
        AComments.Add(TrimRight(NormalizeNewlines(T.Text)));
        if ACommentIsLabel <> nil then
          ACommentIsLabel.Add(IsLbl[i]);
      end
      else if T.Kind in DirectiveKinds then
        ADirectives.Add(DirectiveKey(T.Text));
      Inc(i);
    end; // while
  finally
    CondStk.Free;
    Tokens.Free;
  end; // try
end; // procedure

// True when A equals B element-for-element.
function SameSequence(const A, B: TList<string>): Boolean;
var
  i: Integer;
begin
  Result:= A.Count = B.Count;
  if not Result then
    Exit;
  for i:= 0 to A.Count - 1 do
    if A[i] <> B[i] then
      Exit(False);
end;

// True when every element of A appears in B, in A's order (two-pointer
// subsequence test). Lets the formatter ADD comments without ever being
// able to drop or alter one.
function IsSubsequence(const A, B: TList<string>): Boolean;
var
  Ia: Integer;
  Ib: Integer;
begin
  Ia:= 0;
  Ib:= 0;
  while (Ia < A.Count) and (Ib < B.Count) do
  begin
    if A[Ia] = B[Ib] then
      Inc(Ia);
    Inc  (Ib);
  end;
  Result:= Ia = A.Count;
end; // function

// First element of A not matched in B by the ordered-subsequence walk
// ('' when every element matched) -- the preview for the decline reason.
function FirstUnmatched(const A, B: TList<string>): string;
const
  PREVIEW_LEN = 40;  // longest preview of the unmatched element before '...'
var
  Ia: Integer;
  Ib: Integer;
begin
  Ia:= 0;
  Ib:= 0;
  while (Ia < A.Count) and (Ib < B.Count) do
  begin
    if A[Ia] = B[Ib] then
      Inc(Ia);
    Inc  (Ib);
  end;
  if Ia < A.Count then
  begin
    Result:= A[Ia];
    if Length(Result) > PREVIEW_LEN then
      Result:= Copy(Result, 1, PREVIEW_LEN) + '...';
  end
  else
    Result:= '';
end; // function

// Deletes every flagged entry from AList in place.
//
// A block-end marker that is EXACTLY `// ` + the keyword for its own block is
// FORMATTER-owned text, not the user's: this formatter writes it and (Rule 2 of
// the block-label lifecycle) deletes it again when the block shrinks. So the
// marker positions are stripped from BOTH streams and the user-content check
// runs, unchanged and unrelaxed, on everything that is left.
//
// Doing it positionally -- rather than excusing a missing marker by text -- is
// load-bearing: markers repeat (one file holds dozens of `// function`), and a
// by-text excuse cannot tell WHICH copy went missing. Every attempt to guess
// mis-aligned the ordered walk and declined a perfectly good format, blaming an
// innocent comment further down the file.
procedure DropFlagged(const AList: TList<string>; const AFlags: TList<Boolean>);
var
  i: Integer;
begin
  for i:= AList.Count - 1 downto 0 do
    if AFlags[i] then
      AList.Delete(i);
end;

// Drops the comments that are YADF's own --d10 flags (D10_TODO_MARKER).
procedure DropD10Todos(const AList: TList<string>);
var
  i: Integer;
begin
  for i:= AList.Count - 1 downto 0 do
    if AList[i].StartsWith(D10_TODO_MARKER) then
      AList.Delete(i);
end;

// Preview of a code-stream key for a decline reason.
function KeyPreview(const AKey: string): string;
begin
  Result:= if AKey = STRING_KEY then '<string literal>' else if AKey = DIRECTIVE_KEY then '<compiler directive>' else AKey;
end;

// '' when the two lists carry the same keys in the same order; else where
// they first diverge.
function SameKeysReason(const AOrig, AFmt: TCodeList): string;
var
  i: Integer;
begin
  i:= 0;
  while (i < AOrig.Count) and (i < AFmt.Count) and (AOrig[i].Key = AFmt[i].Key) do
    Inc(i);
  Result:= '';
  if i < AOrig.Count then
    Result:= 'code token reordered, lost or altered near: ' + KeyPreview(AOrig[i].Key)
  else if i < AFmt.Count then
    Result:= 'code token duplicated or added: ' + KeyPreview(AFmt[i].Key);
end;

// Spelling of the first identifier occurrence per key -- the spelling
// FirstOccCasing cascades (it, too, never sees asm bodies, comments or strings).
function FirstSpellings(const AList: TCodeList): TDictionary<string, string>;
var
  C: TCodeTok;
begin
  Result:= TDictionary<string, string>.Create;
  for C in AList do
    if (C.Cls = ccIdent) and not Result.ContainsKey(C.Key) then
      Result.Add(C.Key, C.Text);
end;

// '' when AFmt (same keys as AOrig, position by position) only re-cases what
// ACasing licenses; else the first unlicensed re-casing.
function CasingReasonByPosition(const AOrig, AFmt: TCodeList; ACasing: TGuardCasing): string;
var
  First: TDictionary<string, string>;
  O    : TCodeTok;
  F    : TCodeTok;
  Ok   : Boolean ;
  Want : string  ;
  i    : Integer ;
begin
  Result:= '';
  if gkAnyCase in ACasing then
    Exit;
  First:= FirstSpellings(AOrig);
  try
    for i:= 0 to AOrig.Count - 1 do
    begin
      O:= AOrig[i];
      F:= AFmt[i];
      if O.Text = F.Text then
        Continue;
      case O.Cls of
        ccIdent  : Ok:= (gkFirstOccurrence in ACasing) and not O.Sensitive and First.TryGetValue(O.Key, Want) and (F.Text = Want);
        ccKeyword: Ok:= (gkKeywordsLower in ACasing) and (F.Text = LowerCase(O.Text));
        ccNumber : Ok:= gkUpperHex in ACasing;
        else
          Ok:= False;
      end;
      if not Ok then
        Exit('code token re-cased: ' + O.Text + ' -> ' + F.Text);
    end; // for
  finally
    First.Free;
  end; // try
end; // function

procedure Bump(const ACounts: TDictionary<string, Integer>; const AKey: string; ADelta: Integer);
var
  N: Integer;
begin
  if ACounts.TryGetValue(AKey, N) then
    ACounts[AKey]:= N + ADelta
  else
    ACounts.Add(AKey, ADelta);
end;

// Order-free spelling check (gcD10): every output spelling of a name the
// original has must be a spelling the original used (or a licensed re-casing of
// a keyword / number); spellings that must survive -- the spelling-sensitive
// ones, or every identifier spelling without gkFirstOccurrence -- must occur in
// the output at least as often as in the original (outside `: Type` annotations).
function ContinuesType(const C: TCodeTok; var ANest: Integer): Boolean; forward;

function CasingReasonUnordered(const AOrig, AFmt: TCodeList; ACasing: TGuardCasing): string;
var
  Spell : THashSet<string>;
  Keys  : THashSet<string>;
  Need  : TDictionary<string, Integer>;
  C     : TCodeTok;
  KwOk  : Boolean ;
  NumOk : Boolean ;
  InType: Boolean ;
  Nest  : Integer ;
  N     : Integer ;
  Pair  : TPair<string, Integer>;
begin
  Result:= '';
  if gkAnyCase in ACasing then
    Exit;
  Spell:= THashSet<string>.Create;
  Keys := THashSet<string>.Create;
  Need := TDictionary<string, Integer>.Create;
  try
    // The identifiers of a `: Type` annotation are not counted: D10Reason checks
    // them as name-keyed sets, and the hoist legally drops a same-name/same-type
    // duplicate declaration (`var R: Integer` twice -> one `R: Integer;`).
    InType:= False;
    Nest  := 0;
    for C in AOrig do
    begin
      if InType then
        InType:= ContinuesType(C, Nest);
      if C.Cls in [ccIdent, ccKeyword, ccNumber] then
      begin
        Spell.Add(C.Text);
        Keys.Add(C.Key);
        if (C.Cls = ccIdent) and (C.Sensitive or (gkFirstOccurrence not in ACasing)) and not InType then
          Bump(Need, C.Text, 1);
      end;
      if C.Key = ':' then
      begin
        InType:= True;
        Nest  := 0;
      end;
    end; // for
    InType:= False;
    Nest  := 0;
    for C in AFmt do
    begin
      if InType then
        InType:= ContinuesType(C, Nest);
      if (C.Cls in [ccIdent, ccKeyword, ccNumber]) and Keys.Contains(C.Key) then
      begin
        KwOk := (C.Cls = ccKeyword) and (gkKeywordsLower in ACasing) and (C.Text = C.Key);
        NumOk:= (C.Cls = ccNumber) and (gkUpperHex in ACasing);
        if not (Spell.Contains(C.Text) or KwOk or NumOk) then
          Exit('code token re-cased: ' + C.Text);
        if not InType and Need.TryGetValue(C.Text, N) then
          Need[C.Text]:= N - 1;
      end;
      if C.Key = ':' then
      begin
        InType:= True;
        Nest  := 0;
      end;
    end; // for
    for Pair in Need do
      if Pair.Value > 0 then
        Exit('code token re-cased: ' + Pair.Key);
  finally
    Need.Free;
    Keys.Free;
    Spell.Free;
  end; // try
end; // function

// True for a key that opens / closes a nesting level inside a declaration type
// or a case-arm body.
function IsOpenerKey(const AKey: string): Boolean;
begin
  Result:= MatchStr(AKey, ['(', '[', 'begin', 'case', 'try', 'asm', 'record']);
end;

function IsCloserKey(const AKey: string): Boolean;
begin
  Result:= MatchStr(AKey, [')', ']', 'end']);
end;

function IsParamModifierKey(const AKey: string): Boolean;
begin
  Result:= MatchStr(AKey, ['const', 'var', 'out', 'constref']);
end;

// The expected form of the split transforms (gcSplit): every name list
// `A, B: <type or case-arm body>` becomes `A: <...>; B: <...>`, a parameter
// modifier (`const A, B: T` inside parentheses) repeated per name. Names are
// identifier / number tokens; the type / body runs to the first `;`, closer or
// directive at its own nesting level. Applied to BOTH streams, so a list the
// formatter leaves alone expands identically on both sides; only the
// re-spelling the split passes make is absorbed.
// Index of the last name of a name list starting at AFrom (`A, B, C`), or
// AFrom when AList[AFrom] starts none.
function NameListEnd(const AList: TCodeList; AFrom: Integer): Integer;
begin
  Result:= AFrom;
  while (Result + 2 < AList.Count) and (AList[Result + 1].Key = ',') and (AList[Result + 2].Cls in [ccIdent, ccNumber]) do
    Inc(Result, 2);
end;

// Index just past the type / case-arm body that starts at AFrom: the first
// `;`, unmatched closer or directive at its own nesting level.
function ListBodyEnd(const AList: TCodeList; AFrom: Integer): Integer;
var
  Nest: Integer;
begin
  Result:= AFrom;
  Nest  := 0;
  while (Result < AList.Count) and (AList[Result].Cls <> ccDirective) do
  begin
    if IsOpenerKey(AList[Result].Key) then
      Inc(Nest)
    else if IsCloserKey(AList[Result].Key) then
    begin
      if Nest = 0 then
        Exit;
      Dec(Nest);
    end
    else if (Nest = 0) and (AList[Result].Key = ';') then
      Exit;
    Inc(Result);
  end; // while
end; // function

// Appends the expansion of the name list AFirst..ALast (names every second
// token, `:` at ALast + 1, body up to ABodyEnd) to AOut; AMod >= 0 is the index
// of a parameter modifier to repeat before every name after the first.
procedure EmitExpandedList(const AList, AOut: TCodeList; AFirst, ALast, ABodyEnd, AMod: Integer);
var
  n: Integer;
  b: Integer;
begin
  n:= AFirst;
  while n <= ALast do
  begin
    if n > AFirst then
    begin
      AOut.Add(MakeCodeTok(';', ';', ccOther, AList[ALast + 1].Ctx));
      if AMod >= 0 then
        AOut.Add(AList[AMod]);
    end;
    AOut.Add(AList[n]);
    for b:= ALast + 1 to ABodyEnd - 1 do
      AOut.Add(AList[b]);
    Inc(n, 2);
  end; // while
end; // procedure

// The expected form of the split transforms (gcSplit): every name list
// `A, B: <type or case-arm body>` becomes `A: <...>; B: <...>`, a parameter
// modifier (`const A, B: T` inside parentheses) repeated per name. Names are
// identifier / number tokens; the type / body runs to the first `;`, closer or
// directive at its own nesting level. Applied to BOTH streams, so a list the
// formatter leaves alone expands identically on both sides; only the
// re-spelling the split passes make is absorbed.
function ExpandNameLists(const AList: TCodeList): TCodeList;
var
  Depth: Integer;
  i    : Integer;
  Last : Integer;
  Body : Integer;
  Modi : Integer;
  Untyped: Boolean;
begin
  Result:= TCodeList.Create;
  Depth := 0;
  i     := 0;
  while i < AList.Count do
  begin
    Last:= i;
    if AList[i].Cls in [ccIdent, ccNumber] then
      Last:= NameListEnd(AList, i);
    Modi:= if (Depth > 0) and (i > 0) and IsParamModifierKey(AList[i - 1].Key) then i - 1 else -1;
    // An UNTYPED parameter list (`var A, B)`) re-spells as `var A; var B` too.
    Untyped:= (Last > i) and (Modi >= 0) and (Last + 1 < AList.Count) and MatchStr(AList[Last + 1].Key, [')', ';']);
    if Untyped or ((Last > i) and (Last + 1 < AList.Count) and (AList[Last + 1].Key = ':')) then
    begin
      Body:= if Untyped then Last + 1 else ListBodyEnd(AList, Last + 2);
      EmitExpandedList(AList, Result, i, Last, Body, Modi);
      i:= Body;
      Continue;
    end;
    if AList[i].Key = '(' then
      Inc(Depth)
    else if (AList[i].Key = ')') and (Depth > 0) then
      Dec(Depth);
    Result.Add(AList[i]);
    Inc(i);
  end; // while
end; // function
// True when C may continue a `: Type` annotation; ANest tracks <...> / [...].
function ContinuesType(const C: TCodeTok; var ANest: Integer): Boolean;
begin
  if (C.Key = '<') or (C.Key = '[') then
  begin
    Inc(ANest);
    Exit(True);
  end;
  if (C.Key = '>') or (C.Key = ']') then
  begin
    if ANest = 0 then
      Exit(False);
    Dec(ANest);
    Exit(True);
  end;
  Result:= (C.Cls in [ccIdent, ccNumber]) or MatchStr(C.Key, ['string', 'array', 'of', 'set', 'file', 'packed', '.', '..', '^']) or ((C.Key = ',') and (ANest > 0));
end;

// Splits AList (gcD10) into, per conditional branch, a bag of plain tokens and
// a set of `: Type` annotations. Commas, semicolons, var/const and the names of
// a `var` declaration are noise the hoist legitimately moves or deletes.
procedure CollectD10(const AList: TCodeList; const ABags: TObjectDictionary<string, TDictionary<string, Integer>>; const ATypes: TObjectDictionary<string, THashSet<string>>);
var
  Bag  : TDictionary<string, Integer>;
  Types: THashSet<string>;
  Frag : string ;
  Nest : Integer;
  i    : Integer;
  j    : Integer;
  k    : Integer;
  C    : TCodeTok;
begin
  i:= 0;
  while i < AList.Count do
  begin
    C:= AList[i];
    if not ABags.TryGetValue(C.Ctx, Bag) then
    begin
      Bag:= TDictionary<string, Integer>.Create;
      ABags.Add(C.Ctx, Bag);
    end;
    if not ATypes.TryGetValue(C.Ctx, Types) then
    begin
      Types:= THashSet<string>.Create;
      ATypes.Add(C.Ctx, Types);
    end;
    if C.Key = ':' then
    begin
      // Keyed WITH the declared name: `R: Integer` must survive as such -- a
      // parameter `N: Integer` elsewhere must not cover for it.
      Frag:= (if i > 0 then AList[i - 1].Key + ' ' else '') + ':';
      // The names of a `var A, B: T` declaration are not counted in the bag: the
      // hoist legitimately DROPS a second declaration of a name it already
      // hoisted with the same type, names included (task 10). The `B : T`
      // fragment still has to survive in the set below.
      j:= i - 1;
      while (j >= 0) and ((AList[j].Cls = ccIdent) or (AList[j].Key = ',')) and (AList[j].Key <> 'var') do
        Dec(j);
      if (j >= 0) and (j < i - 1) and (AList[j].Key = 'var') and (AList[j].Ctx = C.Ctx) then
        for k:= j + 1 to i - 1 do
          if AList[k].Cls = ccIdent then
            Bump(Bag, AList[k].Key, -1);
      Nest:= 0;
      Inc(i);
      while (i < AList.Count) and ContinuesType(AList[i], Nest) do
      begin
        Frag:= Frag + ' ' + AList[i].Key;
        Inc(i);
      end;
      Types.Add(Frag);
      Continue;
    end;
    // ; is noise too: a dropped duplicate declaration takes its own ; along.
    if (C.Key <> ',') and (C.Key <> ';') and (C.Key <> 'var') and (C.Key <> 'const') and (C.Cls <> ccDirective) then
      Bump(Bag, C.Key, 1);
    Inc(i);
  end; // while
end; // procedure

// gcD10 order stream (task 10): the code keys of AList in order, with what the
// hoist legitimately moves, adds or drops taken out -- the `var` keyword and the
// names it declares, every `: Type` annotation, a `const` declaration up to its
// `;`, and commas / semicolons. The source stream must be a subsequence of the
// output stream: the hoist adds declarations, but never reorders code.
function D10OrderKeys(const AList: TCodeList): TList<string>;
var
  i   : Integer;
  j   : Integer;
  Nest: Integer;
  C   : TCodeTok;
begin
  Result:= TList<string>.Create;
  i:= 0;
  while i < AList.Count do
  begin
    C:= AList[i];
    if C.Key = 'var' then
    begin
      j:= i + 1;
      while (j < AList.Count) and ((AList[j].Cls = ccIdent) or (AList[j].Key = ',')) do
        Inc(j);
      // `var A, B: T` -> continue at the `:`; `for var I:= 0` keeps `I`.
      i:= if (j < AList.Count) and (AList[j].Key = ':') then j else i + 1;
      Continue;
    end;
    if C.Key = 'const' then
    begin
      while (i < AList.Count) and (AList[i].Key <> ';') do
        Inc(i);
      Inc(i);
      Continue;
    end;
    if C.Key = ':' then
    begin
      Nest:= 0;
      Inc(i);
      while (i < AList.Count) and ContinuesType(AList[i], Nest) do
        Inc(i);
      Continue;
    end;
    if (C.Key <> ',') and (C.Key <> ';') then
      Result.Add(C.Key);
    Inc(i);
  end; // while
end; // function

// gcD10: see TGuardCodeMode.
function D10Reason(const AOrig, AFmt: TCodeList): string;
var
  OrigBags : TObjectDictionary<string, TDictionary<string, Integer>>;
  OutBags : TObjectDictionary<string, TDictionary<string, Integer>>;
  OrigTypes: TObjectDictionary<string, THashSet<string>>;
  OutTypes: TObjectDictionary<string, THashSet<string>>;
  Bag   : TDictionary<string, Integer>;
  Types : THashSet<string>;
  Ctx   : TPair<string, TDictionary<string, Integer>>;
  Pair  : TPair<string, Integer>;
  CtxT  : TPair<string, THashSet<string>>;
  Frag  : string ;
  N     : Integer;
  OrigKeys: TList<string>;
  OutKeys : TList<string>;
begin
  Result:= '';
  OrigBags :=TObjectDictionary<string, TDictionary<string, Integer>>.Create([doOwnsValues]);
  OutBags := TObjectDictionary<string, TDictionary<string, Integer>>.Create([doOwnsValues]);
  OrigTypes:= TObjectDictionary<string, THashSet<string>>.Create([doOwnsValues]);
  OutTypes:= TObjectDictionary<string, THashSet<string>>.Create([doOwnsValues]);
  try
    CollectD10(AOrig, OrigBags, OrigTypes);
    CollectD10(AFmt , OutBags, OutTypes);
    for Ctx in OrigBags do
    begin
      if not OutBags.TryGetValue(Ctx.Key, Bag) then
        Bag:= nil;
      for Pair in Ctx.Value do
      begin
        N:= 0;
        if Bag <> nil then
          Bag.TryGetValue(Pair.Key, N);
        if N < Pair.Value then
          Exit('code token lost by the Delphi 10 transform: ' + KeyPreview(Pair.Key));
      end;
    end; // for
    for CtxT in OrigTypes do
    begin
      if not OutTypes.TryGetValue(CtxT.Key, Types) then
        Types:= nil;
      for Frag in CtxT.Value do
        if (Types = nil) or not Types.Contains(Frag) then
          Exit('declared type lost or moved out of its conditional branch by the Delphi 10 transform: ' + Frag);
    end;
    OrigKeys:= D10OrderKeys(AOrig);
    OutKeys := D10OrderKeys(AFmt);
    try
      if not IsSubsequence(OrigKeys, OutKeys) then
        Exit('code token reordered by the Delphi 10 transform near: ' + KeyPreview(FirstUnmatched(OrigKeys, OutKeys)));
    finally
      OutKeys.Free;
      OrigKeys.Free;
    end; // try
  finally
    OutTypes.Free;
    OrigTypes.Free;
    OutBags.Free;
    OrigBags.Free;
  end; // try
end; // function

// Routine-scope declaration census for gcD10 (2026-11-03, the guard's scope gap):
// ACounts['<scope>/<name>'] = how often <name> is declared in a var / const /
// threadvar / resourcestring section of one declaration scope. A scope is the
// unit, or one routine header and the declaration part that follows it; a nested
// routine is its own scope until its body ends. Bodies (begin / asm .. end) are
// skipped for the count -- inline vars are block-scoped and may repeat -- but
// AInline gets '<scope>/<name>' for every inline `var` / `for var` name a body
// declares outside an anonymous method (review 2026-11-03 M1: a name hoisted into
// the section next to one left inline is E2004 too). Scope numbers follow the
// header order, which the Delphi 10 transform never changes, so the source and
// the output number their scopes alike. Not a parser: a shape it does not know (a
// type section, a class) only ends the current section.
// AShadow (review 2026-11-04 H1) gets '<scope>/<name>' for each such inline name
// that a hoist would let shadow an outer binding: the name occurs in the body
// where no inline declaration of it is in scope (a field, a global), or the
// declaration sits in a `with` body (a member may share the name).
procedure CountScopeDecls(const AList: TCodeList; const ACounts: TDictionary<string, Integer>; const ANames: TDictionary<string, string>; const AInline, AShadow: TDictionary<string, Boolean>);
const
  OPENERS: array[0..5] of string = ('begin', 'try', 'case', 'asm', 'repeat', 'record');
  CLOSERS: array[0..1] of string = ('end', 'until');
var
  Stack    : TStack<Integer>;
  Anon     : TStack<Integer>;
  BodyVars : TList<Integer>;
  BodyFrom : Integer;
  Seq      : Integer;
  Body     : Integer;
  Paren    : Integer;
  i        : Integer;
  Next     : Integer;
  InSection: Boolean;
  PendAnon : Boolean;
  Key      : string ;
  Prev     : string ;

  // The declaration `Name[, Name]` + `:` / `=` starting at AFrom counted in the
  // current scope: the index past its `;` (outside brackets and record .. end),
  // or -1 when no declaration starts there.
  function CountDeclaration(AFrom: Integer): Integer;
  var
    Last: Integer;
    Nest: Integer;
    j   : Integer;
    N   : Integer;
    Slot: string ;
  begin
    Last:= NameListEnd(AList, AFrom);
    if (Last + 1 >= AList.Count) or not MatchStr(AList[Last + 1].Key, [':', '=']) then
      Exit(-1);
    j:= AFrom;
    while j <= Last do
    begin
      Slot:= IntToStr(Stack.Peek) + '/' + AList[j].Key;
      N   := 0;
      ACounts.TryGetValue(Slot, N);
      ACounts.AddOrSetValue(Slot, N + 1);
      ANames.AddOrSetValue(Slot, AList[j].Text);
      Inc(j, 2);
    end;
    Nest:= 0;
    j   := Last + 2;
    while (j < AList.Count) and not ((Nest = 0) and (AList[j].Key = ';')) do
    begin
      if MatchStr(AList[j].Key, ['(', '[', 'record']) then
        Inc(Nest)
      else if MatchStr(AList[j].Key, [')', ']', 'end']) and (Nest > 0) then
        Dec(Nest);
      Inc(j);
    end;
    Result:= j + 1;
  end; // function

  // An inline `var Name[, Name]` / `for var Name` at AFrom (the `var`) in a
  // body: its names go to AInline under the current scope.
  procedure NoteInline(AFrom: Integer);
  var
    Last: Integer;
    j   : Integer;
    Slot: string ;
  begin
    if (AFrom + 1 >= AList.Count) or (AList[AFrom + 1].Cls <> ccIdent) then
      Exit;
    Last:= NameListEnd(AList, AFrom + 1);
    if (Last + 1 >= AList.Count) or not MatchStr(AList[Last + 1].Key, [':', ':=', 'in']) then
      Exit;
    j:= AFrom + 1;
    while j <= Last do
    begin
      Slot:= IntToStr(Stack.Peek) + '/' + AList[j].Key;
      AInline.AddOrSetValue(Slot, True);
      ANames.AddOrSetValue(Slot, AList[j].Text);
      Inc(j, 2);
    end;
    BodyVars.Add(AFrom);
  end; // procedure

  // Index of the innermost unclosed block opener before AIdx (after AFloor), or
  // -1; for an `end` / `until` at AIdx, that block's own opener.
  function OpenerBefore(AIdx, AFloor: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    Result:= AIdx - 1;
    while Result > AFloor do
    begin
      if MatchStr(AList[Result].Key, CLOSERS) then
        Inc(Depth)
      else if MatchStr(AList[Result].Key, OPENERS) then
      begin
        if Depth = 0 then
          Exit;
        Dec(Depth);
      end;
      Dec(Result);
    end; // while
    Result:= -1;
  end; // function

  // Index of the `end` / `until` closing the block that holds AIdx, or ACeil.
  function CloserAfter(AIdx, ACeil: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    Result:= AIdx + 1;
    while Result < ACeil do
    begin
      if MatchStr(AList[Result].Key, OPENERS) then
        Inc(Depth)
      else if MatchStr(AList[Result].Key, CLOSERS) then
      begin
        if Depth = 0 then
          Exit;
        Dec(Depth);
      end;
      Inc(Result);
    end; // while
    Result:= ACeil;
  end; // function

  // True when the statement holding AVar, or one enclosing it, is a `with`.
  function InWith(AVar, AFloor: Integer): Boolean;
  var
    p: Integer;
    j: Integer;
  begin
    p:= AVar;
    while p > AFloor do
    begin
      j:= p - 1;
      while j > AFloor do
      begin
        if MatchStr(AList[j].Key, CLOSERS) then
        begin
          j:= OpenerBefore(j, AFloor);
          if j < 0 then
            Exit(False);
        end
        else if MatchStr(AList[j].Key, [';', 'begin', 'try', 'repeat', 'finally', 'except', 'of']) then
          Break
        else if AList[j].Key = 'with' then
          Exit(True);
        Dec(j);
      end; // while
      p:= OpenerBefore(p, AFloor);
      if p < 0 then
        Exit(False);
    end; // while
    Result:= False;
  end; // function

  // True when the identifier AKey occurs in the body (AFloor..ACeil) outside the
  // scope of every `var` / `const` declaration of it (declaration to block end);
  // a member access (`.AKey`) does not count.
  function RefOutside(const AKey: string; AFloor, ACeil: Integer): Boolean;
  var
    Cover: TList<TPair<Integer, Integer>>;
    Rng  : TPair<Integer, Integer>;
    j    : Integer;
    Last : Integer;
    n    : Integer;
    Hit  : Boolean;
  begin
    Result:= False;
    Cover := TList<TPair<Integer, Integer>>.Create;
    try
      for j:= AFloor + 1 to ACeil - 1 do
        if MatchStr(AList[j].Key, ['var', 'const']) and (j + 1 < ACeil) and (AList[j + 1].Cls = ccIdent) then
        begin
          Last:= NameListEnd(AList, j + 1);
          n   := j + 1;
          while n <= Last do
          begin
            if AList[n].Key = AKey then
            begin
              Cover.Add(TPair<Integer, Integer>.Create(j, CloserAfter(j, ACeil)));
              Break;
            end;
            Inc(n, 2);
          end; // while
        end; // if
      for j:= AFloor + 1 to ACeil - 1 do
      begin
        if (AList[j].Cls <> ccIdent) or (AList[j].Key <> AKey) or (AList[j - 1].Key = '.') then
          Continue;
        Hit:= False;
        for Rng in Cover do
          if (j > Rng.Key) and (j < Rng.Value) then
          begin
            Hit:= True;
            Break;
          end;
        if not Hit then
          Exit(True);
      end; // for
    finally
      Cover.Free;
    end; // try
  end; // function

  // The body that ends at ATo closes: AShadow gets each of its inline names a
  // hoist would let shadow an outer binding (InWith / RefOutside).
  procedure NoteShadows(ATo: Integer);
  var
    v   : Integer;
    j   : Integer;
    Last: Integer;
    W   : Boolean;
  begin
    for v in BodyVars do
    begin
      W   := InWith(v, BodyFrom);
      Last:= NameListEnd(AList, v + 1);
      j   := v + 1;
      while j <= Last do
      begin
        if W or RefOutside(AList[j].Key, BodyFrom, ATo) then
          AShadow.AddOrSetValue(IntToStr(Stack.Peek) + '/' + AList[j].Key, True);
        Inc(j, 2);
      end; // while
    end; // for
    BodyVars.Clear;
  end; // procedure

  // One token (index AIdx) of a begin / asm .. end body: tracks its nesting and
  // the anonymous methods in it, notes inline vars, and the end of the body
  // closes the routine's scope. An anonymous method's `var` (parameter, own
  // section or body) belongs to its own scope and is not noted.
  procedure StepBody(AIdx: Integer);
  var
    BKey: string;
  begin
    BKey:= AList[AIdx].Key;
    if MatchStr(BKey, ['procedure', 'function']) and not MatchStr(Prev, [':', '=', 'to']) then
      PendAnon:= True
    else if MatchStr(BKey, ['begin', 'case', 'try', 'asm', 'record']) then
    begin
      Inc(Body);
      if PendAnon and (BKey = 'begin') then
      begin
        Anon.Push(Body);
        PendAnon:= False;
      end;
    end
    else if BKey = 'end' then
    begin
      if (Anon.Count > 0) and (Anon.Peek = Body) then
        Anon.Pop;
      Dec(Body);
      if Body = 0 then
        NoteShadows(AIdx);
      if (Body = 0) and (Stack.Count > 1) then
        Stack.Pop;
    end
    else if (BKey = 'var') and not PendAnon and (Anon.Count = 0) then
      NoteInline(AIdx);
    Prev:= BKey;
  end; // procedure

begin
  Stack   := TStack<Integer>.Create;
  Anon    := TStack<Integer>.Create;
  BodyVars:= TList<Integer>.Create;
  try
    Stack.Push(0);
    BodyFrom := 0;
    Seq      := 0;
    Body     := 0;
    Paren    := 0;
    InSection:= False;
    PendAnon := False;
    Prev     := '';
    i        := 0;
    while i < AList.Count do
    begin
      Key:= AList[i].Key;
      if AList[i].Cls = ccDirective then
      begin
        Inc(i);
        Continue;
      end;
      if Body > 0 then
      begin
        StepBody(i);
        Inc(i);
        Continue;
      end; // if
      if (Key = '(') or (Key = '[') then
        Inc(Paren)
      else if ((Key = ')') or (Key = ']')) and (Paren > 0) then
        Dec(Paren);
      if (Paren > 0) or (Key = ')') or (Key = ']') then
      begin
        Prev:= Key;
        Inc(i);
        Continue;
      end;
      // A declaration in an open section: `Name[, Name]` then `:` or `=`.
      Next:= if InSection and (AList[i].Cls = ccIdent) then CountDeclaration(i) else -1;
      if Next >= 0 then
      begin
        Prev:= ';';
        i   := Next;
        Continue;
      end;
      if MatchStr(Key, ['var', 'const', 'threadvar', 'resourcestring']) then
        InSection:= True
      else if MatchStr(Key, ['procedure', 'function', 'constructor', 'destructor', 'operator']) then
      begin
        InSection:= False;
        // A procedural TYPE (`= procedure`, `: function`, `reference to`) is no header.
        if not MatchStr(Prev, ['=', ':', 'to']) then
        begin
          Inc(Seq);
          Stack.Push(Seq);
        end;
      end
      else if (Key = 'begin') or (Key = 'asm') then
      begin
        InSection:= False;
        PendAnon := False;
        Anon.Clear;
        BodyVars.Clear;
        BodyFrom := i;
        Body     := 1;
      end
      else if (Key = 'initialization') or (Key = 'finalization') then
        Break
      else if AList[i].Cls <> ccIdent then
        InSection:= InSection and MatchStr(Key, [';', ',', ':', '=']);
      Prev:= Key;
      Inc(i);
    end; // while
  finally
    BodyVars.Free;
    Anon.Free;
    Stack.Free;
  end; // try
end; // procedure

// gcD10: '' unless the output declares a name more often in one routine scope
// than the source does (a hoist that duplicated a declaration: E2004), or
// declares a name in a routine's section that the same routine's body still
// declares inline where the source did not (a hoist next to a declaration a TODO
// fallback left inline: E2004, review 2026-11-03 M1), or adds a section
// declaration of an inline name the source binds outside its block or declares
// in a `with` body (the hoisted local would shadow that binding; review
// 2026-11-04 H1).
function D10ScopeReason(const AOrig, AFmt: TCodeList): string;
var
  OrigCounts: TDictionary<string, Integer>;
  OutCounts : TDictionary<string, Integer>;
  OrigInline: TDictionary<string, Boolean>;
  OutInline : TDictionary<string, Boolean>;
  OrigShadow: TDictionary<string, Boolean>;
  OutShadow : TDictionary<string, Boolean>;
  Names     : TDictionary<string, string>;
  Pair      : TPair<string, Integer>;
  N         : Integer;
begin
  Result    := '';
  OrigCounts:= TDictionary<string, Integer>.Create;
  OutCounts := TDictionary<string, Integer>.Create;
  OrigInline:= TDictionary<string, Boolean>.Create;
  OutInline := TDictionary<string, Boolean>.Create;
  OrigShadow:= TDictionary<string, Boolean>.Create;
  OutShadow := TDictionary<string, Boolean>.Create;
  Names     := TDictionary<string, string>.Create;
  try
    CountScopeDecls(AOrig, OrigCounts, Names, OrigInline, OrigShadow);
    Names.Clear;
    CountScopeDecls(AFmt, OutCounts, Names, OutInline, OutShadow);
    for Pair in OutCounts do
    begin
      N:= 0;
      OrigCounts.TryGetValue(Pair.Key, N);
      if (Pair.Value > 1) and (Pair.Value > N) then
        Exit('declaration duplicated in one routine by the Delphi 10 transform: ' + Names[Pair.Key]);
      if OutInline.ContainsKey(Pair.Key) and not ((N > 0) and OrigInline.ContainsKey(Pair.Key)) then
        Exit('declaration hoisted next to the same name left inline by the Delphi 10 transform: ' + Names[Pair.Key]);
      if (Pair.Value > N) and OrigShadow.ContainsKey(Pair.Key) then
        Exit('declaration hoisted over an outer binding of the same name by the Delphi 10 transform: ' + Names[Pair.Key]);
    end;
  finally
    OutShadow.Free;
    OrigShadow.Free;
    OutInline.Free;
    OrigInline.Free;
    Names.Free;
    OutCounts.Free;
    OrigCounts.Free;
  end; // try
end; // function
// '' when the code-token stream of the output is acceptable for AMode and
// ACasing; else a short decline cause. See TGuardCodeMode / TGuardCasingRule.
function CodeStreamReason(const AOrig, AFmt: TCodeList; AMode: TGuardCodeMode; ACasing: TGuardCasing): string;
var
  O: TCodeList;
  F: TCodeList;
begin
  Result:= '';
  case AMode of
    gcStrict:
    begin
      Result:= SameKeysReason(AOrig, AFmt);
      if Result = '' then
        Result:= CasingReasonByPosition(AOrig, AFmt, ACasing);
    end;
    gcSplit:
    begin
      O:= ExpandNameLists(AOrig);
      F:= nil;
      try
        F:= ExpandNameLists(AFmt);
        Result:= SameKeysReason(O, F);
        if Result = '' then
          Result:= CasingReasonByPosition(O, F, ACasing);
      finally
        F.Free;
        O.Free;
      end; // try
    end;
    gcD10:
    begin
      Result:= D10Reason(AOrig, AFmt);
      if Result = '' then
        Result:= D10ScopeReason(AOrig, AFmt);
      if Result = '' then
        Result:= CasingReasonUnordered(AOrig, AFmt, ACasing);
    end;
  end; // case
end; // function

function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; out AReason: string): Boolean;
begin
  Result:= FormatPreservesContent(AOriginal, AFormatted, AAllowStringDuplication, AAllowLabelRemoval, gcNone, AReason);
end;

function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; ACodeMode: TGuardCodeMode; out AReason: string): Boolean;
begin
  Result:= FormatPreservesContent(AOriginal, AFormatted, AAllowStringDuplication, AAllowLabelRemoval, ACodeMode, [gkAnyCase], AReason);
end;

function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; ACodeMode: TGuardCodeMode; ACasing: TGuardCasing;
  out AReason: string): Boolean;
var
  OrigStr: TList<string>;
  FmtStr : TList<string>;
  OrigCom: TList<string>;
  FmtCom : TList<string>;
  OrigDir: TList<string>;
  FmtDir : TList<string>;
  OrigLbl: TList<Boolean>;
  FmtLbl : TList<Boolean>;
  OrigAsm: TList<string>;
  FmtAsm : TList<string>;
  OrigCod: TCodeList    ;
  FmtCod : TCodeList    ;
  StrOk  : Boolean      ;
  Marker : string       ;
begin
  AReason:= '';
  // A formatter-internal marker in the output that the input never had is a
  // shield that failed to restore -- decline before anything else. Checked on
  // the RAW text: the lexer-based streams below go through the same shield and
  // would be just as blind to it.
  for Marker in SHIELD_MARKERS do
    if CountOccurrences(Marker, AFormatted) > CountOccurrences(Marker, AOriginal) then
    begin
      AReason:= 'formatter shield marker leaked into the output: ' + Marker;
      Exit(False);
    end;
  OrigAsm:= TList<string>.Create;
  FmtAsm := TList<string>.Create;
  OrigCod:= TCodeList.Create;
  FmtCod := TCodeList.Create;
  OrigStr:= TList<string>.Create;
  FmtStr:= TList<string>.Create;
  OrigCom:= TList<string>.Create;
  FmtCom:= TList<string>.Create;
  OrigDir:= TList<string>.Create;
  FmtDir:= TList<string>.Create;
  OrigLbl:= TList<Boolean>.Create;
  FmtLbl:= TList<Boolean>.Create;
  try
    try
      if AAllowLabelRemoval then
      begin
        ExtractContent(AOriginal , OrigStr, OrigCom, OrigDir, OrigLbl, OrigAsm, OrigCod);
        ExtractContent(AFormatted, FmtStr , FmtCom , FmtDir , FmtLbl , FmtAsm , FmtCod );
        // Formatter-owned block-end markers take no part in the user-content
        // check -- on EITHER side. Everything else stays exactly as strict.
        DropFlagged(OrigCom, OrigLbl);
        DropFlagged(FmtCom , FmtLbl );
      end
      else
      begin
        ExtractContent(AOriginal , OrigStr, OrigCom, OrigDir, nil, OrigAsm, OrigCod);
        ExtractContent(AFormatted, FmtStr , FmtCom , FmtDir , nil, FmtAsm , FmtCod );
      end;
      // YADF's own --d10 flags may be removed (a run without --d10 strips them).
      DropD10Todos(OrigCom);
      // Directives stay STRICT even under duplication-tolerant mode: a
      // duplicated {$IFDEF}/{$ENDIF} inside a duplicated case arm would
      // unbalance conditional compilation -- that must decline.
      StrOk:= if AAllowStringDuplication then IsSubsequence(OrigStr, FmtStr) else SameSequence(OrigStr, FmtStr);
      if not StrOk then
        AReason:= 'string literal lost or altered: ' + FirstUnmatched(OrigStr, FmtStr)
      else if not SameSequence(OrigDir, FmtDir) then
        AReason:= 'compiler directive lost, altered or duplicated: ' + FirstUnmatched(OrigDir, FmtDir)
      else if not IsSubsequence(OrigCom, FmtCom) then
        AReason:= 'comment lost or altered: ' + FirstUnmatched(OrigCom, FmtCom)
      else if not SameSequence(OrigAsm, FmtAsm) then
        AReason:= 'asm instruction lines joined, split or altered: ' + FirstUnmatched(OrigAsm, FmtAsm)
      else
      begin
        AReason:= CodeStreamReason(OrigCod, FmtCod, ACodeMode, ACasing);
        if AReason <> '' then
          AReason:= 'code tokens: ' + AReason;
      end;
      Result:= AReason = '';
    except  // dl:ok bare-except@1e8f
      // Cannot verify -> fail closed; the caller keeps the original text.
      AReason:= 'content could not be verified (lexing failed)';
      Result := False;
    end; // try
  finally
    OrigStr.Free;
    FmtStr.Free;
    OrigCom.Free;
    FmtCom.Free;
    OrigDir.Free;
    FmtDir.Free;
    OrigLbl.Free;
    FmtLbl.Free;
    OrigAsm.Free;
    FmtAsm .Free;
    OrigCod.Free;
    FmtCod .Free;
  end; // try
end; // function

function FormatPreservesContent(const AOriginal, AFormatted: string): Boolean;
var
  Reason: string;
begin
  Result:= FormatPreservesContent(AOriginal, AFormatted, False, False, Reason);
end;

end.


