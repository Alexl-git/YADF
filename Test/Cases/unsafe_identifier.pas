unit unsafe_identifier;

{ `unsafe` is a DIRECTIVE, not a reserved word, so an identifier spelled Unsafe
  must keep the casing the author gave it. The vendored DelphiAST lexer used to
  classify it as a hard keyword (TokenID = ptUnsafe) instead of an ExID, so
  LowercaseKeywords rewrote the user's identifier to `unsafe`. Every other
  directive (Virtual, Overload, Static) is an ExID and was already left alone --
  this fixture pins both halves of that consistency. }

interface

type
  TFoo = class
  private
    FUnsafe: Boolean;
  public
    property Unsafe: Boolean read FUnsafe;
    procedure DoIt(const Unsafe: Boolean); Virtual;
  end;

implementation

procedure TFoo.DoIt(const Unsafe: Boolean);
begin
  if Unsafe then
    FUnsafe := True;
end;

end.
