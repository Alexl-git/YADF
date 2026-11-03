program review1102_after_end;
{$APPTYPE CONSOLE}
// REVIEW-2026-11-02-corruption L1: the compiler ignores everything after the
// final end. -- the formatter must leave that tail verbatim, not decline the file.
begin
  Writeln('ok');
end.
Trailing junk after end. with an 'unbalanced quote and { open brace
and more junk
