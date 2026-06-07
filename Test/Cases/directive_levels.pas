unit directive_levels;

interface

{$IF Defined(MSWINDOWS)}
const Platform = 'win';
{$ELSE}
const Platform = 'other';
{$ENDIF}

implementation

end.
