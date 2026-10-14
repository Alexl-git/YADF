{---------------------------------------------------------------------------
The contents of this file are subject to the Mozilla Public License Version
1.1 (the "License"); you may not use this file except in compliance with the
License. You may obtain a copy of the License at
http://www.mozilla.org/NPL/NPL-1_1Final.html

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for
the specific language governing rights and limitations under the License.

The Original Code is: mwPasLexTypes, released November 14, 1999.

The Initial Developer of the Original Code is Martin Waldenburg
unit CastaliaPasLexTypes;

----------------------------------------------------------------------------}

unit SimpleParser.Lexer.Types;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils,
  TypInfo;

{$INCLUDE SimpleParser.inc}

{$IFNDEF D14_NEWER}
type
  TArray<T> = array of T;
{$ENDIF}

var
  CompTable: array[#0..#255] of byte;

type
/// <summary></summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: TMessageEventType caller (DelphiAST.pas) ?, DelphiAST.TPasSyntaxTreeBuilder.ParserMessage (DelphiAST.pas) ?, TMessageEventType caller (SimpleParser.Lexer.Types.pas) ?
/// <!-- drag-lint:auto END -->
/// </remarks>
  TMessageEventType = (meError, meNotSupported);

  TMessageEvent = procedure(Sender: TObject; const Typ: TMessageEventType;
    const Msg: string; X, Y: Integer) of object;

/// <summary></summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: TCommentState caller (SimpleParser.Lexer.Types.pas) ?, TCommentState caller (SimpleParser.Lexer.pas) ?
/// <!-- drag-lint:auto END -->
/// </remarks>
  TCommentState = (csAnsi, csBor, csNo);

/// <summary></summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: TTokenPoint caller (DelphiAST.SimpleParserEx.pas) ?, DelphiAST.SimpleParserEx.TPasLexer.GetPosXY (DelphiAST.SimpleParserEx.pas) ?, DelphiAST.SimpleParserEx.TmwSimplePasParEx.TNameList.TNameItem.TNameItemToken.Create (DelphiAST.SimpleParserEx.pas) ?, DelphiAST.SimpleParserEx.TmwSimplePasParEx.TNameList.TNameItem.Create (DelphiAST.SimpleParserEx.pas) ?, DelphiAST.SimpleParserEx.TmwSimplePasParEx.TNameList.TNameItem.AddToken (DelphiAST.SimpleParserEx.pas) ? (+6 more)
/// Used in units: DelphiAST, DelphiAST.SimpleParserEx, SimpleParser, SimpleParser.Lexer
/// <!-- drag-lint:auto END -->
/// </remarks>
  TTokenPoint = packed record
    X: Integer;
    Y: Integer;
    LineSeq: Integer;
  end;

/// <summary></summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: TptTokenKind caller (DelphiAST.SimpleParserEx.pas) ?, DelphiAST.SimpleParserEx.TmwSimplePasParEx.TNameList.TNameItem.Create (DelphiAST.SimpleParserEx.pas) ?, DelphiAST.SimpleParserEx.TmwSimplePasParEx.TNameList.TNameItem.AddToken (DelphiAST.SimpleParserEx.pas) ?, TptTokenKind caller (SimpleParser.Lexer.Types.pas) ?, SimpleParser.Lexer.Types.ptTokenName (SimpleParser.Lexer.Types.pas) ? (+118 more)
/// <!-- drag-lint:auto END -->
/// </remarks>
  TptTokenKind = (
    ptAbort,
    ptAbsolute,
    ptAbstract,
    ptAdd,
    ptAddressOp,
    ptAlign,
    ptAmpersand,
    ptAnd,
    ptAnsiComment,
    ptAnsiString,
    ptArray,
    ptAs,
    ptAsciiChar,
    ptAsm,
    ptAssembler,
    ptAssign,
    ptAt,
    ptAutomated,
    ptBegin,
    ptBoolean,
    ptBorComment,
    ptBraceClose,
    ptBraceOpen,
    ptBreak,
    ptByte,
    ptByteBool,
    ptCardinal,
    ptCase,
    ptCdecl,
    ptChar,
    ptClass,
    ptClassForward,
    ptClassFunction,
    ptClassProcedure,
    ptColon,
    ptComma,
    ptComp,
    ptCompDirect,
    ptConst,
    ptConstructor,
    ptContains,
    ptContinue,
    ptCRLF,
    ptCRLFCo,
    ptCurrency,
    ptDefault,
    ptDefineDirect,
    ptDeprecated,
    ptDestructor,
    ptDispid,
    ptDispinterface,
    ptDiv,
    ptDo,
    ptDotDot,
    ptDouble,
    ptDoubleAddressOp,
    ptDownto,
    ptDWORD,
    ptDynamic,
    ptElse,
    ptElseDirect,
    ptEnd,
    ptEndIfDirect,
    ptEqual,
    ptError,
    ptExcept,
    ptExit,
    ptExport,
    ptExports,
    ptExtended,
    ptExternal,
    ptFar,
    ptFile,
    ptFinal,
    ptExperimental,
    ptDelayed,
    ptFinalization,
    ptFinally,
    ptFloat,
    ptFor,
    ptForward,
    ptFunction,
    ptGoto,
    ptGreater,
    ptGreaterEqual,
    ptHalt,
    ptHelper,
    ptIdentifier,
    ptIf,
    ptIfDirect,
    ptIfEndDirect,
    ptElseIfDirect,
    ptIfDefDirect,
    ptIfNDefDirect,
    ptIfOptDirect,
    ptImplementation,
    ptImplements,
    ptIn,
    ptIncludeDirect,
    ptIndex,
    ptInherited,
    ptInitialization,
    ptInline,
    ptInt64,
    ptInteger,
    ptIntegerConst,
    ptInterface,
    ptIs,
    ptLabel,
    ptLibrary,
    ptLocal,
    ptLongBool,
    ptLongint,
    ptLongword,
    ptLower,
    ptLowerEqual,
    ptMessage,
    ptMinus,
    ptMod,
    ptName,
    ptNear,
    ptNil,
    ptNodefault,
    ptNone,
    ptNoreturn,
    ptNot,
    ptNotEqual,
    ptNull,
    ptObject,
    ptOf,
    ptOleVariant,
    ptOn,
    ptOperator,
    ptOr,
    ptOut,
    ptOverload,
    ptOverride,
    ptPackage,
    ptPacked,
    ptPascal,
    ptPChar,
    ptPlatform,
    ptPlus,
    ptPoint,
    ptPointerSymbol,
    ptPrivate,
    ptProcedure,
    ptProgram,
    ptProperty,
    ptProtected,
    ptPublic,
    ptPublished,
    ptRaise,
    ptRead,
    ptReadonly,
    ptReal,
    ptReal48,
    ptRecord,
    ptReference,
    ptRegister,
    ptReintroduce,
    ptRemove,
    ptRepeat,
    ptRequires,
    ptResident,
    ptResourceDirect,
    ptResourcestring,
    ptRoundClose,
    ptRoundOpen,
    ptRunError,
    ptSafeCall,
    ptScopedEnumsDirect,
    ptSealed,
    ptSemiColon,
    ptSet,
    ptShl,
    ptShortint,
    ptShortString,
    ptShr,
    ptSingle,
    ptSlash,
    ptSlashesComment,
    ptSmallint,
    ptSpace,
    ptSquareClose,
    ptSquareOpen,
    ptStar,
    ptStatic,
    ptStdcall,
    ptStored,
    ptStrict,
    ptString,
    ptStringConst,
    ptStringDQConst,
    ptStringresource,
    ptSymbol,
    ptThen,
    ptThreadvar,
    ptTo,
    ptTry,
    ptType,
    ptUndefDirect,
    ptUnit,
    ptUnknown,
    ptUnsafe,
    ptUntil,
    ptUses,
    ptVar,
    ptVarargs,
    ptVariant,
    ptVirtual,
    ptWhile,
    ptWideChar,
    ptWideString,
    ptWith,
    ptWord,
    ptWordBool,
    ptWrite,
    ptWriteonly,
    ptXor);

  TmwPasLexStatus = record
    CommentState: TCommentState;
    ExID: TptTokenKind;
    LineNumber: Integer;
    LinePos: Integer;
    Origin: PChar;
    RunPos: Integer;
    TokenPos: Integer;
    TokenID: TptTokenKind;
  end;

  EIncludeError = class(Exception);
/// <summary></summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: IIncludeHandler caller (DelphiAST.ProjectIndexer.pas) ?, IIncludeHandler caller (DelphiAST.pas) ?, DelphiAST.TPasSyntaxTreeBuilder.Run (DelphiAST.pas) ?, IIncludeHandler caller (SimpleParser.Lexer.pas) ?, IIncludeHandler caller (SimpleParser.pas) ? (+2 more)
/// Used in units: DelphiAST, DelphiAST.ProjectIndexer, SimpleParser, SimpleParser.Lexer, uMainForm
/// <!-- drag-lint:auto END -->
/// </remarks>
  IIncludeHandler = interface
    ['{C5F20740-41D2-43E9-8321-7FE5E3AA83B6}']
/// <summary></summary>
/// <param name="ParentFileName"></param><!-- drag-lint:auto param -->
/// <param name="IncludeName"></param><!-- drag-lint:auto param -->
/// <param name="Content"></param><!-- drag-lint:auto param -->
/// <param name="FileName"></param><!-- drag-lint:auto param -->
/// <returns></returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: SimpleParser.Lexer.TmwBasePasLex.IncludeFile (SimpleParser.Lexer.pas)
/// <!-- drag-lint:auto END -->
/// </remarks>
    function GetIncludeFileContent(const ParentFileName, IncludeName: string;
      out Content: string; out FileName: string): Boolean;
  end;

/// <summary></summary>
/// <param name="Value"></param><!-- drag-lint:auto param -->
/// <returns>Observed: Copy(ptTokenName(Value), 3, MaxInt).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: SimpleParser.TmwSimplePasPar.Expected (SimpleParser.pas) ?, SimpleParser.TmwSimplePasPar.ExpectedEx (SimpleParser.pas) ?, SimpleParser.TmwSimplePasPar.ExpectedFatal (SimpleParser.pas) ?
/// Calls: Copy, SimpleParser.Lexer.Types.ptTokenName
/// <!-- drag-lint:auto END -->
/// </remarks>
function TokenName(Value: TptTokenKind): string;
/// <summary></summary>
/// <param name="Value"></param><!-- drag-lint:auto param -->
/// <returns>Observed: GetEnumName(TypeInfo(TptTokenKind), Integer(Value)).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: SimpleParser.Lexer.Types.TokenName (SimpleParser.Lexer.Types.pas)
/// Calls: GetEnumName, Integer, TypeInfo
/// <!-- drag-lint:auto END -->
/// </remarks>
function ptTokenName(Value: TptTokenKind): string;
/// <summary></summary>
/// <param name="aTokenID"></param><!-- drag-lint:auto param -->
/// <returns>Observed: aTokenID in [.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DelphiAST.SimpleParserEx.TmwSimplePasParEx.TNameList.TNameItem.AddToken (DelphiAST.SimpleParserEx.pas) ?, SimpleParser.Lexer.TmwBasePasLex.GetIsJunk (SimpleParser.Lexer.pas) ?
/// Covered by: TestBlockCommentLock, TestLenientIntRead, TestLineStartDepths, TestLooksLikeUtf8
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsTokenIDJunk(const aTokenID: TptTokenKind): Boolean;

implementation

function TokenName(Value: TptTokenKind): string;
begin
  Result := Copy(ptTokenName(Value), 3, MaxInt);
end;

function ptTokenName(Value: TptTokenKind): string;
begin
  result := GetEnumName(TypeInfo(TptTokenKind), Integer(Value));
end;

function IsTokenIDJunk(const aTokenID: TptTokenKind): Boolean;
begin
  Result := aTokenID in [
    ptAnsiComment,
    ptBorComment,
    ptCRLF,
    ptCRLFCo,
    ptSlashesComment,
    ptSpace,
    ptIfDirect,
    ptElseDirect,
    ptIfEndDirect,
    ptElseIfDirect,
    ptIfDefDirect,
    ptIfNDefDirect,
    ptEndIfDirect,
    ptIfOptDirect,
    ptDefineDirect,
    ptScopedEnumsDirect,
    ptUndefDirect];
end;

end.