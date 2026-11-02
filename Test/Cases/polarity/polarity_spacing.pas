unit polarity_spacing;

// Q12 / Q13 polarity fixture (test_option_polarity.ps1, SPEC-2026-11-01 task 2d-4b).
// Q12 (rule): no blank after "(" or before ")" -- Sq( 3 ), ( Alpha * 2 ).
// Q13: with every align option off, declarations come out plain "Name: Type;"
// and "Name = Value;" -- the author's column padding below is not kept.

interface

const
  SpOne     = 1;
  SpTwenty  = 20;

function Sq(V: Integer): Integer;
procedure RunSpacing;

implementation

uses
  System.SysUtils;

function Sq(V: Integer): Integer;
begin
  Result:= V * V;
end;

procedure RunSpacing;
var
  Alpha   : Integer;
  B       : string ;
begin
  Alpha:= Sq( SpOne ) + ( SpTwenty * 2 );
  B:= IntToStr( Alpha );
  if ( Alpha > 0 ) and ( B <> '' ) then
    Alpha:= 0;
end;

end.