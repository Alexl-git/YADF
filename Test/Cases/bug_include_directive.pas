unit bug_include_directive;

interface

{$I jedi.inc}
{$I extra.inc}

uses
  System.SysUtils;

{$IFDEF SOMESYM}
procedure P;
{$ENDIF}

implementation

{$IFDEF SOMESYM}
procedure P; begin end;
{$ENDIF}

end.
