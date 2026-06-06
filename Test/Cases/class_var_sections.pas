unit class_var_sections;

interface

type
  TTestProtectedClassVars = class
  protected
  var
    Var1, Var2: Boolean;
  class var
    CVar1, CVar2: string;
  var
    Var3, Var4: string;
  end;

implementation

end.
