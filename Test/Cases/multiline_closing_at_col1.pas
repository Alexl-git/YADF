unit multiline_closing_at_col1;

interface

const
  CMsg = '''
Hello world;
Second line;
''';

  CMsg2 =
    '''
Indented open, closing at col1;
''';

  // Interior contains a lone apostrophe, doubled '' , and tokens that look
  // like Pascal keywords/comments -- none of it must be touched, and the
  // begin/end inside must NOT corrupt indentation of real code afterwards.
  CMsg3 = '''
it's a test; don't break it
begin end { not a brace } // not a comment
    keep   this    spacing;
''';

implementation

procedure RealCodeAfterString;
begin
  if True then
    WriteLn(CMsg3);
end;

end.
