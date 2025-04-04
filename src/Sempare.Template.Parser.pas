(*%*************************************************************************************************
 *                 ___                                                                              *
 *                / __|  ___   _ __    _ __   __ _   _ _   ___                                      *
 *                \__ \ / -_) | '  \  | '_ \ / _` | | '_| / -_)                                     *
 *                |___/ \___| |_|_|_| | .__/ \__,_| |_|   \___|                                     *
 *                                    |_|                                                           *
 ****************************************************************************************************
 *                                                                                                  *
 *                          Sempare Template Engine                                                 *
 *                                                                                                  *
 *                                                                                                  *
 *         https://github.com/sempare/sempare-delphi-template-engine                                *
 ****************************************************************************************************
 *                                                                                                  *
 * Copyright (c) 2019-2025 Sempare Limited                                                          *
 *                                                                                                  *
 * Contact: info@sempare.ltd                                                                        *
 *                                                                                                  *
 * Licensed under the Apache Version 2.0 or the Sempare Commercial License                          *
 * You may not use this file except in compliance with one of these Licenses.                       *
 * You may obtain a copy of the Licenses at                                                         *
 *                                                                                                  *
 * https://www.apache.org/licenses/LICENSE-2.0                                                      *
 * https://github.com/sempare/sempare-delphi-template-engine/blob/master/docs/commercial.license.md *
 *                                                                                                  *
 * Unless required by applicable law or agreed to in writing, software                              *
 * distributed under the Licenses is distributed on an "AS IS" BASIS,                               *
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.                         *
 * See the License for the specific language governing permissions and                              *
 * limitations under the License.                                                                   *
 *                                                                                                  *
 *************************************************************************************************%*)
unit Sempare.Template.Parser;

interface

{$I 'Sempare.Template.Compiler.inc'}

uses
  System.Classes,
  Sempare.Template.AST,
  Sempare.Template.Context;

type
  ETemplateParser = class(ETemplate);

  ITemplateParser = interface
    ['{DAF8A08D-9158-4D2C-9E76-BE80E9DA50A3}']
    function Parse(const AStream: TStream; const AManagedStream: boolean = true): ITemplate;
  end;

function CreateTemplateParser(const AContext: ITemplateContext): ITemplateParser;

implementation

uses
  System.SysUtils,
  System.Rtti,
  System.Generics.Collections,
  Sempare.Template,
  Sempare.Template.PrettyPrint,
  Sempare.Template.BlockResolver,
  Sempare.Template.ResourceStrings,
  Sempare.Template.Common,
  Sempare.Template.Lexer,
  Sempare.Template.Rtti,
  Sempare.Template.Util;

type

  TTemplate = class(TInterfacedObject, ITemplate, ITemplateAdd, ITemplateVisitorHost)
  private
    FPosition: IPosition;
    FArray: TList<IStmt>;

    procedure FlattenTemplate;
    procedure OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string);
    function GetFilename: string;
    procedure SetFilename(const AFilename: string);
    function GetLine: integer;
    procedure SetLine(const Aline: integer);
    function GetPos: integer;
    procedure SetPos(const Apos: integer);
    function GetItem(const AOffset: integer): IStmt;
    function GetCount: integer;

    procedure Add(const AItem: IStmt; const AAddLocation: TAddLocation = alLast);
    function GetLastItem: IStmt;
    procedure Accept(const AVisitor: ITemplateVisitor);

  public
    constructor Create;
    destructor Destroy; override;
  end;

  TDebugStmt = class(TAbstractStmt, IDebugStmt)
  private
    FStmt: IStmt;
    function GetStmt: IStmt;
  public
    constructor Create(const AStmt: IStmt);
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TEndStmt = class(TAbstractStmt, IEndStmt)
  public
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TExtendsStmt = class(TAbstractStmt, IExtendsStmt)
  private
    FName: IExpr;
    FBlockContainer: ITemplate;
    function GetName: IExpr;
    function GetBlockContainer: ITemplate;
    function NameAsString(const AEvalVisitor: IEvaluationTemplateVisitor): string;
    function GetHasEnd: boolean; override;
  protected
    procedure OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string); override;
  public
    constructor Create(const APosition: IPosition; const AName: IExpr; const ABlockContainer: ITemplate);
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TBlockStmt = class(TAbstractStmt, IBlockStmt)
  private
    FName: IExpr;
    FContainer: ITemplate;
    function GetName: IExpr;
    function GetContainer: ITemplate;
    function NameAsString(const AEvalVisitor: IEvaluationTemplateVisitor): string;
    function GetHasEnd: boolean; override;
  protected
    procedure OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string); override;
  public
    constructor Create(const APosition: IPosition; const AName: IExpr; const AContainer: ITemplate);
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TElseStmt = class(TAbstractStmt, IElseStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TNoopStmt = class(TAbstractStmt, INoopStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TContinueStmt = class(TAbstractStmt, IContinueStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TBreakStmt = class(TAbstractStmt, IBreakStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TCommentStmt = class(TAbstractStmt, ICommentStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TElIfStmt = class(TAbstractStmt, IElIfStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TAbstractStmtWithExpr = class abstract(TAbstractStmt)
  private
    FExpr: IExpr;
    function GetExpr: IExpr;
  public
    constructor Create(const APosition: IPosition; const AExpr: IExpr);
  end;

  TPrintStmt = class(TAbstractStmtWithExpr, IPrintStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TStripStmt = class(TAbstractStmt, IStripStmt)
  private
    FDirection: TStripDirection;
    FAction: TStripActionSet;
    FHasEnd: boolean;
    FIndent: string;
    function GetIndent: string;
    procedure SetIndent(const AIndent: string);
    function GetDirection: TStripDirection;
    function GetAction: TStripActionSet;
    function GetHasEnd: boolean; override;
    procedure SetHasEnd(const AHasEnd: boolean);
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const ADirection: TStripDirection; const AAction: TStripActionSet);
  end;

  TCompositeStmt = class(TAbstractStmt, ICompositeStmt)
  private
    FFirstStmt: IStmt;
    FSecondStmt: IStmt;
    function GetFirstStmt: IStmt;
    function GetSecondStmt: IStmt;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
    function Flatten: TArray<IStmt>; override;
  public
    constructor Create(const AFirstStmt, ASecondStmt: IStmt);
  end;

  TIncludeStmt = class(TAbstractStmtWithExpr, IIncludeStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TRequireStmt = class(TAbstractStmt, IRequireStmt)
  private
    FExprList: IExprList;
    function GetExprList: IExprList;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AExprList: IExprList);
  end;

  TIfStmt = class(TAbstractStmt, IIfStmt)
  private
    FCondition: IExpr;
    FTrueContainer: ITemplate;
    FFalseContainer: ITemplate;
    function GetCondition: IExpr;
    function GetTrueContainer: ITemplate;
    function GetFalseContainer: ITemplate;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
    function GetHasEnd: boolean; override;
  protected
    procedure OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string); override;
  public
    constructor Create(const APosition: IPosition; const ACondition: IExpr; const ATrueContainer: ITemplate; const AFalseContainer: ITemplate);
  end;

  TAbstractStmtWithContainer = class abstract(TAbstractStmt)
  private
    FContainer: ITemplate;
    function GetContainer: ITemplate;
  protected
    procedure OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string); override;
  public
    constructor Create(const APosition: IPosition; const AContainer: ITemplate);
  end;

  TProcessTemplateStmt = class(TAbstractStmtWithContainer, IProcessTemplateStmt)
  private
    FAllowNewline: boolean;
    function GetAllowNewLine: boolean;
    procedure SetAllowNewLine(const AAllow: boolean);
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AContainer: ITemplate; const AAllowNewLine: boolean = true);
  end;

  TDefineTemplateStmt = class(TAbstractStmtWithContainer, IDefineTemplateStmt)
  private
    FName: IExpr;
    function GetName: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
    function GetHasEnd: boolean; override;
  public
    constructor Create(const APosition: IPosition; const AName: IExpr; const AContainer: ITemplate);
  end;

  TWithStmt = class(TAbstractStmtWithContainer, IWithStmt)
  private
    FExpr: IExpr;
    function GetExpr: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
    function GetHasEnd: boolean; override;
  public
    constructor Create(const APosition: IPosition; const AExpr: IExpr; const AContainer: ITemplate);
  end;

  TIgnoreNLStmt = class(TAbstractStmtWithContainer, IIgnoreNLStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
    function GetHasEnd: boolean; override;
  public
    constructor Create(const APosition: IPosition; const AContainer: ITemplate);
  end;

  TIgnoreWSStmt = class(TAbstractStmtWithContainer, IIgnoreWSStmt)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
    function GetHasEnd: boolean; override;
  public
    constructor Create(const APosition: IPosition; const AContainer: ITemplate);
  end;

  TLoopStmt = class(TAbstractStmtWithContainer, ILoopStmt)
  protected
    FOnBegin: ITemplate;
    FOnEnd: ITemplate;
    FOnEmpty: ITemplate;
    FBetweenItem: ITemplate;

    function GetOnBeginContainer: ITemplate;
    function GetOnEndContainer: ITemplate;
    function GetOnEmptyContainer: ITemplate;
    function GetBetweenItemContainer: ITemplate;
    function GetHasEnd: boolean; override;
    procedure OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string); override;
  public
    constructor Create(const APosition: IPosition; const AContainer: ITemplate; const AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
  end;

  TWhileStmt = class(TLoopStmt, IWhileStmt)
  private
    FCondition: IExpr;
    FOffsetExpr: IExpr;
    FLimitExpr: IExpr;
    function GetCondition: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
    function GetOffsetExpr: IExpr;
    function GetLimitExpr: IExpr;
  public
    constructor Create(const APosition: IPosition; const ACondition: IExpr; const AOffsetExpr: IExpr; const ALimitExpr: IExpr; const AContainer: ITemplate; const AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
  end;

  TForInStmt = class(TLoopStmt, IForInStmt)
  private
    FVariable: string;
    FForOp: TForOp;
    FExpr: IExpr;
    FOffsetExpr: IExpr;
    FLimitExpr: IExpr;
    function GetVariable: string;
    function GetForOp: TForOp;
    function GetExpr: IExpr;
    function GetOffsetExpr: IExpr;
    function GetLimitExpr: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AVariable: string; const AForOp: TForOp; const AExpr: IExpr; const AOffsetExpr: IExpr; const ALimitExpr: IExpr; const AContainer: ITemplate; const AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
  end;

  TForRangeStmt = class(TLoopStmt, IForRangeStmt)
  private
    FVariable: string;
    FForOp: TForOp;
    FLowExpr: IExpr;
    FHighExpr: IExpr;
    FStepExpr: IExpr;
    function GetVariable: string;
    function GetForOp: TForOp;
    function GetLowExpr: IExpr;
    function GetHighExpr: IExpr;
    function GetStepExpr: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AVariable: string; const AForOp: TForOp; const ALowExpr: IExpr; const AHighExpr: IExpr; const AStep: IExpr; const AContainer: ITemplate; const AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
  end;

  TAssignStmt = class(TAbstractStmtWithExpr, IAssignStmt)
  private
    FVariable: string;
    function GetVariable: string;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AVariable: string; const AExpr: IExpr);
  end;

  TCycleStmt = class(TAbstractStmt, ICycleStmt)
  private
    FExprList: IExprList;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AList: IExprList);
    function GetList: IExprList;
  end;

  TExprList = class(TAbstractBase, IExprList)
  private
    FExprs: TArray<IExpr>;
    function GetExpr(const AOffset: integer): IExpr;
    procedure AddExpr(const AExpr: IExpr);
    function GetExprCount: integer;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TValueExpr = class(TAbstractExpr, IValueExpr)
  private
    FValue: TValue;
    function GetValue: TValue;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AValue: TValue);
  end;

  TNewLineExpr = class(TValueExpr, INewLineExpr)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AValue: TValue);
  end;

  TWhitespaceExpr = class(TValueExpr, IWhitespaceExpr)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AValue: TValue);
  end;

  TAbstractExprWithExprList = class abstract(TAbstractExpr)
  private
    FExprList: IExprList;
    function GetExprList: IExprList;
  public
    constructor Create(const APosition: IPosition; AExprList: IExprList);
  end;

  TAbstractExprWithExpr = class abstract(TAbstractExpr)
  private
    FExpr: IExpr;
    function GetExpr: IExpr;
  public
    constructor Create(const APosition: IPosition; const AExpr: IExpr);
  end;

  TArrayExpr = class(TAbstractExprWithExprList, IArrayExpr)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TVariableExpr = class(TAbstractExpr, IVariableExpr)
  private
    FVariable: string;
    function GetVariable: string;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AVariable: string);
  end;

  TEncodeExpr = class(TAbstractExprWithExpr, IEncodeExpr)
  private
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  end;

  TVariableDerefExpr = class(TAbstractExprWithExpr, IVariableDerefExpr)
  private
    FDeref: IExpr;
    FDerefType: TDerefType;
    function GetDerefType: TDerefType;
    function GetDerefExpr: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const ADerefType: TDerefType; const AVariable: IExpr; const ADeref: IExpr);
  end;

  TFunctionCallExpr = class(TAbstractExprWithExprList, IFunctionCallExpr)
  private
    FFunctionInfo: TArray<TRttiMethod>;
    function GetFunctionInfo: TArray<TRttiMethod>;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AFunction: TArray<TRttiMethod>; const ExprList: IExprList);
  end;

  TMethodCallExpr = class(TAbstractExprWithExprList, IMethodCallExpr)
  private
    FObjectExpr: IExpr;
    FMethod: string;
    function GetMethod: string;
    function GetObject: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AObjectExpr: IExpr; const AMethod: string; const AExprList: IExprList);
  end;

  TBinopExpr = class(TAbstractExpr, IBinopExpr)
  private
    FLeft: IExpr;
    FBinop: TBinOp;
    FRight: IExpr;
    function GetBinOp: TBinOp;
    function GetLeftExpr: IExpr;
    function GetRightExpr: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const ALeft: IExpr; const ABinop: TBinOp; const ARight: IExpr);
    destructor Destroy; override;
  end;

  TTernaryExpr = class(TAbstractExprWithExpr, ITernaryExpr)
  private
    FTrueExpr: IExpr;
    FFalseExpr: IExpr;
    function GetTrueExpr: IExpr;
    function GetFalseExpr: IExpr;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const ACondition: IExpr; const ATrueExpr: IExpr; const AFalseExpr: IExpr);
  end;

  TUnaryExpr = class(TAbstractExprWithExpr, IUnaryExpr)
  private
    FUnaryOp: TUnaryOp;
    function GetUnaryOp: TUnaryOp;
    procedure Accept(const AVisitor: ITemplateVisitor); override;
  public
    constructor Create(const APosition: IPosition; const AUnaryOp: TUnaryOp; const ACondition: IExpr);
  end;

  EEndOfBlock = class(ETemplate);

  TTemplateSymbolSet = set of TTemplateSymbol;

  TTemplateParser = class(TInterfacedObject, ITemplateParser)
  private
    FContext: ITemplateContext;
    FSemiColon: ITemplateSymbol;
    FLookahead: ITemplateSymbol;
    FLexer: ITemplateLexer;
    FContainerStack: TStack<ITemplate>;
    FOptions: TParserOptions;

    FBeforeStartScriptStripActions: TStripActionSet;
    FLoopStripActions: TStripActionSet;

    function PushContainer(const ABeforeNLStripActions: TStripActionSet): ITemplate;
    function PopContainer: ITemplate;

    function CurrentContainer: ITemplate;
    function LookaheadValue: string;

    function MatchValues(const ASymbols: TTemplateSymbolSet; out ASymbol: TTemplateSymbol): string;
    function MatchValue(const ASymbol: TTemplateSymbol): string;
    procedure Match(const ASymbol: ITemplateSymbol); overload; inline;
    function Match(ASymbols: TTemplateSymbolSet; var AMatchSymbol: TTemplateSymbol): TStripActionSet; overload; inline;
    function MatchEndOfScript: TStripActionSet;
    function Match(const ASymbol: TTemplateSymbol): TStripActionSet; overload;
    function MatchNumber(const ASymbol: TTemplateSymbol): extended;
    procedure MatchClosingBracket(const AExpect: TTemplateSymbol);

    function AddStripStmtFront(const AStmt: IStmt; const AStripActions: TStripActionSet; const ADirection: TStripDirection): IStmt; overload;
    function AddStripStmtEnd(const AStmt: IStmt; const AStripActions: TStripActionSet; const ADirection: TStripDirection): IStmt; overload;
    function AddStripStmtFront(const ATemplate: ITemplate; const AStripActions: TStripActionSet; const ADirection: TStripDirection): ITemplate; overload;
    function AddStripStmtEnd(const ATemplate: ITemplate; const AStripActions: TStripActionSet; const ADirection: TStripDirection): ITemplate; overload;

    function WrapWithStripStmt(const AStmt: IStmt; const ABeforeScript: TStripActionSet): IStmt; overload;
    function WrapWithStripStmt(const ATemplate: ITemplate; const ABeforeScript: TStripActionSet): ITemplate; overload;

    procedure AddStmt(const ATemplate: ITemplate; const AStmt: IStmt);
    function GetValueSeparatorSymbol: TTemplateSymbol;

  private
    // helper rules
    function RuleIgnoreOption(const ASymbol: TTemplateSymbol; const AOption: TParserOption): IStmt;
    function RuleExprList(const AEndToken: TTemplateSymbol = vsCloseRoundBracket): IExprList;
    function RuleElIfStmt(out AFalseContainer: ITemplate; const ABeforeStmtStripActions: TStripActionSet): IStmt;
    function RulePrintStmtVariable(const AExpr: IExpr): IStmt; overload;
    function RuleAssignStmt(const ASymbol: IExpr): IStmt;
    function RuleEndStmt: IStmt;
  private
    function RuleStmts(const Container: ITemplate; const AEndToken: TTemplateSymbolSet): TTemplateSymbol;
    function RuleStmt: IStmt;

    function RuleIgnoreNewline: IStmt;
    function RuleIgnoreWhitespace: IStmt;
    function RuleCommentStmt: IStmt;
    function RuleIdStmt: IStmt;
    function RuleExprStmt: IStmt;
    function RuleIncludeStmt: IStmt; overload;
    function RuleIncludeStmt(const AName: IExpr): IStmt; overload;
    function RulePrintStmt: IStmt;
    function RuleContinueStmt: IStmt;
    function RuleBreakStmt: IStmt;
    function RuleIfStmt: IStmt;
    function RuleForStmt: IStmt;
    function RuleWhileStmt: IStmt;
    function RuleWithStmt: IStmt;
    function RuleCycleStmt: IStmt;
    function RuleTemplateStmt: IStmt;
    function RuleBlockStmt: IStmt;
    function RuleExtendsStmt: IStmt;
    function RuleRequireStmt: IStmt;
    function RuleNoopStmt: IStmt;
    function RuleMapExpr: IExpr;
    function RuleExprMap: IExpr;
    function RuleExpression: IExpr;
    function RuleSimpleExpression: IExpr;
    function RuleTerm: IExpr;
    function RuleSignedFactor: IExpr;
    function RuleFactor: IExpr;
    function RuleVariable: IExpr;
    function RuleFunctionExpr(const ASymbol: string): IExpr;
    function RuleMethodExpr(const AExpr: IExpr; const AMethodExpr: IExpr): IExpr;

  public
    constructor Create(const AContext: ITemplateContext);
    destructor Destroy; override;
    function Parse(const AStream: TStream; const AManagedStream: boolean): ITemplate;
  end;

function TrailingStripActions(const AActions: TStripActionSet): TStripActionSet;
begin
  if AActions = [] then
    exit([]);
  if TStripAction.saWhitespace in AActions then
    exit([saWhitespace, saNL])
  else
    exit([saWhitespace]);
end;

function IsPrintNLOrWhitespaceExpr(const AStmt: IStmt; out ANL: boolean): boolean;
var
  LDebugStmt: IDebugStmt;
  LPrintStmt: IPrintStmt;
  LExpr: IExpr;
begin
  if supports(AStmt, IDebugStmt, LDebugStmt) then
  begin
    exit(IsPrintNLOrWhitespaceExpr(LDebugStmt.Stmt, ANL));
  end;

  if not supports(AStmt, IPrintStmt, LPrintStmt) then
    exit(false);

  LExpr := LPrintStmt.Expr;
  if supports(LExpr, INewLineExpr) then
  begin
    ANL := true;
    exit(true);
  end;
  if supports(LExpr, IWhitespaceExpr) then
  begin
    ANL := false;
    exit(true);
  end;
  exit(false);
end;

function IsPrintTextExpr(const AStmt: IStmt; out AStr: string): boolean;
var
  LDebugStmt: IDebugStmt;
  LPrintStmt: IPrintStmt;
  LVal: IValueExpr;
begin
  if supports(AStmt, IDebugStmt, LDebugStmt) then
  begin
    exit(IsPrintTextExpr(LDebugStmt.Stmt, AStr));
  end;

  if not supports(AStmt, IPrintStmt, LPrintStmt) then
    exit(false);
  if supports(LPrintStmt.Expr, IValueExpr, LVal) and isStrLike(LVal.Value) then
  begin
    AStr := LVal.Value.asString;
    exit(true);
  end;
  exit(false);
end;

function IsStripStmt(const AStmt: IStmt; out AStripStmt: IStripStmt): boolean;
var
  LDebugStmt: IDebugStmt;
begin
  if supports(AStmt, IDebugStmt, LDebugStmt) then
  begin
    exit(IsStripStmt(LDebugStmt.Stmt, AStripStmt));
  end;
  exit(supports(AStmt, IStripStmt, AStripStmt));
end;

function IsAny(const AStmt: IStmt; const AGuids: array of TGuid): boolean;
var
  LGuid: TGuid;
begin
  for LGuid in AGuids do
  begin
    if supports(AStmt, LGuid) then
      exit(true);
  end;
  exit(false);
end;

function IsPrintExpr(const AStmt: IStmt; const ASymExpr: TGuid): boolean;
var
  LDebugStmt: IDebugStmt;
  LPrintStmt: IPrintStmt;
begin
  if supports(AStmt, IDebugStmt, LDebugStmt) then
  begin
    exit(IsPrintExpr(LDebugStmt.Stmt, ASymExpr));
  end;
  if not supports(AStmt, IPrintStmt, LPrintStmt) then
    exit(false);

  exit(supports(LPrintStmt.Expr, ASymExpr));
end;

function IsPrintWhitespaceExpr(const AStmt: IStmt): boolean;
begin
  exit(IsPrintExpr(AStmt, IWhitespaceExpr));
end;

function IsPrintNewlineExpr(const AStmt: IStmt): boolean;
begin
  exit(IsPrintExpr(AStmt, INewLineExpr));
end;

function IsNLorWSStmt(const AStmt: IStmt; out AIsWS: boolean): boolean;
var
  LDebugStmt: IDebugStmt;
  LPrintStmt: IPrintStmt;
begin
  if supports(AStmt, IDebugStmt, LDebugStmt) then
  begin
    exit(IsNLorWSStmt(LDebugStmt.Stmt, AIsWS));
  end;
  if not supports(AStmt, IPrintStmt, LPrintStmt) then
    exit(false);
  AIsWS := supports(LPrintStmt.Expr, IWhitespaceExpr);
  exit(AIsWS or supports(LPrintStmt.Expr, INewLineExpr));
end;

function Flatten(const AStmts: TList<IStmt>): TArray<IStmt>;
var
  LStmt: IStmt;
  LFlattenedStmts: TList<IStmt>;
begin
  LFlattenedStmts := TList<IStmt>.Create;
  try
    for LStmt in AStmts do
    begin
      LFlattenedStmts.AddRange(LStmt.Flatten);
    end;
    exit(LFlattenedStmts.ToArray);
  finally
    LFlattenedStmts.Free;
  end;
end;

function CreateTemplateParser(const AContext: ITemplateContext): ITemplateParser;
begin
  exit(TTemplateParser.Create(AContext));
end;

function IsValue(const AExpr: IExpr): boolean;
begin
  exit(supports(AExpr, IValueExpr));
end;

function AsValue(const AExpr: IExpr): TValue;
var
  LValueExpr: IValueExpr;
begin
  LValueExpr := AExpr as IValueExpr;
  exit(LValueExpr.Value);
end;

function AsVarString(const AExpr: IExpr): string;
var
  LVar: IVariableExpr;
begin
  if supports(AExpr, IVariableExpr, LVar) then
    exit(LVar.Variable)
  else
    exit('');
end;

function IsEnd(const AStmt: IStmt): boolean;
begin
  if AStmt = nil then
    exit(false);
  exit(supports(AStmt, IEndStmt));
end;

function TemplateForop(const APosition: IPosition; const ASymbol: TTemplateSymbol): TForOp;
begin
  result := foTo;
  case ASymbol of
    vsTo:
      exit;
    vsDownto:
      exit(foDownto);
    vsIn:
      exit(foIn);
    vsOf:
      exit(foOf);
  else
    RaiseErrorRes(APosition, @SForOpNotSupported, [TemplateSymbolToString(ASymbol)]);
  end;
end;

var
  GTemplateBinOps: array [TTemplateSymbol] of TBinOp;

function TemplateBinop(const ASymbol: TTemplateSymbol; out BinOp: TBinOp): boolean;

begin
  BinOp := GTemplateBinOps[ASymbol];
  exit(BinOp <> boInvalid);
end;

function GetTemplateParser(const AContext: ITemplateContext): ITemplateParser;
begin
  exit(TTemplateParser.Create(AContext));
end;

{ TTemplateParser }
const
  ValueSeparators = [vsComma, vsSemiColon];

function OppositeValueSepartor(const ASep: TTemplateSymbol): TTemplateSymbol;
begin
  if ASep = vsComma then
    exit(vsSemiColon)
  else
    exit(vsComma);
end;

function TTemplateParser.GetValueSeparatorSymbol: TTemplateSymbol;
begin
  if FContext.ValueSeparator = ';' then
    exit(vsSemiColon)
  else
    exit(vsComma);
end;

procedure TTemplateParser.MatchClosingBracket(const AExpect: TTemplateSymbol);
begin
  if AExpect = vsCloseCurlyBracket then
  begin
    assert(AExpect in [vsCloseRoundBracket, vsCloseSquareBracket, vsCloseCurlyBracket]);
  end
  else
  begin
    assert(AExpect in [vsCloseRoundBracket, vsCloseSquareBracket]);

  end;
  if FLookahead.Token in ValueSeparators then
    Match(OppositeValueSepartor(FLookahead.Token));
  Match(AExpect);
end;

function TTemplateParser.MatchEndOfScript: TStripActionSet;
var
  LSym: TTemplateSymbol;
begin
  LSym := vsEndScript;
  result := Match([vsEndScript, vsSemiColon], LSym);
  if LSym = vsEndScript then
  begin
    FSemiColon := nil;
  end;
end;

procedure TTemplateParser.AddStmt(const ATemplate: ITemplate; const AStmt: IStmt);
var
  LAdd: ITemplateAdd;
begin
  if supports(ATemplate, ITemplateAdd, LAdd) then
    LAdd.Add(AStmt);
end;

function TTemplateParser.AddStripStmtEnd(const ATemplate: ITemplate; const AStripActions: TStripActionSet; const ADirection: TStripDirection): ITemplate;
var
  LAdd: ITemplateAdd;
  LStmt: IStripStmt;
begin
  if AStripActions = [] then
    exit(ATemplate);
  result := ATemplate;
  LStmt := TStripStmt.Create(ADirection, AStripActions);

  if supports(ATemplate, ITemplateAdd, LAdd) then
    LAdd.Add(LStmt, TAddLocation.alLast);
end;

function TTemplateParser.AddStripStmtEnd(const AStmt: IStmt; const AStripActions: TStripActionSet; const ADirection: TStripDirection): IStmt;
var
  LStripStmt: IStripStmt;
begin
  if AStripActions = [] then
    exit(AStmt);

  LStripStmt := TStripStmt.Create(ADirection, AStripActions);
  if AStmt = nil then
    exit(LStripStmt);
  LStripStmt.HasEnd := AStmt.HasEnd;

  exit(TCompositeStmt.Create(AStmt, LStripStmt));
end;

function TTemplateParser.AddStripStmtFront(const AStmt: IStmt; const AStripActions: TStripActionSet; const ADirection: TStripDirection): IStmt;
var
  LStripStmt: IStripStmt;
begin
  if AStripActions = [] then
    exit(AStmt);

  LStripStmt := TStripStmt.Create(ADirection, AStripActions);
  if AStmt = nil then
    exit(LStripStmt);
  LStripStmt.HasEnd := AStmt.HasEnd;

  exit(TCompositeStmt.Create(LStripStmt, AStmt));
end;

constructor TTemplateParser.Create(const AContext: ITemplateContext);
begin
  FOptions := [];
  FContext := AContext;
  FContainerStack := TStack<ITemplate>.Create;
end;

function TTemplateParser.RuleIfStmt: IStmt;
var
  LConditionalExpr: IExpr;
  LTrueContainer: ITemplate;
  LFalseContainer: ITemplate;
  LLastContainer: ITemplate;
  LLastElifContainer: ITemplate;
  LOptions: TParserOptions;
  LSymbol: ITemplateSymbol;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LOptions := FOptions;
  FOptions := FOptions + [poAllowElse, poAllowEnd, poAllowElIf];
  try
    LSymbol := FLookahead;

    LBeforeStmtStripActions := Match(vsIF);

    LConditionalExpr := RuleExpression;
    MatchEndOfScript;

    LTrueContainer := PushContainer(LBeforeStmtStripActions);

    RuleStmts(LTrueContainer, [vsELIF, vsElse, vsEND]);

    PopContainer;

    LFalseContainer := PushContainer(LBeforeStmtStripActions);
    LLastContainer := LFalseContainer;

    if FLookahead.Token = vsELIF then
    begin
      while (FLookahead.Token = vsELIF) do
      begin
        AddStmt(LLastContainer, RuleElIfStmt(LLastElifContainer, LBeforeStmtStripActions));
        LLastContainer := LLastElifContainer;
      end;
    end
    else if FLookahead.Token = vsElse then
    begin
      Match(vsElse);
      MatchEndOfScript;

      RuleStmts(LFalseContainer, [vsEND]);
    end;
    PopContainer;

    Match(vsEND);
    MatchEndOfScript;

    if assigned(LTrueContainer) and (LTrueContainer.Count = 0) then
      LTrueContainer := nil;

    if assigned(LFalseContainer) and (LFalseContainer.Count = 0) then
      LFalseContainer := nil;

    if not assigned(LTrueContainer) and not assigned(LFalseContainer) then
      exit(nil);

    LTrueContainer := WrapWithStripStmt(LTrueContainer, LBeforeStmtStripActions);
    LFalseContainer := WrapWithStripStmt(LFalseContainer, LBeforeStmtStripActions);

    try

      if (eoEvalEarly in FContext.Options) and IsValue(LConditionalExpr) then
      begin
        if AsBoolean(AsValue(LConditionalExpr)) then
          exit(TProcessTemplateStmt.Create(LSymbol.Position, LTrueContainer))
        else if LFalseContainer <> nil then
          exit(TProcessTemplateStmt.Create(LSymbol.Position, LFalseContainer))
      end;
      exit(TIfStmt.Create(LSymbol.Position, LConditionalExpr, LTrueContainer, LFalseContainer));

    finally
      result := WrapWithStripStmt(result, LBeforeStmtStripActions);
    end;

  finally
    FOptions := LOptions;
  end;
end;

function TTemplateParser.RuleIgnoreOption(const ASymbol: TTemplateSymbol; const AOption: TParserOption): IStmt;
var
  LSymbol: ITemplateSymbol;
  LContainerTemplate: ITemplate;
  LOptions: TParserOptions;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LOptions := FOptions;
  FOptions := FOptions + [poAllowEnd, AOption];
  try
    LSymbol := FLookahead;

    LBeforeStmtStripActions := Match(ASymbol);
    MatchEndOfScript;

    LContainerTemplate := PushContainer(LBeforeStmtStripActions);

    RuleStmts(LContainerTemplate, [vsEND]);

    PopContainer;

    Match(vsEND);
    MatchEndOfScript;

    LContainerTemplate := WrapWithStripStmt(LContainerTemplate, LBeforeStmtStripActions);

    case AOption of
      poStripNL:
        result := TIgnoreNLStmt.Create(LSymbol.Position, LContainerTemplate);
      poStripws:
        result := TIgnoreWSStmt.Create(LSymbol.Position, LContainerTemplate);
    end;

    exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
  finally
    FOptions := LOptions;
  end;
end;

function TTemplateParser.RuleIgnoreNewline: IStmt;
begin
  exit(RuleIgnoreOption(vsIgnoreNL, poStripNL));
end;

function TTemplateParser.RuleIgnoreWhitespace: IStmt;
begin
  exit(RuleIgnoreOption(vsIgnoreWS, poStripws));
end;

function TTemplateParser.RuleIncludeStmt(const AName: IExpr): IStmt;
var
  LSymbol: ITemplateSymbol;
  LIncludeExpr: IExpr;
  LScopeExpr: IExpr;
  LContainerTemplate: TTemplate;
  LMatchBracket: boolean;
  LVarExpr: IVariableExpr;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LVarExpr := AName as IVariableExpr;
  LIncludeExpr := TValueExpr.Create(AName, LVarExpr.Variable);
  LSymbol := FLookahead;

  LBeforeStmtStripActions := FBeforeStartScriptStripActions;

  LMatchBracket := false;
  if FLookahead.Token = vsOpenCurlyBracket then
  begin
    Match(vsOpenCurlyBracket);
    LMatchBracket := true;
  end;

  if FLookahead.Token in [vsID, vsString] then
  begin
    LScopeExpr := RuleExprMap;
  end;

  if LMatchBracket then
    MatchClosingBracket(vsCloseCurlyBracket);

  result := TIncludeStmt.Create(LSymbol.Position, LIncludeExpr);

  if LScopeExpr <> nil then
  begin
    LContainerTemplate := TTemplate.Create();
    LContainerTemplate.Add(result);
    result := TWithStmt.Create(LSymbol.Position, LScopeExpr, LContainerTemplate);
  end;
end;

function TTemplateParser.RuleIncludeStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LIncludeExpr: IExpr;
  LScopeExpr: IExpr;
  LContainerTemplate: TTemplate;
  LValueSeparator: TTemplateSymbol;
  LBeforeStmtStripActions: TStripActionSet;
  LMatchBracket: boolean;
begin
  LSymbol := FLookahead;

  LBeforeStmtStripActions := Match(vsInclude);

  LMatchBracket := false;
  if FLookahead.Token = vsOpenRoundBracket then
  begin
    Match(vsOpenRoundBracket);
    LMatchBracket := true;
  end;

  LIncludeExpr := RuleExpression;
  LValueSeparator := GetValueSeparatorSymbol;
  if FLookahead.Token = LValueSeparator then
  begin
    Match(LValueSeparator);
    LScopeExpr := RuleExpression;
  end;

  if LMatchBracket then
    MatchClosingBracket(vsCloseRoundBracket);

  MatchEndOfScript;

  result := TIncludeStmt.Create(LSymbol.Position, LIncludeExpr);

  if LScopeExpr <> nil then
  begin
    LContainerTemplate := TTemplate.Create();
    LContainerTemplate.Add(result);
    result := TWithStmt.Create(LSymbol.Position, LScopeExpr, LContainerTemplate);
  end;

  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RuleMapExpr: IExpr;

function ParseMap: TMap; forward;
function ParseExpr: TValue; forward;

  function ParseArray: TArray<TValue>;
  var
    LSymbol: ITemplateSymbol;
    i: integer;
  begin
    i := 0;
    result := nil;
    LSymbol := FLookahead;
    Match(vsOpenSquareBracket);
    while FLookahead.Token <> vsCloseSquareBracket do
    begin
      if i > 0 then
      begin
        Match(vsComma);
      end;
      SetLength(result, length(result) + 1);
      result[high(result)] := ParseExpr;
      inc(i);
    end;
    Match(vsCloseSquareBracket);
  end;

  function ParseExpr: TValue;
  var
    LSymbol: ITemplateSymbol;
    LValue: TValue;
    LArr: TArray<TValue>;
  begin
    LSymbol := FLookahead;
    case LSymbol.Token of
      vsString:
        exit(MatchValue(vsString));
      vsNumber:
        exit(MatchNumber(vsNumber));
      vsBoolean:
        exit(MatchValue(vsBoolean) = 'true');
      vsOpenSquareBracket:
        begin
          LArr := ParseArray;
          LValue := TValue.From < TArray < TValue >> (LArr);
          exit(LValue);
        end;
      vsOpenCurlyBracket:
        begin
          exit(TValue.From<TMap>(ParseMap));
        end;
    end;
  end;

  function ParseMap: TMap;
  var
    LKey: string;
    i: integer;
    LValue: TValue;
    LTok: TTemplateSymbol;
  begin
    result := TMap.Create;
    i := 0;
    Match(vsOpenCurlyBracket);
    while FLookahead.Token <> vsCloseCurlyBracket do
    begin
      if i > 0 then
      begin
        Match(vsComma);
      end;
      LTok := vsString;
      LKey := MatchValues([vsString, vsID], LTok);
      Match(VsCOLON);
      LValue := TValue.From<IExpr>(RuleSimpleExpression);
      result.Add(LKey, LValue);
      inc(i);
    end;
    Match(vsCloseCurlyBracket);
  end;

var
  LSymbol: ITemplateSymbol;
  LDict: TMap;
begin
  LSymbol := FLookahead;

  LDict := ParseMap;

  exit(TMapExpr.Create(LSymbol.Position, LDict));
end;

function TTemplateParser.RuleRequireStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LBeforeStmtStripActions: TStripActionSet;
  LExprList: IExprList;
  LMatchBracket: boolean;
begin
  LSymbol := FLookahead;

  LBeforeStmtStripActions := Match(vsRequire);

  LMatchBracket := false;
  if FLookahead.Token = vsOpenRoundBracket then
  begin
    Match(vsOpenRoundBracket);
    LMatchBracket := true;
  end;

  LExprList := self.RuleExprList();

  if LMatchBracket then
    Match(vsCloseRoundBracket);

  MatchEndOfScript;

  result := TRequireStmt.Create(LSymbol.Position, LExprList);
  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RuleMethodExpr(const AExpr: IExpr; const AMethodExpr: IExpr): IExpr;
var
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;

  Match(vsOpenRoundBracket);

  result := TMethodCallExpr.Create(LSymbol.Position, AExpr, AsVarString(AMethodExpr), RuleExprList);

  MatchClosingBracket(vsCloseRoundBracket);
end;

function TTemplateParser.RuleStmts(const Container: ITemplate; const AEndToken: TTemplateSymbolSet): TTemplateSymbol;
var
  LStmt: IStmt;
  LParentContainer: ITemplate;
  LSymbol: ITemplateSymbol;
  LLoop: boolean;
  LEndToken: TTemplateSymbolSet;

  function AddPrintStmt: IStmt;
  var
    LText: string;
    LMatch: TTemplateSymbol;
    LExpr: IExpr;
  begin
    LMatch := vsText;
    LText := MatchValues([vsText, vsNewLine, vsWhiteSpace], LMatch);
    if LText = '' then
      exit(nil);
    case LMatch of
      vsText:
        LExpr := TValueExpr.Create(LSymbol.Position, LText);
      vsNewLine:
        LExpr := TNewLineExpr.Create(LSymbol.Position, LText);
      vsWhiteSpace:
        LExpr := TWhitespaceExpr.Create(LSymbol.Position, LText);
    end;
    exit(RulePrintStmtVariable(LExpr));
  end;

  procedure SkipStmt;
  begin
    MatchValue(vsText)
  end;

begin
  result := vsInvalid;
  LEndToken := AEndToken + [vsEOF];
  LParentContainer := Container;
  LLoop := true;
  while LLoop do
  begin
    LSymbol := FLookahead;
    if LSymbol.Token in LEndToken then
    begin
      exit(LSymbol.Token);
    end;
    if assigned(FSemiColon) then
    begin
      LStmt := RuleStmt;
      if LStmt = nil then
        LLoop := false;
    end
    else
    begin
      LStmt := nil;
      case LSymbol.Token of
        vsComment:
          begin
            FLookahead := FLexer.GetToken;
          end;
        vsWhiteSpace, vsNewLine, vsText:
          begin
            LStmt := AddPrintStmt;
          end;
        vsSemiColon, vsStartScript:
          begin
            LStmt := RuleStmt;
            if LStmt = nil then
              LLoop := false;
          end;
      end;
    end;
    if (LStmt <> nil) and not supports(LStmt, IElseStmt) then
    begin
      AddStmt(LParentContainer, LStmt);
    end;
  end;
end;

function TTemplateParser.RuleTemplateStmt: IStmt;
var
  LExpr: IExpr;
  LSymbol: ITemplateSymbol;
  LOptions: TParserOptions;
  LContainer: ITemplate;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LOptions := FOptions;
  FOptions := FOptions + [poAllowEnd];
  try
    LSymbol := FLookahead;

    LBeforeStmtStripActions := Match(vsTemplate);

    LExpr := RuleExpression;

    MatchEndOfScript;

    LContainer := PushContainer(LBeforeStmtStripActions);
    RuleStmts(CurrentContainer, [vsEND]);

    PopContainer;

    Match(vsEND);
    MatchEndOfScript;

    LContainer := WrapWithStripStmt(LContainer, LBeforeStmtStripActions);

    result := TDefineTemplateStmt.Create(LSymbol.Position, LExpr, LContainer);
    exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
  finally
    FOptions := LOptions;
  end;
end;

function TTemplateParser.RuleSignedFactor: IExpr;
var
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;

  if LSymbol.Token in [vsMinus, vsPLUS] then
    Match(LSymbol.Token);

  result := RuleFactor;

  if LSymbol.Token = vsMinus then
  begin
    result := RuleFactor;
    if (eoEvalEarly in FContext.Options) and IsValue(result) then
      exit(TValueExpr.Create(LSymbol.Position, -asnum(AsValue(result), FContext)))
    else
      exit(TUnaryExpr.Create(LSymbol.Position, uoMinus, result))
  end;
end;

function TTemplateParser.RuleSimpleExpression: IExpr;
var
  LRightExpr: IExpr;
  LBinOp: TBinOp;
  LSymbol: ITemplateSymbol;
begin
  result := RuleTerm();

  LSymbol := FLookahead;
  if LSymbol.Token in [vsPLUS, vsMinus, vsOR] then
  begin
    TemplateBinop(LSymbol.Token, LBinOp);
    Match(LSymbol.Token);
    LRightExpr := RuleSimpleExpression;
    if (eoEvalEarly in FContext.Options) and IsValue(result) and IsValue(LRightExpr) then
    begin
      case LBinOp of
        boOR:
          exit(TValueExpr.Create(LSymbol.Position, AsBoolean(AsValue(result)) or AsBoolean(AsValue(LRightExpr))));
        boPlus:
          begin
            if isNumLike(AsValue(result)) and isNumLike(AsValue(LRightExpr)) then
              exit(TValueExpr.Create(LSymbol.Position, asnum(AsValue(result), FContext) + asnum(AsValue(LRightExpr), FContext)))
            else if isStrLike(AsValue(result)) and isStrLike(AsValue(LRightExpr)) then
              exit(TValueExpr.Create(LSymbol.Position, asString(AsValue(result), FContext) + asString(AsValue(LRightExpr), FContext)))
            else if isStrLike(AsValue(result)) and isNumLike(AsValue(LRightExpr)) then
              exit(TValueExpr.Create(LSymbol.Position, asString(AsValue(result), FContext) + floattostr(asnum(AsValue(LRightExpr), FContext), FContext.FormatSettings)));
          end;
        boMinus:
          exit(TValueExpr.Create(LSymbol.Position, asnum(AsValue(result), FContext) - asnum(AsValue(LRightExpr), FContext)));
      end;
    end;
    exit(TBinopExpr.Create(LSymbol.Position, result, LBinOp, LRightExpr));
  end;
end;

function TTemplateParser.RuleTerm: IExpr;
var
  LRightExpr: IExpr;
  LBinOp: TBinOp;
  LSymbol: ITemplateSymbol;
begin
  result := RuleSignedFactor;

  LSymbol := FLookahead;
  if LSymbol.Token in [vsMULT, vsDIV, vsSLASH, vsMOD, vsAND] then
  begin
    TemplateBinop(LSymbol.Token, LBinOp);
    Match(LSymbol.Token);
    LRightExpr := RuleTerm;
    if (eoEvalEarly in FContext.Options) and IsValue(result) and IsValue(LRightExpr) then
    begin
      case LBinOp of
        boAND:
          exit(TValueExpr.Create(LSymbol.Position, AsBoolean(AsValue(result)) and AsBoolean(AsValue(LRightExpr))));
        boMult:
          exit(TValueExpr.Create(LSymbol.Position, asnum(AsValue(result), FContext) * asnum(AsValue(LRightExpr), FContext)));
        boDiv:
          exit(TValueExpr.Create(LSymbol.Position, trunc(asnum(AsValue(result), FContext)) div trunc(asnum(AsValue(LRightExpr), FContext))));
        boSlash:
          exit(TValueExpr.Create(LSymbol.Position, asnum(AsValue(result), FContext) / asnum(AsValue(LRightExpr), FContext)));
        boMod:
          exit(TValueExpr.Create(LSymbol.Position, AsInt(AsValue(result), FContext) mod AsInt(AsValue(LRightExpr), FContext)));
      end;
    end;
    exit(TBinopExpr.Create(LSymbol.Position, result, LBinOp, LRightExpr));
  end;
end;

function TTemplateParser.RuleStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
begin
  result := nil;
  LSymbol := FLookahead;
  if not assigned(FSemiColon) then
    FBeforeStartScriptStripActions := Match(vsStartScript);

  case FLookahead.Token of
    vsEndScript:
      result := RuleNoopStmt;
    vsBreak:
      result := RuleBreakStmt;
    vsContinue:
      result := RuleContinueStmt;
    vsIgnoreNL:
      result := RuleIgnoreNewline;
    vsIgnoreWS:
      result := RuleIgnoreWhitespace;
    vsComment:
      result := RuleCommentStmt;
    vsInclude:
      result := RuleIncludeStmt;
    vsEND:
      result := RuleEndStmt;
    vsElse, vsELIF, vsOnBegin, vsOnEnd, vsOnEmpty, vsBetweenItem:
      result := nil;
    vsIF:
      result := RuleIfStmt;
    vsFor:
      result := RuleForStmt;
    vsCycle:
      result := RuleCycleStmt;
    vsPrint:
      result := RulePrintStmt;
    vsWhile:
      result := RuleWhileStmt;
    vsWith:
      result := RuleWithStmt;
    vsRequire:
      result := RuleRequireStmt;
    vsTemplate:
      result := RuleTemplateStmt;
    vsID:
      result := RuleIdStmt;
    vsBlock:
      result := RuleBlockStmt;
    vsExtends:
      result := RuleExtendsStmt;

  else
    result := RuleExprStmt;
  end;

  if (eoEmbedException in FContext.Options) and (result <> nil) then
  begin
    result := TDebugStmt.Create(result);
  end;
end;

function TTemplateParser.RuleVariable: IExpr;
var
  LId: string;
  LIdVal: TValue;
  LSymbol: ITemplateSymbol;
  LExpr: IExpr;
  LDone: boolean;
  LDeref: TValue;
begin
  LDone := false;
  LSymbol := FLookahead;

  LId := MatchValue(vsID);

  if (eoEvalVarsEarly in FContext.Options) and FContext.TryGetVariable(LId, LIdVal) then
    result := TValueExpr.Create(LSymbol.Position, LIdVal)
  else
    result := TVariableExpr.Create(LSymbol.Position, LId);

  while not LDone do
  begin
    LSymbol := FLookahead;
    case LSymbol.Token of
      vsOpenRoundBracket:
        begin
          result := self.RuleFunctionExpr(LId);
        end;
      vsOpenSquareBracket:
        begin
          Match(vsOpenSquareBracket);
          LExpr := self.RuleExpression;
          if (eoEvalVarsEarly in FContext.Options) and IsValue(result) and IsValue(LExpr) then
          begin
            LDeref := Deref(LSymbol.Position, AsValue(result), AsValue(LExpr), eoRaiseErrorWhenVariableNotFound in FContext.Options, FContext);
            result := TValueExpr.Create(LSymbol.Position, LDeref);
          end
          else
          begin
            result := TVariableDerefExpr.Create(LSymbol.Position, dtArray, result, LExpr);
          end;
          Match(vsCloseSquareBracket);
        end;
      vsDOT:
        begin
          Match(vsDOT);
          LExpr := TVariableExpr.Create(LSymbol.Position, MatchValue(vsID));
          if FLookahead.Token = vsOpenRoundBracket then
            result := RuleMethodExpr(result, LExpr)
          else
          begin
            if (eoEvalVarsEarly in FContext.Options) and IsValue(result) and IsValue(LExpr) then
            begin
              LDeref := Deref(LSymbol.Position, AsValue(result), AsValue(LExpr), eoRaiseErrorWhenVariableNotFound in FContext.Options, FContext);
              result := TValueExpr.Create(LSymbol.Position, LDeref);
            end
            else
            begin
              result := TVariableDerefExpr.Create(LSymbol.Position, dtObject, result, LExpr);
            end;
          end;
        end;
    else
      LDone := true;
    end;
    if LDone then
      break;
  end;
end;

function TTemplateParser.RuleAssignStmt(const ASymbol: IExpr): IStmt;
var
  LSymbol: ITemplateSymbol;
  LVar: string;
begin
  LSymbol := FLookahead;

  Match(vsEQ);

  LVar := AsVarString(ASymbol);
  if LVar = '' then
    RaiseError(LSymbol.Position, SAssignmentToVar);

  exit(TAssignStmt.Create(LSymbol.Position, LVar, RuleExpression));
end;

function TTemplateParser.RuleBlockStmt: IStmt;
var
  LName: IExpr;
  LSymbol: ITemplateSymbol;
  LOptions: TParserOptions;
  LContainer: ITemplate;
  LBeforeStmtStripActions: TStripActionSet;
  LMatchBracket: boolean;
begin
  LOptions := FOptions;
  FOptions := FOptions + [poAllowEnd];
  try
    LSymbol := FLookahead;

    LBeforeStmtStripActions := Match(vsBlock);
    LMatchBracket := false;
    if FLookahead.Token = vsOpenRoundBracket then
    begin
      Match(vsOpenRoundBracket);
      LMatchBracket := true;
    end;
    LName := RuleExpression;
    if LMatchBracket then
      Match(vsCloseRoundBracket);

    MatchEndOfScript;

    LContainer := PushContainer(LBeforeStmtStripActions);
    RuleStmts(LContainer, [vsEND]);

    PopContainer;

    Match(vsEND);
    MatchEndOfScript;

    LContainer := WrapWithStripStmt(LContainer, LBeforeStmtStripActions);

    result := TBlockStmt.Create(LSymbol.Position, LName, LContainer);
    exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
  finally
    FOptions := LOptions;
  end;
end;

function TTemplateParser.RuleNoopStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LSymbol := FLookahead;

  LBeforeStmtStripActions := FBeforeStartScriptStripActions;

  MatchEndOfScript;

  result := TNoopStmt.Create(LSymbol.Position);
  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RuleBreakStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LLoopStripActions: TStripActionSet;
begin
  LSymbol := FLookahead;

  LLoopStripActions := FLoopStripActions;
  Match(vsBreak);
  MatchEndOfScript;

  if not(poInLoop in FOptions) then
    RaiseError(LSymbol.Position, SContinueShouldBeInALoop);

  result := TBreakStmt.Create(LSymbol.Position);
  exit(WrapWithStripStmt(result, LLoopStripActions));
end;

function TTemplateParser.RuleCommentStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LSymbol := FLookahead;

  LBeforeStmtStripActions := Match(vsComment);
  MatchEndOfScript;

  result := TCommentStmt.Create(LSymbol.Position);
  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RuleContinueStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LLoopStripActions: TStripActionSet;
begin
  LSymbol := FLookahead;

  LLoopStripActions := FLoopStripActions;

  Match(vsContinue);
  MatchEndOfScript;

  if not(poInLoop in FOptions) then
    RaiseError(LSymbol.Position, SContinueShouldBeInALoop);

  result := TContinueStmt.Create(LSymbol.Position);
  exit(WrapWithStripStmt(result, LLoopStripActions));
end;

function TTemplateParser.RuleCycleStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LListExpr: IExprList;
  LBeforeStmtStripActions: TStripActionSet;
  LMatchBracket: boolean;
begin
  LSymbol := FLookahead;

  LBeforeStmtStripActions := Match(vsCycle);

  LMatchBracket := false;
  if FLookahead.Token = vsOpenRoundBracket then
  begin
    Match(vsOpenRoundBracket);
    LMatchBracket := true;
  end;

  LListExpr := RuleExprList();

  if LMatchBracket then
    MatchClosingBracket(vsCloseRoundBracket);

  MatchEndOfScript;

  result := TCycleStmt.Create(LSymbol.Position, LListExpr);
  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RuleElIfStmt(out AFalseContainer: ITemplate; const ABeforeStmtStripActions: TStripActionSet): IStmt;
var
  LConditionExpr: IExpr;
  LTrueContainer: ITemplate;
  LOptions: TParserOptions;
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;
  if not(poAllowElIf in FOptions) then
    RaiseError(LSymbol.Position, SElIfExpected);

  LOptions := FOptions;
  FOptions := FOptions + [poAllowElse, poHasElse, poAllowEnd];
  try
    Match(vsELIF);

    LConditionExpr := RuleExpression;

    MatchEndOfScript;

    LTrueContainer := PushContainer(ABeforeStmtStripActions);

    RuleStmts(LTrueContainer, [vsELIF, vsElse, vsEND]);

    PopContainer;

    AFalseContainer := PushContainer(ABeforeStmtStripActions);

    if FLookahead.Token = vsElse then
    begin
      Match(vsElse);
      MatchEndOfScript;

      RuleStmts(AFalseContainer, [vsEND, vsELIF]);
    end;

    PopContainer;

    try
      LTrueContainer := WrapWithStripStmt(LTrueContainer, ABeforeStmtStripActions);
      AFalseContainer := WrapWithStripStmt(AFalseContainer, ABeforeStmtStripActions);

      if (eoEvalEarly in FContext.Options) and IsValue(LConditionExpr) then
      begin
        if AsBoolean(AsValue(LConditionExpr)) then
          exit(TProcessTemplateStmt.Create(LSymbol.Position, LTrueContainer))
        else if AFalseContainer <> nil then
          exit(TProcessTemplateStmt.Create(LSymbol.Position, AFalseContainer))
      end;

      exit(TIfStmt.Create(LSymbol.Position, LConditionExpr, LTrueContainer, AFalseContainer));
    finally
      result := WrapWithStripStmt(result, ABeforeStmtStripActions);
    end;

  finally
    FOptions := LOptions;
  end;
end;

function TTemplateParser.RuleEndStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;

  if not(poAllowEnd in FOptions) then
    RaiseError(LSymbol.Position, SEndNotExpected);

  exit(TEndStmt.Create(LSymbol.Position));
end;

function TTemplateParser.RuleExpression: IExpr;
var
  LSymbol: ITemplateSymbol;
  LRight: IExpr;
  LBinOp: TBinOp;

  function TryTernary(const ACond: IExpr; const ATrueExpr: IExpr; const AFalseExpr: IExpr): IExpr;
  begin
    if (eoEvalEarly in FContext.Options) and IsValue(ACond) then
    begin
      if AsBoolean(AsValue(ACond)) then
        exit(ATrueExpr)
      else
        exit(AFalseExpr);
    end;
    exit(TTernaryExpr.Create(LSymbol.Position, ACond, ATrueExpr, AFalseExpr));
  end;

  function TryCTernary(var AExpr: IExpr): boolean;
  var
    LTrueExpr: IExpr;
    LFalseExpr: IExpr;
  begin
    if FLookahead.Token = vsQUESTION then
    begin
      Match(vsQUESTION);
      LTrueExpr := RuleExpression();
      Match(VsCOLON);
      LFalseExpr := RuleExpression();
      AExpr := TryTernary(AExpr, LTrueExpr, LFalseExpr);
      exit(true);
    end;
    exit(false);
  end;

  function TryPasTernary(var LExprIsInitialTrue: IExpr): boolean;
  var
    LCond: IExpr;
    LFalseExpr: IExpr;
  begin
    if FLookahead.Token = vsIF then
    begin
      Match(vsIF);
      LCond := RuleExpression();
      Match(vsElse);
      LFalseExpr := RuleExpression();
      LExprIsInitialTrue := TryTernary(LCond, LExprIsInitialTrue, LFalseExpr);
      exit(true);
    end;
    exit(false);
  end;

begin
  result := RuleSimpleExpression();

  LSymbol := FLookahead;
  if LSymbol.Token in [vsEQ, vsNotEQ, vsLT, vsLTE, vsGT, vsGTE, vsIn] then
  begin
    TemplateBinop(LSymbol.Token, LBinOp);
    Match(LSymbol);
    LRight := RuleExpression;
    if (eoEvalEarly in FContext.Options) and IsValue(result) and IsValue(LRight) then
    begin
      case LBinOp of
        boEQ:
          exit(TValueExpr.Create(LSymbol.Position, isequal(AsValue(result), AsValue(LRight), FContext)));
        boNotEQ:
          exit(TValueExpr.Create(LSymbol.Position, not isequal(AsValue(result), AsValue(LRight), FContext)));
        boLT:
          exit(TValueExpr.Create(LSymbol.Position, isLessThan(AsValue(result), AsValue(LRight), FContext)));
        boGTE:
          exit(TValueExpr.Create(LSymbol.Position, not isLessThan(AsValue(result), AsValue(LRight), FContext)));
        boGT:
          exit(TValueExpr.Create(LSymbol.Position, isGreaterThan(AsValue(result), AsValue(LRight), FContext)));
        boLTE:
          exit(TValueExpr.Create(LSymbol.Position, not isGreaterThan(AsValue(result), AsValue(LRight), FContext)));
      end;
    end;
    result := TBinopExpr.Create(LSymbol.Position, result, LBinOp, LRight);
  end;

  if TryCTernary(result) then // this is C like - initial mistake IMO
    exit;
  if TryPasTernary(result) then // this is the prefered ternary
    exit;
end;

function TTemplateParser.RuleFactor: IExpr;
var
  LSymbol: ITemplateSymbol;

begin
  LSymbol := FLookahead;

  case LSymbol.Token of
    vsOpenCurlyBracket:
      exit(RuleMapExpr);
    vsOpenSquareBracket:
      begin
        Match(vsOpenSquareBracket);
        result := TArrayExpr.Create(LSymbol.Position, RuleExprList(vsCloseSquareBracket));
        MatchClosingBracket(vsCloseSquareBracket);
        exit;
      end;
    vsOpenRoundBracket:
      begin
        Match(vsOpenRoundBracket);
        result := RuleExpression;
        MatchClosingBracket(vsCloseRoundBracket);
        exit;
      end;
    vsString:
      exit(TValueExpr.Create(LSymbol.Position, MatchValue(vsString)));
    vsNumber:
      exit(TValueExpr.Create(LSymbol.Position, MatchNumber(vsNumber)));
    vsBoolean:
      exit(TValueExpr.Create(LSymbol.Position, MatchValue(vsBoolean) = 'true'));
    vsID:
      exit(self.RuleVariable());
    vsNOT:
      begin
        Match(vsNOT);
        result := RuleExpression;
        if (eoEvalEarly in FContext.Options) and IsValue(result) then
          exit(TValueExpr.Create(LSymbol.Position, not AsBoolean(AsValue(result))))
        else
          exit(TUnaryExpr.Create(LSymbol.Position, uoNot, result));
      end;
  end;
end;

const
  ONFIRST_ONEND_ONLOOP_ELSE: TTemplateSymbolSet = [vsOnBegin, vsOnEnd, vsOnEmpty, vsBetweenItem, vsEND];

{$IFDEF SUPPORT_PASS_ARRAY_OF_INTERFACE}

function ArrayOfTemplate(const ATemplates: TArray<ITemplate>): TArray<ITemplate>;
begin
  exit(ATemplates);
end;
{$ELSE}

function ArrayOfTemplate(const ATemplates: array of ITemplate): TArray<ITemplate>;
var
  i: integer;
begin
  SetLength(result, length(ATemplates));
  for i := Low(ATemplates) to High(ATemplates) do
    result[i] := ATemplates[i];
end;
{$ENDIF}

function TTemplateParser.RuleForStmt: IStmt;
var
  LId: string;
  LRangeExpr: IExpr;
  LLowValueExpr, LHighValueExpr: IExpr;
  LOffsetExpr, LLimitExpr, LStep: IExpr;
  LForOp: TForOp;
  LOptions: TParserOptions;
  LContainerTemplate: ITemplate;
  LSymbol: ITemplateSymbol;
  LOnBegin, LOnEnd, LOnLoop, LOnEmpty, LBetweenItem: ITemplate;
  LPrevSymbol, LBlockSymbol: TTemplateSymbol;
  i: integer;
  LBeforeStmtStripActions: TStripActionSet;
  LLoopStripActions: TStripActionSet;
  procedure ResolveTemplate(const ASymbol: TTemplateSymbol);
  begin
    case ASymbol of
      vsInvalid:
        begin
          LOnLoop := LContainerTemplate;
        end;
      vsOnBegin:
        begin
          LOnBegin := LContainerTemplate;
        end;
      vsOnEnd:
        begin
          LOnEnd := LContainerTemplate;
        end;
      vsOnEmpty:
        begin
          LOnEmpty := LContainerTemplate;
        end;
      vsBetweenItem:
        begin
          LBetweenItem := LContainerTemplate;
        end;
    end;
  end;

begin
  LSymbol := FLookahead;
  LLoopStripActions := FLoopStripActions;
  LOptions := FOptions;
  FOptions := FOptions + [poInLoop, poAllowEnd];
  try
    LBeforeStmtStripActions := Match(vsFor);
    FLoopStripActions := LBeforeStmtStripActions;

    LId := MatchValue(vsID);

    if FLookahead.Token in [vsIn, vsOf] then
    begin
      LForOp := TemplateForop(LSymbol.Position, FLookahead.Token);
      Match(FLookahead.Token);
      LRangeExpr := RuleExpression;
    end
    else
    begin
      Match(vsEQ);

      LLowValueExpr := RuleExpression();
      LForOp := TemplateForop(LSymbol.Position, FLookahead.Token);
      if FLookahead.Token in [vsDownto, vsTo] then
        Match(FLookahead.Token)
      else
        RaiseError(LSymbol.Position, SUnexpectedToken);
      LHighValueExpr := RuleExpression();
    end;

    while FLookahead.Token in [vsOffset, vsLimit, vsStep] do
    begin
      case FLookahead.Token of
        vsOffset:
          begin
            Match(vsOffset);
            LOffsetExpr := RuleExpression();
          end;

        vsLimit:
          begin
            Match(vsLimit);
            LLimitExpr := RuleExpression();
          end;

        vsStep:
          begin
            Match(vsStep);
            LStep := RuleExpression();
          end;
      end;
    end;

    MatchEndOfScript;

    LBlockSymbol := vsInvalid;
    LPrevSymbol := vsInvalid;
    i := 0;
    repeat
      if (i > 1) and (i mod 2 = 0) then
      begin
        Match(LBlockSymbol);
        MatchEndOfScript;
      end;
      LContainerTemplate := PushContainer(LBeforeStmtStripActions);

      LBlockSymbol := RuleStmts(LContainerTemplate, ONFIRST_ONEND_ONLOOP_ELSE);

      PopContainer;
      if (i mod 2 = 0) then
      begin
        ResolveTemplate(LPrevSymbol);
      end;
      LPrevSymbol := LBlockSymbol;
      inc(i);
    until LBlockSymbol = vsEND;

    Match(vsEND);

    if LOnLoop = nil then
    begin
      LOnLoop := LContainerTemplate;
    end;

    MatchEndOfScript;

    if assigned(LOnLoop) and (LOnLoop.Count = 0) then
      LOnLoop := nil;
    if assigned(LOnBegin) and (LOnBegin.Count = 0) then
      LOnBegin := nil;
    if assigned(LOnEnd) and (LOnEnd.Count = 0) then
      LOnEnd := nil;
    if assigned(LOnEmpty) and (LOnEmpty.Count = 0) then
      LOnEmpty := nil;
    if assigned(LBetweenItem) and (LBetweenItem.Count = 0) then
      LBetweenItem := nil;

    LOnLoop := WrapWithStripStmt(LOnLoop, LBeforeStmtStripActions);
    LOnBegin := WrapWithStripStmt(LOnBegin, LBeforeStmtStripActions);
    LOnEnd := WrapWithStripStmt(LOnEnd, LBeforeStmtStripActions);
    LOnEmpty := WrapWithStripStmt(LOnEmpty, LBeforeStmtStripActions);
    LBetweenItem := WrapWithStripStmt(LBetweenItem, LBeforeStmtStripActions);

    if not assigned(LOnLoop) and not assigned(LOnBegin) and not assigned(LOnEnd) and not assigned(LOnEmpty) and not assigned(LBetweenItem) then
      exit(nil);

    if LForOp in [TForOp.foIn, TForOp.foOf] then
      result := TForInStmt.Create(LSymbol.Position, LId, LForOp, LRangeExpr, LOffsetExpr, LLimitExpr, LOnLoop, LOnBegin, LOnEnd, LOnEmpty, LBetweenItem)
    else
      result := TForRangeStmt.Create(LSymbol.Position, LId, LForOp, LLowValueExpr, LHighValueExpr, LStep, LOnLoop, LOnBegin, LOnEnd, LOnEmpty, LBetweenItem);

    result := WrapWithStripStmt(result, LBeforeStmtStripActions);
  finally
    FOptions := LOptions;
    FLoopStripActions := LLoopStripActions;
  end;
end;

function TTemplateParser.RuleFunctionExpr(const ASymbol: string): IExpr;
var
  LFunctions: TArray<TRttiMethod>;
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;

  if not FContext.TryGetFunction(ASymbol, LFunctions) then
    RaiseError(LSymbol.Position, SFunctionNotRegisteredInContext, [ASymbol]);

  Match(vsOpenRoundBracket);

  result := TFunctionCallExpr.Create(LSymbol.Position, LFunctions, RuleExprList);

  MatchClosingBracket(vsCloseRoundBracket);
end;

function TTemplateParser.RuleIdStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LExpr: IExpr;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LSymbol := FLookahead;
  LExpr := RuleVariable;

  LBeforeStmtStripActions := FBeforeStartScriptStripActions;

  if FLookahead.Token = vsEQ then
  begin
    result := RuleAssignStmt(LExpr);
  end
  else if FLookahead.Token in [vsOpenCurlyBracket, vsID, vsString] then
  begin
    result := RuleIncludeStmt(LExpr);
  end
  else if FLookahead.Token in [vsEndScript, vsSemiColon] then
  begin
    LExpr := TEncodeExpr.Create(LSymbol.Position, LExpr);
    result := RulePrintStmtVariable(LExpr);
  end
  else
  begin
    RaiseError(LSymbol.Position, SParsingErrorExpecting, ['variable reference, function call or assignment']);
  end;

  MatchEndOfScript;

  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RuleWhileStmt: IStmt;
var
  LCondition: IExpr;
  LOptions: TParserOptions;
  LSymbol: ITemplateSymbol;
  LOffsetExpr, LLimitExpr: IExpr;
  LContainerTemplate: ITemplate;
  LOnBegin, LOnEnd, LOnLoop, LOnEmpty, LBetweenItem: ITemplate;
  LPrevSymbol, LBlockSymbol: TTemplateSymbol;
  i: integer;
  LBeforeStmtStripActions: TStripActionSet;
  LLoopStripActions: TStripActionSet;
  procedure ResolveTemplate(const ASymbol: TTemplateSymbol);
  begin
    case ASymbol of
      vsInvalid:
        begin
          LOnLoop := LContainerTemplate;
        end;
      vsOnBegin:
        begin
          LOnBegin := LContainerTemplate;
        end;
      vsOnEnd:
        begin
          LOnEnd := LContainerTemplate;
        end;
      vsOnEmpty:
        begin
          LOnEmpty := LContainerTemplate;
        end;
      vsBetweenItem:
        begin
          LBetweenItem := LContainerTemplate;
        end;
    end;
  end;

begin
  LSymbol := FLookahead;
  LLoopStripActions := FLoopStripActions;
  LOptions := FOptions;
  FOptions := FOptions + [poInLoop, poAllowEnd];
  try
    LBeforeStmtStripActions := Match(vsWhile);
    FLoopStripActions := LBeforeStmtStripActions;

    LCondition := RuleExpression;
    while FLookahead.Token in [vsOffset, vsLimit] do
    begin
      case FLookahead.Token of
        vsOffset:
          begin
            Match(vsOffset);
            LOffsetExpr := RuleExpression();
          end;
        vsLimit:
          begin
            Match(vsLimit);
            LLimitExpr := RuleExpression();
          end;
      end;
    end;

    MatchEndOfScript;

    LBlockSymbol := vsInvalid;
    LPrevSymbol := vsInvalid;
    i := 0;
    repeat
      if (i > 1) and (i mod 2 = 0) then
      begin
        Match(LBlockSymbol);
        MatchEndOfScript;
      end;
      LContainerTemplate := PushContainer(LBeforeStmtStripActions);

      LBlockSymbol := RuleStmts(LContainerTemplate, ONFIRST_ONEND_ONLOOP_ELSE);

      PopContainer;
      if (i mod 2 = 0) then
      begin
        ResolveTemplate(LPrevSymbol);
      end;
      LPrevSymbol := LBlockSymbol;
      inc(i);
    until LBlockSymbol = vsEND;

    if LOnLoop = nil then
    begin
      LOnLoop := LContainerTemplate;
    end;

    Match(vsEND);
    MatchEndOfScript;

    if assigned(LOnLoop) and (LOnLoop.Count = 0) then
      LOnLoop := nil;
    if assigned(LOnBegin) and (LOnBegin.Count = 0) then
      LOnBegin := nil;
    if assigned(LOnEnd) and (LOnEnd.Count = 0) then
      LOnEnd := nil;
    if assigned(LOnEmpty) and (LOnEmpty.Count = 0) then
      LOnEmpty := nil;
    if assigned(LBetweenItem) and (LBetweenItem.Count = 0) then
      LBetweenItem := nil;

    LOnLoop := WrapWithStripStmt(LOnLoop, LBeforeStmtStripActions);
    LOnBegin := WrapWithStripStmt(LOnBegin, LBeforeStmtStripActions);
    LOnEnd := WrapWithStripStmt(LOnEnd, LBeforeStmtStripActions);
    LOnEmpty := WrapWithStripStmt(LOnEmpty, LBeforeStmtStripActions);
    LBetweenItem := WrapWithStripStmt(LBetweenItem, LBeforeStmtStripActions);

    if not assigned(LOnLoop) and not assigned(LOnBegin) and not assigned(LOnEnd) and not assigned(LOnEmpty) and not assigned(LBetweenItem) then
      exit(nil);

    if (eoEvalEarly in FContext.Options) and IsValue(LCondition) and not AsBoolean(AsValue(LCondition)) then
      result := nil
    else
      result := TWhileStmt.Create(LSymbol.Position, LCondition, LOffsetExpr, LLimitExpr, LOnLoop, LOnBegin, LOnEnd, LOnEmpty, LBetweenItem);

    result := WrapWithStripStmt(result, LBeforeStmtStripActions);
  finally
    FOptions := LOptions;
    FLoopStripActions := LLoopStripActions;
  end;
end;

function TTemplateParser.RuleWithStmt: IStmt;
var
  LExpr: IExpr;
  LSymbol: ITemplateSymbol;
  LOptions: TParserOptions;
  LContainer: ITemplate;
  LBeforeStmtStripActions: TStripActionSet;
begin
  LOptions := FOptions;
  FOptions := FOptions + [poAllowEnd];
  try
    LSymbol := FLookahead;

    LBeforeStmtStripActions := Match(vsWith);

    LExpr := RuleExpression;

    MatchEndOfScript;

    LContainer := PushContainer(LBeforeStmtStripActions);

    RuleStmts(LContainer, [vsEND]);
    PopContainer;

    Match(vsEND);
    MatchEndOfScript;

    if LContainer.Count = 0 then
      exit(nil);

    LContainer := WrapWithStripStmt(LContainer, LBeforeStmtStripActions);

    result := TWithStmt.Create(LSymbol.Position, LExpr, LContainer);
    exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
  finally
    FOptions := LOptions;
  end;
end;

function TTemplateParser.WrapWithStripStmt(const AStmt: IStmt; const ABeforeScript: TStripActionSet): IStmt;
begin
  if not assigned(AStmt) then
    exit(nil);

  result := AddStripStmtFront(AStmt, ABeforeScript, sdLeft);
  result := AddStripStmtEnd(result, TrailingStripActions(ABeforeScript), sdRight);
end;

function TTemplateParser.WrapWithStripStmt(const ATemplate: ITemplate; const ABeforeScript: TStripActionSet): ITemplate;
begin
  if not assigned(ATemplate) then
    exit(nil);

  result := AddStripStmtFront(ATemplate, TrailingStripActions(ABeforeScript), sdRight);
  result := AddStripStmtEnd(result, ABeforeScript, sdLeft);
end;

function TTemplateParser.RulePrintStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LExpr: IExpr;
  LBeforeStmtStripActions: TStripActionSet;
  LMatchBracket: boolean;
begin
  LSymbol := FLookahead;

  LBeforeStmtStripActions := Match(vsPrint);

  LMatchBracket := false;
  if FLookahead.Token = vsOpenRoundBracket then
  begin
    Match(vsOpenRoundBracket);
    LMatchBracket := true;
  end;

  LExpr := RuleExpression;

  if LMatchBracket then
    MatchClosingBracket(vsCloseRoundBracket);

  MatchEndOfScript;

  result := TPrintStmt.Create(LSymbol.Position, LExpr);
  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RulePrintStmtVariable(const AExpr: IExpr): IStmt;
var
  LSymbol: ITemplateSymbol;
  LValueExpr: IValueExpr;
begin
  LSymbol := FLookahead;

  if supports(AExpr, IValueExpr, LValueExpr) and (asString(LValueExpr.Value, FContext) = '') then
    exit(nil);

  exit(TPrintStmt.Create(LSymbol.Position, AExpr));
end;

function TTemplateParser.RuleExprList(const AEndToken: TTemplateSymbol): IExprList;
var
  LSymbol: ITemplateSymbol;
  LValueSeparator: TTemplateSymbol;
begin
  LSymbol := FLookahead;
  result := TExprList.Create(LSymbol.Position);
  if FLookahead.Token <> AEndToken then
    result.AddExpr(RuleExpression);
  LValueSeparator := GetValueSeparatorSymbol;
  while FLookahead.Token = LValueSeparator do
  begin
    Match(LValueSeparator);
    result.AddExpr(RuleExpression);
  end;
end;

function TTemplateParser.RuleExprMap: IExpr;

function ParseMap(const AMatchCurly: boolean): TMap; forward;
function ParseExpr: TValue; forward;

  function ParseArray: TArray<TValue>;
  var
    LSymbol: ITemplateSymbol;
    i: integer;
  begin
    i := 0;
    result := nil;
    LSymbol := FLookahead;
    Match(vsOpenSquareBracket);
    while FLookahead.Token <> vsCloseSquareBracket do
    begin
      if i > 0 then
      begin
        Match(vsComma);
      end;
      SetLength(result, length(result) + 1);
      result[high(result)] := ParseExpr;
      inc(i);
    end;
    Match(vsCloseSquareBracket);
  end;

  function ParseExpr: TValue;
  var
    LSymbol: ITemplateSymbol;
    LValue: TValue;
    LArr: TArray<TValue>;
  begin
    LSymbol := FLookahead;
    case LSymbol.Token of
      vsString:
        exit(MatchValue(vsString));
      vsNumber:
        exit(MatchNumber(vsNumber));
      vsBoolean:
        exit(MatchValue(vsBoolean) = 'true');
      vsOpenSquareBracket:
        begin
          LArr := ParseArray;
          LValue := TValue.From < TArray < TValue >> (LArr);
          exit(LValue);
        end;
      vsOpenCurlyBracket:
        begin
          exit(TValue.From<TMap>(ParseMap(true)));
        end;
    end;
  end;

  function ParseMap(const AMatchCurly: boolean): TMap;
  var
    LKey: string;
    i: integer;
    LValue: TValue;
    LTok: TTemplateSymbol;
    LEnd: set of TTemplateSymbol;
  begin
    result := TMap.Create;
    i := 0;
    if AMatchCurly then
    begin
      Match(vsOpenCurlyBracket);
      LEnd := [vsCloseCurlyBracket];
    end
    else
    begin
      LEnd := [vsEndScript, vsSemiColon, vsCloseCurlyBracket];
    end;
    while not(FLookahead.Token in LEnd) do
    begin
      if i > 0 then
      begin
        Match(vsComma);
      end;
      LTok := vsString;
      LKey := MatchValues([vsString, vsID], LTok);
      if not AMatchCurly then
        Match(vsEQ)
      else
        Match(VsCOLON);
      LValue := TValue.From<IExpr>(RuleSimpleExpression);
      result.Add(LKey, LValue);
      inc(i);
    end;
    if AMatchCurly then
      Match(vsCloseCurlyBracket);
  end;

var
  LSymbol: ITemplateSymbol;
  LDict: TMap;
begin
  LSymbol := FLookahead;

  LDict := ParseMap(false);

  exit(TMapExpr.Create(LSymbol.Position, LDict));
end;

function TTemplateParser.RuleExprStmt: IStmt;
var
  LSymbol: ITemplateSymbol;
  LExpr: IExpr;
  LBeforeStmtStripActions: TStripActionSet;
  LMatchBracket: boolean;
begin
  LSymbol := FLookahead;

  LBeforeStmtStripActions := FBeforeStartScriptStripActions;

  LMatchBracket := false;
  if FLookahead.Token = vsOpenRoundBracket then
  begin
    Match(vsOpenRoundBracket);
    LMatchBracket := true;
  end;

  LExpr := RuleExpression;

  if LMatchBracket then
    Match(vsCloseRoundBracket);

  result := RulePrintStmtVariable(TEncodeExpr.Create(LSymbol.Position, LExpr));

  MatchEndOfScript;

  exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
end;

function TTemplateParser.RuleExtendsStmt: IStmt;
var
  LName: IExpr;
  LScopeExpr: IExpr;
  LSymbol: ITemplateSymbol;
  LOptions: TParserOptions;
  LContainer: ITemplate;
  LContainerTemplate: TTemplate;
  LBeforeStmtStripActions: TStripActionSet;
  LMatchBracket: boolean;
begin
  LOptions := FOptions;
  FOptions := FOptions + [poAllowEnd];
  try
    LSymbol := FLookahead;

    LBeforeStmtStripActions := Match(vsExtends);

    LMatchBracket := false;
    if FLookahead.Token = vsOpenRoundBracket then
    begin
      Match(vsOpenRoundBracket);
      LMatchBracket := true;
    end;

    LName := RuleExpression;

    if FLookahead.Token = vsComma then
    begin
      Match(vsComma);
      LScopeExpr := RuleExpression;
    end;

    if LMatchBracket then
      Match(vsCloseRoundBracket);

    MatchEndOfScript;

    LContainer := PushContainer(LBeforeStmtStripActions);
    RuleStmts(LContainer, [vsEND]);
    PopContainer;

    Match(vsEND);
    MatchEndOfScript;

    LContainer := WrapWithStripStmt(LContainer, LBeforeStmtStripActions);

    result := TExtendsStmt.Create(LSymbol.Position, LName, LContainer);

    if LScopeExpr <> nil then
    begin
      LContainerTemplate := TTemplate.Create();
      LContainerTemplate.Add(result);
      result := TWithStmt.Create(LSymbol.Position, LScopeExpr, LContainerTemplate);
    end;

    exit(WrapWithStripStmt(result, LBeforeStmtStripActions));
  finally
    FOptions := LOptions;
  end;
end;

function TTemplateParser.CurrentContainer: ITemplate;
begin
  if FContainerStack.Count <> 0 then
    exit(FContainerStack.peek)
  else
    exit(nil);
end;

destructor TTemplateParser.Destroy;
begin
  FContainerStack.Free;
  inherited;
end;

function TTemplateParser.LookaheadValue: string;
var
  val: ITemplateValueSymbol;
begin
  val := FLookahead as ITemplateValueSymbol;
  exit(val.Value)
end;

function TTemplateParser.Match(const ASymbol: TTemplateSymbol): TStripActionSet;
var
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;
  result := [];
  if ASymbol = FLookahead.Token then
  begin
    case ASymbol of
      vsStartScript:
        begin
          result := LSymbol.StripActions;
          FBeforeStartScriptStripActions := result;
        end;
    else
      result := FBeforeStartScriptStripActions;
    end;
    FLookahead := FLexer.GetToken;
    exit;
  end;
  RaiseError(LSymbol.Position, SParsingErrorExpecting, [TemplateSymbolToString(ASymbol)]);
end;

function TTemplateParser.Match(ASymbols: TTemplateSymbolSet; var AMatchSymbol: TTemplateSymbol): TStripActionSet;
var
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;
  if FLookahead.Token in ASymbols then
  begin
    AMatchSymbol := FLookahead.Token;
    if AMatchSymbol = vsSemiColon then
    begin
      FSemiColon := FLookahead;
    end;
    FLookahead := FLexer.GetToken;
    exit(LSymbol.StripActions);
  end;
  RaiseError(LSymbol.Position, SParsingErrorExpecting, [TemplateSymbolToString(AMatchSymbol)]);
end;

procedure TTemplateParser.Match(const ASymbol: ITemplateSymbol);
begin
  Match(ASymbol.Token);
end;

function TTemplateParser.MatchNumber(const ASymbol: TTemplateSymbol): extended;
begin
  exit(StrToFloat(MatchValue(ASymbol), FContext.FormatSettings));
end;

function TTemplateParser.MatchValues(const ASymbols: TTemplateSymbolSet; out ASymbol: TTemplateSymbol): string;
var
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;
  if FLookahead.Token in ASymbols then
  begin
    ASymbol := FLookahead.Token;
    result := LookaheadValue;
    FLookahead := FLexer.GetToken;
    exit;
  end;
  RaiseError(LSymbol.Position, SParsingErrorExpecting, [TemplateSymbolToString(ASymbol)]);
end;

function TTemplateParser.MatchValue(const ASymbol: TTemplateSymbol): string;
var
  LSymbol: ITemplateSymbol;
begin
  LSymbol := FLookahead;
  if ASymbol = FLookahead.Token then
  begin
    result := LookaheadValue;

    FLookahead := FLexer.GetToken;
    exit;
  end;
  RaiseError(LSymbol.Position, SParsingErrorExpecting, [TemplateSymbolToString(ASymbol)]);
end;

function TTemplateParser.Parse(const AStream: TStream; const AManagedStream: boolean): ITemplate;

  function GetOptions(const AOptions: TParserOptions): TParserOptions;
  begin
    result := AOptions;
    if eoStripRecurringNewlines in FContext.Options then
      include(result, poStripRecurringNL);
  end;

begin
  FContainerStack.Clear;
  result := PushContainer([]);
  FLexer := CreateTemplateLexer(FContext, AStream, '', AManagedStream);
  FLookahead := FLexer.GetToken;
  if AStream.Size > 0 then
  begin
    RuleStmts(result, []);
  end;
  Match(vsEOF);
  PopContainer;

  if eoOptimiseTemplate in FContext.Options then
    result.OptimiseTemplate(GetOptions(FOptions), FContext.NewLine);

  if eoPrettyPrint in FContext.Options then
    FContext.PrettyPrintOutput(Template.PrettyPrint(result));
end;

function TTemplateParser.PopContainer: ITemplate;
begin
  result := FContainerStack.pop;

  if (eoFlattenTemplate in FContext.Options) or (eoOptimiseTemplate in FContext.Options) then
    result.FlattenTemplate;

end;

function TTemplateParser.PushContainer(const ABeforeNLStripActions: TStripActionSet): ITemplate;
begin
  result := TTemplate.Create();
  FContainerStack.push(result);
end;

function TTemplateParser.AddStripStmtFront(const ATemplate: ITemplate; const AStripActions: TStripActionSet; const ADirection: TStripDirection): ITemplate;
var
  LAdd: ITemplateAdd;
  LStmt: IStripStmt;
begin
  if AStripActions = [] then
    exit(ATemplate);
  result := ATemplate;
  LStmt := TStripStmt.Create(ADirection, AStripActions);

  if supports(ATemplate, ITemplateAdd, LAdd) then
    LAdd.Add(LStmt, TAddLocation.alFront);
end;

{ TValueExpr }

procedure TValueExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TValueExpr.Create(const APosition: IPosition; const AValue: TValue);
begin
  inherited Create(APosition);
  FValue := AValue;
end;

function TValueExpr.GetValue: TValue;
begin
  exit(FValue);
end;

{ TExprList }

procedure TExprList.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

procedure TExprList.AddExpr(const AExpr: IExpr);
var
  LOffset: integer;
begin
  LOffset := length(FExprs);
  SetLength(FExprs, LOffset + 1);
  FExprs[LOffset] := AExpr;
end;

function TExprList.GetExpr(const AOffset: integer): IExpr;
begin
  exit(FExprs[AOffset]);
end;

function TExprList.GetExprCount: integer;
begin
  exit(length(FExprs));
end;

{ TUnaryExpr }

procedure TUnaryExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TUnaryExpr.Create(const APosition: IPosition; const AUnaryOp: TUnaryOp; const ACondition: IExpr);
begin
  inherited Create(APosition, ACondition);
  FUnaryOp := AUnaryOp;
end;

function TUnaryExpr.GetUnaryOp: TUnaryOp;
begin
  exit(FUnaryOp);
end;

{ TVariableExpr }

procedure TVariableExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TVariableExpr.Create(const APosition: IPosition; const AVariable: string);
begin
  inherited Create(APosition);
  FVariable := AVariable;
end;

function TVariableExpr.GetVariable: string;
begin
  exit(FVariable);
end;

{ TFunctionCallExpr }

procedure TFunctionCallExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TFunctionCallExpr.Create(const APosition: IPosition; const AFunction: TArray<TRttiMethod>; const ExprList: IExprList);

begin
  inherited Create(APosition, ExprList);
  FFunctionInfo := AFunction;
end;

function TFunctionCallExpr.GetFunctionInfo: TArray<TRttiMethod>;
begin
  exit(FFunctionInfo);
end;

{ TIfStmt }

procedure TIfStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TIfStmt.Create(const APosition: IPosition; const ACondition: IExpr; const ATrueContainer: ITemplate; const AFalseContainer: ITemplate);
begin
  inherited Create(APosition);
  FCondition := ACondition;
  FTrueContainer := ATrueContainer;
  FFalseContainer := AFalseContainer;
end;

function TIfStmt.GetCondition: IExpr;
begin
  exit(FCondition);
end;

function TIfStmt.GetFalseContainer: ITemplate;
begin
  exit(FFalseContainer);
end;

function TIfStmt.GetTrueContainer: ITemplate;
begin
  exit(FTrueContainer);
end;

procedure TIfStmt.OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string);
begin
  if assigned(FTrueContainer) then
    FTrueContainer.OptimiseTemplate(AOptions, ANewLine);
  if assigned(FFalseContainer) then
    FFalseContainer.OptimiseTemplate(AOptions, ANewLine);
end;

function TIfStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

{ TBinopExpr }

procedure TBinopExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TBinopExpr.Create(const APosition: IPosition; const ALeft: IExpr; const ABinop: TBinOp; const ARight: IExpr);
begin
  inherited Create(APosition);
  FLeft := ALeft;
  FBinop := ABinop;
  FRight := ARight;
end;

destructor TBinopExpr.Destroy;
begin
  FLeft := nil;
  FRight := nil;
  inherited;
end;

function TBinopExpr.GetBinOp: TBinOp;
begin
  exit(FBinop);
end;

function TBinopExpr.GetLeftExpr: IExpr;
begin
  exit(FLeft);
end;

function TBinopExpr.GetRightExpr: IExpr;
begin
  exit(FRight);
end;

{ TPrintStmt }

procedure TPrintStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TForInStmt }

procedure TForInStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TForInStmt.Create(const APosition: IPosition; const AVariable: string; const AForOp: TForOp; const AExpr: IExpr; const AOffsetExpr: IExpr; const ALimitExpr: IExpr; const AContainer: ITemplate; const AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
begin
  inherited Create(APosition, AContainer, AOnBegin, AOnEnd, AOnEmpty, ABetweenItem);
  FVariable := AVariable;
  FForOp := AForOp;
  FExpr := AExpr;
  FOffsetExpr := AOffsetExpr;
  FLimitExpr := ALimitExpr;
end;

function TForInStmt.GetForOp: TForOp;
begin
  exit(FForOp);
end;

function TForInStmt.GetExpr: IExpr;
begin
  exit(FExpr);
end;

function TForInStmt.GetLimitExpr: IExpr;
begin
  exit(FLimitExpr);
end;

function TForInStmt.GetOffsetExpr: IExpr;
begin
  exit(FOffsetExpr);
end;

function TForInStmt.GetVariable: string;
begin
  exit(FVariable);
end;

{ TForRangeStmt }

procedure TForRangeStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TForRangeStmt.Create(const APosition: IPosition; const AVariable: string; const AForOp: TForOp; const ALowExpr: IExpr; const AHighExpr: IExpr; const AStep: IExpr; const AContainer: ITemplate; const AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
begin
  inherited Create(APosition, AContainer, AOnBegin, AOnEnd, AOnEmpty, ABetweenItem);
  FVariable := AVariable;
  FForOp := AForOp;
  FLowExpr := ALowExpr;
  FHighExpr := AHighExpr;
  FStepExpr := AStep;
end;

function TForRangeStmt.GetForOp: TForOp;
begin
  exit(FForOp);
end;

function TForRangeStmt.GetHighExpr: IExpr;
begin
  exit(FHighExpr);
end;

function TForRangeStmt.GetLowExpr: IExpr;
begin
  exit(FLowExpr);
end;

function TForRangeStmt.GetStepExpr: IExpr;
begin
  exit(FStepExpr);
end;

function TForRangeStmt.GetVariable: string;
begin
  exit(FVariable);
end;

{ TAssignStmt }

procedure TAssignStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TAssignStmt.Create(const APosition: IPosition; const AVariable: string; const AExpr: IExpr);
begin
  inherited Create(APosition, AExpr);
  FVariable := AVariable;
end;

function TAssignStmt.GetVariable: string;
begin
  exit(FVariable);
end;

{ TTemplateContainer }

procedure TTemplate.Accept(const AVisitor: ITemplateVisitor);
var
  i: integer;
begin
  for i := 0 to FArray.Count - 1 do
  begin
    FArray[i].Accept(AVisitor);
  end;
end;

procedure TTemplate.Add(const AItem: IStmt; const AAddLocation: TAddLocation);
begin
  case AAddLocation of
    TAddLocation.alFront:
      FArray.Insert(0, AItem);
    TAddLocation.alLast:
      FArray.Add(AItem);
  end;
end;

constructor TTemplate.Create;
begin
  FPosition := TPosition.Create('', 1, 1);
  FArray := TList<IStmt>.Create;
end;

destructor TTemplate.Destroy;
begin
  FArray.Free;
  inherited;
end;

function TTemplate.GetCount: integer;
begin
  exit(FArray.Count);
end;

function TTemplate.GetFilename: string;
begin
  exit(FPosition.FileName);
end;

function TTemplate.GetLastItem: IStmt;
begin
  if GetCount = 0 then
    exit(nil)
  else
    exit(GetItem(GetCount - 1));
end;

function TTemplate.GetLine: integer;
begin
  exit(FPosition.line);
end;

function TTemplate.GetPos: integer;
begin
  exit(FPosition.pos);
end;

procedure TTemplate.FlattenTemplate;
var
  LStmt: IStmt;
  LStmts: TList<IStmt>;
begin
  LStmts := TList<IStmt>.Create;
  try
    for LStmt in FArray do
    begin
      if IsAny(LStmt, [IEndStmt, ICommentStmt, IElseStmt, INoopStmt]) then
      begin
        continue;
      end;
      LStmts.AddRange(LStmt.Flatten);
    end;
    FArray.Clear;
    FArray.AddRange(LStmts);
  finally
    LStmts.Free;
  end;
end;

procedure TTemplate.OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string);
var
  LStmt: IStmt;
  LStmts: TList<IStmt>;
  i: integer;
  j: integer;
  LScanStmt: IStripStmt;
  LReviewStmt: IStmt;

  function CanStrip(const AAction: TStripActionSet; const AStmt: IStmt; out AIsNL: boolean): boolean; overload;
  begin
    if IsPrintNLOrWhitespaceExpr(AStmt, AIsNL) then
    begin
      if AIsNL then
        exit(saNL in AAction)
      else
        exit(saWhitespace in AAction);
    end;
    if supports(AStmt, IStripStmt) then
      exit(true);
    exit(false);
  end;
  function CanStrip(const AAction: TStripActionSet; const AStmt: IStmt): boolean; overload;
  var
    LIsNL: boolean;
  begin
    exit(CanStrip(AAction, AStmt, LIsNL));
  end;

  procedure Scan(const ADelta: integer; const ATest: TPredicate<integer>);
  begin
    j := i + ADelta;
    while ATest(j) do
    begin
      LReviewStmt := FArray[j];
      if CanStrip(LScanStmt.Action, LReviewStmt) then
      begin
        FArray[j] := nil;
      end
      else
        break;
      j := j + ADelta;
    end;
    FArray[i] := nil;
  end;

  procedure ScanLeft;
  begin
    j := i + -1;
    while j >= 0 do
    begin
      LReviewStmt := FArray[j];
      if not assigned(LReviewStmt) or CanStrip(LScanStmt.Action, LReviewStmt) then
      begin
        FArray[j] := nil;
      end
      else
        break;
      j := j + -1;
    end;
    FArray[i] := nil;
  end;

  procedure ScanRight;
  var
    LIsNL: boolean;
  begin
    j := i + 1;
    LIsNL := false;
    while j <= FArray.Count - 1 do
    begin
      LReviewStmt := FArray[j];
      if not assigned(LReviewStmt) or CanStrip(LScanStmt.Action, LReviewStmt, LIsNL) then
      begin
        FArray[j] := nil;
        if LIsNL then
          break;
      end
      else
        break;
      j := j + 1;
    end;
    FArray[i] := nil;
  end;

  procedure StripNilStmts;
  var
    LStmt: IStmt;
  begin
    LStmts.Clear;
    for LStmt in FArray do
    begin
      if LStmt <> nil then
        LStmts.Add(LStmt);
    end;
    FArray.Clear;
    FArray.AddRange(LStmts);
  end;

  function JoinTextStmts: boolean;
  var
    LSB: TStringBuilder;
    LStr: string;
    LJoin: boolean;
    LLastStr: string;
  begin
    result := false;
    LSB := TStringBuilder.Create;
    try
      i := 0;
      while i <= FArray.Count - 1 do
      begin
        LStmt := FArray[i];
        if IsPrintTextExpr(LStmt, LStr) then
        begin
          LSB.Clear;
          LSB.append(LStr);
          LLastStr := LStr;
          j := i + 1;
          LJoin := false;
          while j <= FArray.Count - 1 do
          begin
            LReviewStmt := FArray[j];
            if IsPrintTextExpr(LReviewStmt, LStr) then
            begin
              LJoin := true;
              result := true;
              FArray[j] := nil;
              if not(poStripRecurringNL in AOptions) or (LStr <> ANewLine) or (LLastStr <> LStr) then
              begin
                LSB.append(LStr);
                LLastStr := LStr;
              end;
            end
            else
            begin
              break;
            end;
            inc(j);
          end;
          if LJoin then
          begin
            FArray[i] := TPrintStmt.Create(nil, TValueExpr.Create(nil, LSB.tostring));
            i := j + 1;
            continue;
          end;
        end;
        inc(i);
      end;
    finally
      LSB.Free;
    end;
  end;

begin
  LStmts := TList<IStmt>.Create;
  try
    i := 0;
    while i <= FArray.Count - 1 do
    begin
      LStmt := FArray[i];
      if not assigned(LStmt) then
      begin
        inc(i);
        continue;
      end;
      if IsStripStmt(LStmt, LScanStmt) then
      begin
        case LScanStmt.Direction of
          sdLeft:
            ScanLeft;
          sdRight:
            ScanRight;
        end;
      end
      else
      begin
        LStmt.OptimiseTemplate(AOptions, ANewLine);
      end;
      inc(i);
    end;
    StripNilStmts;
    if JoinTextStmts then
      StripNilStmts;
  finally
    LStmts.Free;
  end;
  FArray.Capacity := FArray.Count;
end;

procedure TTemplate.SetFilename(const AFilename: string);
begin
  FPosition.FileName := AFilename;
end;

procedure TTemplate.SetLine(const Aline: integer);
begin
  FPosition.line := Aline;
end;

procedure TTemplate.SetPos(const Apos: integer);
begin
  FPosition.pos := Apos;
end;

function TTemplate.GetItem(const AOffset: integer): IStmt;
begin
  exit(FArray[AOffset]);
end;

{ TWhileStmt }

procedure TWhileStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TWhileStmt.Create(const APosition: IPosition; const ACondition: IExpr; const AOffsetExpr: IExpr; const ALimitExpr: IExpr; const AContainer: ITemplate; const AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
begin
  inherited Create(APosition, AContainer, AOnBegin, AOnEnd, AOnEmpty, ABetweenItem);
  FCondition := ACondition;
  FOffsetExpr := AOffsetExpr;
  FLimitExpr := ALimitExpr;
end;

function TWhileStmt.GetCondition: IExpr;
begin
  exit(FCondition);
end;

function TWhileStmt.GetLimitExpr: IExpr;
begin
  exit(FLimitExpr);
end;

function TWhileStmt.GetOffsetExpr: IExpr;
begin
  exit(FOffsetExpr);
end;

{ TContinueStmt }

procedure TContinueStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TBreakStmt }

procedure TBreakStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TEndStmt }

procedure TEndStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TVariableDerefExpr }

procedure TVariableDerefExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TVariableDerefExpr.Create(const APosition: IPosition; const ADerefType: TDerefType; const AVariable: IExpr; const ADeref: IExpr);
begin
  inherited Create(APosition, AVariable);
  FDerefType := ADerefType;
  FDeref := ADeref;
end;

function TVariableDerefExpr.GetDerefExpr: IExpr;
begin
  exit(FDeref);
end;

function TVariableDerefExpr.GetDerefType: TDerefType;
begin
  exit(FDerefType);
end;

{ TIncludeStmt }

procedure TIncludeStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TElseStmt }

procedure TElseStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TElIfStmt }

procedure TElIfStmt.Accept(const AVisitor: ITemplateVisitor);
begin
end;

{ TCommentStmt }

procedure TCommentStmt.Accept(const AVisitor: ITemplateVisitor);
begin
end;

{ TMethodCallExpr }

procedure TMethodCallExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TMethodCallExpr.Create(const APosition: IPosition; const AObjectExpr: IExpr; const AMethod: string; const AExprList: IExprList);
begin
  inherited Create(APosition, AExprList);
  FObjectExpr := AObjectExpr;
  FMethod := AMethod;
end;

function TMethodCallExpr.GetMethod: string;
begin
  exit(FMethod);
end;

function TMethodCallExpr.GetObject: IExpr;
begin
  exit(FObjectExpr);
end;

{ TEncodeStmt }

procedure TEncodeExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TProcessTemplateStmt }

procedure TProcessTemplateStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TProcessTemplateStmt.Create(const APosition: IPosition; const AContainer: ITemplate; const AAllowNewLine: boolean);
begin
  inherited Create(APosition, AContainer);
  FAllowNewline := AAllowNewLine;
end;

function TProcessTemplateStmt.GetAllowNewLine: boolean;
begin
  exit(FAllowNewline);
end;

procedure TProcessTemplateStmt.SetAllowNewLine(const AAllow: boolean);
begin
  FAllowNewline := AAllow;
end;

{ TDefineTemplateStmt }

procedure TDefineTemplateStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TDefineTemplateStmt.Create(const APosition: IPosition; const AName: IExpr; const AContainer: ITemplate);
begin
  inherited Create(APosition, AContainer);
  FName := AName;
end;

function TDefineTemplateStmt.GetName: IExpr;
begin
  exit(FName);
end;

function TDefineTemplateStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

{ TWithStmt }

procedure TWithStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TWithStmt.Create(const APosition: IPosition; const AExpr: IExpr; const AContainer: ITemplate);
begin
  inherited Create(APosition, AContainer);
  FExpr := AExpr;
end;

function TWithStmt.GetExpr: IExpr;
begin
  exit(FExpr);
end;

function TWithStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

{ TIfExpr }

procedure TTernaryExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TTernaryExpr.Create(const APosition: IPosition; const ACondition, ATrueExpr, AFalseExpr: IExpr);
begin
  inherited Create(APosition, ACondition);
  FTrueExpr := ATrueExpr;
  FFalseExpr := AFalseExpr;
end;

function TTernaryExpr.GetFalseExpr: IExpr;
begin
  exit(FFalseExpr);
end;

function TTernaryExpr.GetTrueExpr: IExpr;
begin
  exit(FTrueExpr);
end;

{ TArrayExpr }

procedure TArrayExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

procedure initOps;
var
  LSymbol: TTemplateSymbol;
begin
  for LSymbol := low(TTemplateSymbol) to high(TTemplateSymbol) do
    GTemplateBinOps[LSymbol] := boInvalid;
  GTemplateBinOps[vsIn] := boIN;
  GTemplateBinOps[vsAND] := boAND;
  GTemplateBinOps[vsOR] := boOR;
  GTemplateBinOps[vsPLUS] := boPlus;
  GTemplateBinOps[vsMinus] := boMinus;
  GTemplateBinOps[vsMULT] := boMult;
  GTemplateBinOps[vsSLASH] := boSlash;
  GTemplateBinOps[vsDIV] := boDiv;
  GTemplateBinOps[vsMOD] := boMod;
  GTemplateBinOps[vsLT] := boLT;
  GTemplateBinOps[vsLTE] := boLTE;
  GTemplateBinOps[vsGT] := boGT;
  GTemplateBinOps[vsGTE] := boGTE;
  GTemplateBinOps[vsEQ] := boEQ;
  GTemplateBinOps[vsNotEQ] := boNotEQ;
end;

{ TRequireStmt }

procedure TRequireStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TRequireStmt.Create(const APosition: IPosition; const AExprList: IExprList);
begin
  inherited Create(APosition);
  FExprList := AExprList;
end;

function TRequireStmt.GetExprList: IExprList;
begin
  exit(FExprList);
end;

{ TAbstractStmtWithExpr }

constructor TAbstractStmtWithExpr.Create(const APosition: IPosition; const AExpr: IExpr);
begin
  inherited Create(APosition);
  FExpr := AExpr;
end;

function TAbstractStmtWithExpr.GetExpr: IExpr;
begin
  exit(FExpr);
end;

{ TAbstractStmtWithContainer }

constructor TAbstractStmtWithContainer.Create(const APosition: IPosition; const AContainer: ITemplate);
begin
  inherited Create(APosition);
  FContainer := AContainer;
end;

function TAbstractStmtWithContainer.GetContainer: ITemplate;
begin
  exit(FContainer);
end;

procedure TAbstractStmtWithContainer.OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string);
begin
  if assigned(FContainer) then
    FContainer.OptimiseTemplate(AOptions, ANewLine);
end;

{ TAbstractExprWithExprList }

constructor TAbstractExprWithExprList.Create(const APosition: IPosition; AExprList: IExprList);
begin
  inherited Create(APosition);
  FExprList := AExprList;
end;

function TAbstractExprWithExprList.GetExprList: IExprList;
begin
  exit(FExprList);
end;

{ TAbstractExprWithExpr }

constructor TAbstractExprWithExpr.Create(const APosition: IPosition; const AExpr: IExpr);
begin
  inherited Create(APosition);
  FExpr := AExpr;
end;

function TAbstractExprWithExpr.GetExpr: IExpr;
begin
  exit(FExpr);
end;

{ TCycleStmt }

procedure TCycleStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TCycleStmt.Create(const APosition: IPosition; const AList: IExprList);
begin
  inherited Create(APosition);
  FExprList := AList;
end;

function TCycleStmt.GetList: IExprList;
begin
  exit(FExprList);
end;

{ TDebugStmt }

procedure TDebugStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TDebugStmt.Create(const AStmt: IStmt);
begin
  FStmt := AStmt;
end;

function TDebugStmt.GetStmt: IStmt;
begin
  exit(FStmt);
end;

{ TLoopStmt }

constructor TLoopStmt.Create(const APosition: IPosition; const AContainer, AOnBegin, AOnEnd, AOnEmpty, ABetweenItem: ITemplate);
begin
  inherited Create(APosition, AContainer);
  FOnBegin := AOnBegin;
  FOnEnd := AOnEnd;
  FOnEmpty := AOnEmpty;
  FBetweenItem := ABetweenItem;
end;

function TLoopStmt.GetBetweenItemContainer: ITemplate;
begin
  exit(FBetweenItem);
end;

function TLoopStmt.GetOnEmptyContainer: ITemplate;
begin
  exit(FOnEmpty);
end;

function TLoopStmt.GetOnEndContainer: ITemplate;
begin
  exit(FOnEnd);
end;

procedure TLoopStmt.OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string);
begin
  if assigned(FContainer) then
    FContainer.OptimiseTemplate(AOptions, ANewLine);
  if assigned(FOnBegin) then
    FOnBegin.OptimiseTemplate(AOptions, ANewLine);
  if assigned(FOnEnd) then
    FOnEnd.OptimiseTemplate(AOptions, ANewLine);
  if assigned(FOnEmpty) then
    FOnEmpty.OptimiseTemplate(AOptions, ANewLine);
  if assigned(FBetweenItem) then
    FBetweenItem.OptimiseTemplate(AOptions, ANewLine);
  if assigned(FBetweenItem) then
    FBetweenItem.OptimiseTemplate(AOptions, ANewLine);
end;

function TLoopStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

function TLoopStmt.GetOnBeginContainer: ITemplate;
begin
  exit(FOnBegin);
end;

{ TCompositeStmt }

procedure TCompositeStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TCompositeStmt.Create(const AFirstStmt, ASecondStmt: IStmt);
begin
  FFirstStmt := AFirstStmt;
  FSecondStmt := ASecondStmt;
end;

function TCompositeStmt.Flatten: TArray<IStmt>;
var
  LStmts: TList<IStmt>;
begin
  LStmts := TList<IStmt>.Create;
  try
    LStmts.Add(FFirstStmt);
    LStmts.Add(FSecondStmt);
    exit(Sempare.Template.Parser.Flatten(LStmts));
  finally
    LStmts.Free;
  end;
end;

function TCompositeStmt.GetFirstStmt: IStmt;
begin
  exit(FFirstStmt);
end;

function TCompositeStmt.GetSecondStmt: IStmt;
begin
  exit(FSecondStmt);
end;

{ TStripStmt }

procedure TStripStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TStripStmt.Create(const ADirection: TStripDirection; const AAction: TStripActionSet);
begin
  FDirection := ADirection;
  FAction := AAction;
end;

function TStripStmt.GetAction: TStripActionSet;
begin
  exit(FAction);
end;

function TStripStmt.GetHasEnd: boolean;
begin
  exit(FHasEnd);
end;

function TStripStmt.GetDirection: TStripDirection;
begin
  exit(FDirection);
end;

function TStripStmt.GetIndent: string;
begin
  exit(FIndent);
end;

procedure TStripStmt.SetHasEnd(const AHasEnd: boolean);
begin
  FHasEnd := AHasEnd;
end;

procedure TStripStmt.SetIndent(const AIndent: string);
begin
  FIndent := AIndent;
end;

{ TBlockStmt }

procedure TBlockStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TBlockStmt.Create(const APosition: IPosition; const AName: IExpr; const AContainer: ITemplate);
begin
  inherited Create(APosition);
  FName := AName;
  FContainer := AContainer;
end;

function TBlockStmt.GetContainer: ITemplate;
begin
  exit(FContainer);
end;

function TBlockStmt.GetName: IExpr;
begin
  exit(FName);
end;

function TBlockStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

function TBlockStmt.NameAsString(const AEvalVisitor: IEvaluationTemplateVisitor): string;
begin
  exit(AEvalVisitor.EvalExprAsString(FName));
end;

procedure TBlockStmt.OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string);
begin
  FContainer.OptimiseTemplate(AOptions, ANewLine);
end;

{ TExtendsStmt }

procedure TExtendsStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TExtendsStmt.Create(const APosition: IPosition; const AName: IExpr; const ABlockContainer: ITemplate);
begin
  inherited Create(APosition);
  FBlockContainer := ABlockContainer;
  FName := AName;
end;

function TExtendsStmt.GetBlockContainer: ITemplate;
begin
  exit(FBlockContainer);
end;

function TExtendsStmt.GetName: IExpr;
begin
  exit(FName);
end;

function TExtendsStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

function TExtendsStmt.NameAsString(const AEvalVisitor: IEvaluationTemplateVisitor): string;
begin
  exit(AEvalVisitor.EvalExprAsString(FName));
end;

procedure TExtendsStmt.OptimiseTemplate(const AOptions: TParserOptions; const ANewLine: string);
begin
  FBlockContainer.OptimiseTemplate(AOptions, ANewLine);
end;

{ TNoopStmt }

procedure TNoopStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

{ TNewLineExpr }

procedure TNewLineExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TNewLineExpr.Create(const APosition: IPosition; const AValue: TValue);
begin
  inherited Create(APosition, AValue);
end;

{ TWhitespaceExpr }

procedure TWhitespaceExpr.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TWhitespaceExpr.Create(const APosition: IPosition; const AValue: TValue);
begin
  inherited Create(APosition, AValue);
end;

{ TIgnoreNLStmt }

procedure TIgnoreNLStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TIgnoreNLStmt.Create(const APosition: IPosition; const AContainer: ITemplate);
begin
  inherited Create(APosition, AContainer);
end;

function TIgnoreNLStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

{ TIgnoreWSStmt }

procedure TIgnoreWSStmt.Accept(const AVisitor: ITemplateVisitor);
begin
  AVisitor.Visit(self);
end;

constructor TIgnoreWSStmt.Create(const APosition: IPosition; const AContainer: ITemplate);
begin
  inherited Create(APosition, AContainer);
end;

function TIgnoreWSStmt.GetHasEnd: boolean;
begin
  exit(true);
end;

initialization

initOps;

end.
