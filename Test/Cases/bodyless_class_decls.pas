unit bodyless_class_decls;

{
  Regression fixture -- "ladder" indentation of bodyless type declarations.

  A class / interface declaration that has NO body terminates at its `;` and
  never reaches an `end`. ReindentByDepth pushes a stack level when it sees
  `= class` / `= interface`, and used to pop that level only on `end`, so every
  bodyless declaration leaked one level and each following sibling was indented
  one step deeper -- a staircase:

      EAlpha                  = class(Exception);
        EBeta                 = class(Exception);
          TAlphaClass         = class of EAlpha;

  Every type declaration in the block below is a SIBLING and must sit at
  exactly one indent step under `type`. The bodied declarations are here to
  prove the balanced case still opens and closes correctly.
}

interface

uses
  System.SysUtils;

type
  EAlpha = class(Exception);
  EBeta = class(Exception);
  EGamma = class(Exception);

  TAlphaClass = class of EAlpha;
  TBetaClass = class of EBeta;

  TNodeRef = class;
  IHandler = interface;

  TOwner = class(TObject)
  private
    FNode: TNodeRef;
    FHandler: IHandler;
  public
    property Node: TNodeRef read FNode write FNode;
    property Handler: IHandler read FHandler write FHandler;
  end;

  IHandler = interface(IInterface)
    procedure Handle;
  end;

  TNodeRef = class(TObject)
  private
    FName: string;
  public
    procedure Clear;
    property Name: string read FName write FName;
  end;

  EDelta = class(Exception);

  TRec = record
    X: Integer;
  end;

  EEpsilon = class(Exception);

implementation

procedure TNodeRef.Clear;
begin
  FName := '';
end;

end.
