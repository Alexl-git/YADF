unit section_keywords;

// Regression (2026-10-13, ORM3 BASICS.PAS): the `type` of a distinct-type
// alias was taken for a section opener -- the line broke after it and a
// phantom section indented the following resourcestring block. resourcestring
// and threadvar were not section keywords at all.

interface

type
  UTF8String = type AnsiString;

resourcestring
  SDotStar = '.*';
  SEmpty   = '';

type
  TName = type string;
  TAbc  = class(TObject)
  end;

const
  C1 = 1;

threadvar
  GCount: Integer;

implementation

end.