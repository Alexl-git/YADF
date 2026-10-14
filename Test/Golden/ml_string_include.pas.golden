unit ml_string_include;

// Regression fixture (review 2026-10-14): the include-directive shield
// scanner did not know multi-line ''' strings. An odd number of apostrophes
// inside one desynchronised the scan for the rest of the file: a later real
// {$I ...} was left unshielded and silently dropped, and {$I ...} TEXT inside
// a later string got the include-shield sentinel written into it.

interface

const
  S1 = '''
    don't {$I foo.inc}
    ''';
  S2 = '''
    plain {$INCLUDE bar.inc}
    ''';

procedure Bar(A: Integer; {$I params.inc} B: Integer);

implementation

procedure Bar(A: Integer; {$I params.inc} B: Integer);
begin
end;

end.
