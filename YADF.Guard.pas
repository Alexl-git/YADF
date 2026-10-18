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
/// <para>Overload 1 of 3</para>
/// <para>Directives: overload</para>
/// <seealso cref="YADF.Guard.FormatPreservesContent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string): Boolean; overload;

type
  /// <summary>How strictly the guard compares the CODE-token stream (every token
  /// that is not whitespace, a comment, a directive, a string/char literal or an
  /// asm body), lowercased.</summary>
  /// <remarks>
  /// gcNone: code tokens are not compared (historic behaviour of the 2- and
  /// 5-argument overloads). gcStrict: the sequences must be identical -- any
  /// reordered, lost or duplicated token declines. gcSplit: for
  /// SplitMultiVarDecls / BreakCaseLabels, which legitimately re-spell
  /// `A, B: T;` as `A: T; B: T;`; the original minus its commas must be an
  /// ordered subsequence of the output minus its commas AND the output may not
  /// contain an identifier/number the original lacks. gcD10: the Delphi10Compat
  /// hoist moves `name: Type` ahead of its statement, so order is NOT checked;
  /// every original token (ignoring commas and var/const) must still occur in
  /// the output at least as often (nothing lost; duplicates and new names
  /// tolerated).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (YADF.Guard.pas), YADF.Guard.CodeStreamReason (YADF.Guard.pas), YADF.Layout.FormatSource/3 (YADF.Layout.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGuardCodeMode = (gcNone, gcStrict, gcSplit, gcD10);

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
/// <para>Called from: YADF.Guard.FormatPreservesContent/5 (YADF.Guard.pas), YADF.Layout.FormatSource/3 (YADF.Layout.pas)</para>
/// <para>Calls: Pos, YADF.Guard.CodeStreamReason, YADF.Guard.DropFlagged, YADF.Guard.ExtractContent, YADF.Guard.FirstUnmatched, YADF.Guard.IsSubsequence, YADF.Guard.SameSequence</para>
/// <para>Returns: False; AReason = ''</para>
/// <para>Overload 2 of 3</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 89 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Mutates: AReason (out)</para>
/// <para>Directives: overload</para>
/// <seealso cref="YADF.Guard.CodeStreamReason"/>
/// <seealso cref="YADF.Guard.DropFlagged"/>
/// <seealso cref="YADF.Guard.ExtractContent"/>
/// <seealso cref="YADF.Guard.FirstUnmatched"/>
/// <seealso cref="YADF.Guard.IsSubsequence"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; ACodeMode: TGuardCodeMode; out AReason: string): Boolean; overload;

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
/// <para>Overload 3 of 3</para>
/// <para>Directives: overload</para>
/// <seealso cref="YADF.Guard.FormatPreservesContent"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; out AReason: string): Boolean; overload;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , SimpleParser.Lexer.Types
  , YADF.Groups
  , YADF.Tokens
  ;

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
  // asm placeholders (YADF.Layout `__YADF_ML_n__`, `__YADF_MLC_n__`, ...).
  SHIELD_MARKERS: array[0..1] of string = ('ZQYADF', '__YADF_');

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
    while Pos('  ', S) > 0 do
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
  const AAsmLines: TList<string> = nil; const ACode: TList<string> = nil);
var
  Tokens : TTokenList    ;
  T      : TToken        ;
  IsLbl  : TArray<Boolean>;
  i      : Integer       ;
  AsmLast: Integer       ;
begin
  AsmLast:= -1;
  Tokens:= LoadTokensFromString(ASource);
  try
    if ACommentIsLabel <> nil then
      IsLbl:= CollectBlockLabelComments(Tokens);
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
      if (ACode <> nil) and ((i > AsmLast) or (T.Kind = ptAsm)) then
        if not (T.Kind in StringKinds + CommentKinds + DirectiveKinds + CodeSkipKinds) and (T.Text <> '') then
          ACode.Add(LowerCase(T.Text));
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
    if Length(Result) > 40 then  // dl:ok large-magic-number@ea9c
      Result:= Copy(Result, 1, 40) + '...';  // dl:ok large-magic-number@9e1e
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

// True when S starts like an identifier, keyword or number token.
function IsWordToken(const S: string): Boolean;
begin
  Result:= (S <> '') and (CharInSet(S[1], ['a'..'z', 'A'..'Z', '0'..'9', '_', '$', '&']));
end;

// Copy of AList without ',' (and, when ADropDecl, without var/const).
function WithoutNoise(const AList: TList<string>; ADropDecl: Boolean): TList<string>;
var
  S: string;
begin
  Result:= TList<string>.Create;
  for S in AList do
    if (S <> ',') and not (ADropDecl and ((S = 'var') or (S = 'const'))) then
      Result.Add(S);
end;

// '' when the code-token stream of the output is acceptable for AMode; else a
// short decline cause. See TGuardCodeMode for the three rules.
function CodeStreamReason(const AOrig, AFmt: TList<string>; AMode: TGuardCodeMode): string;
var
  O     : TList<string>;
  F     : TList<string>;
  Seen  : THashSet<string>;
  Counts: TDictionary<string, Integer>;
  S     : string;
  i     : Integer;
begin
  Result:= '';
  if AMode = gcNone then
  begin
    // not compared
  end
  else if AMode = gcStrict then
  begin
    if not SameSequence(AOrig, AFmt) then
    begin
      i:= 0;
      while (i < AOrig.Count) and (i < AFmt.Count) and (AOrig[i] = AFmt[i]) do
        Inc(i);
      if i < AOrig.Count then
        Result:= 'code token reordered, lost or altered near: ' + AOrig[i]
      else
        Result:= 'code token duplicated or added: ' + AFmt[i];
    end;
  end
  else
  begin
    O     := WithoutNoise(AOrig, AMode = gcD10);
    F     := WithoutNoise(AFmt , AMode = gcD10);
    Seen  := THashSet<string>.Create;
    Counts:= TDictionary<string, Integer>.Create;
    try
      if AMode = gcD10 then
      begin
        // The hoist MOVES `name: Type` ahead of the statement it came from, so
        // order cannot be asserted; what must hold is that no original token
        // was lost (multiset containment, so a duplicate is tolerated).
        for S in F do
          if Counts.TryGetValue(S, i) then
            Counts[S]:= i + 1
          else
            Counts.Add(S, 1);
        for S in O do
          if Result = '' then
          begin
            if Counts.TryGetValue(S, i) and (i > 0) then
              Counts[S]:= i - 1
            else
              Result:= 'code token lost by the Delphi 10 transform: ' + S;
          end;
      end
      else if not IsSubsequence(O, F) then
        Result:= 'code token lost or reordered near: ' + FirstUnmatched(O, F)
      else
      begin
        for S in O do
          Seen.Add(S);
        for S in F do
          if (Result = '') and IsWordToken(S) and not Seen.Contains(S) then
            Result:= 'code token introduced by the split: ' + S;
      end;
    finally
      Counts.Free;
      Seen.Free;
      O.Free;
      F.Free;
    end;
  end;
end; // function

function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; out AReason: string): Boolean;
begin
  Result:= FormatPreservesContent(AOriginal, AFormatted, AAllowStringDuplication, AAllowLabelRemoval, gcNone, AReason);
end;

function FormatPreservesContent(const AOriginal, AFormatted: string; AAllowStringDuplication, AAllowLabelRemoval: Boolean; ACodeMode: TGuardCodeMode; out AReason: string): Boolean;
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
  OrigCod: TList<string>;
  FmtCod : TList<string>;
  StrOk  : Boolean      ;
  Marker : string       ;
begin
  AReason:= '';
  // A formatter-internal marker in the output that the input never had is a
  // shield that failed to restore -- decline before anything else. Checked on
  // the RAW text: the lexer-based streams below go through the same shield and
  // would be just as blind to it.
  for Marker in SHIELD_MARKERS do
    if (Pos(Marker, AFormatted) > 0) and (Pos(Marker, AOriginal) = 0) then
    begin
      AReason:= 'formatter shield marker leaked into the output: ' + Marker;
      Exit(False);
    end;
  OrigAsm:= TList<string>.Create;
  FmtAsm := TList<string>.Create;
  OrigCod:= TList<string>.Create;
  FmtCod := TList<string>.Create;
  OrigStr:= TList<string>.Create; FmtStr:= TList<string>.Create;
  OrigCom:= TList<string>.Create; FmtCom:= TList<string>.Create;
  OrigDir:= TList<string>.Create; FmtDir:= TList<string>.Create;
  OrigLbl:= TList<Boolean>.Create; FmtLbl:= TList<Boolean>.Create;
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
      // Directives stay STRICT even under duplication-tolerant mode: a
      // duplicated {$IFDEF}/{$ENDIF} inside a duplicated case arm would
      // unbalance conditional compilation -- that must decline.
      if AAllowStringDuplication then
        StrOk:= IsSubsequence(OrigStr, FmtStr)
      else
        StrOk:= SameSequence(OrigStr, FmtStr);
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
        AReason:= CodeStreamReason(OrigCod, FmtCod, ACodeMode);
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
    OrigStr.Free; FmtStr.Free;
    OrigCom.Free; FmtCom.Free;
    OrigDir.Free; FmtDir.Free;
    OrigLbl.Free; FmtLbl.Free;
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


