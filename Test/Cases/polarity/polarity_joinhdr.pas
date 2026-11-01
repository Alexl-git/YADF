unit polarity_joinhdr;

// JoinRoutineHeaders polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\join-routine-headers.md. JhSplit = a header the
// author broke across lines; JhLong = a long header broken once (re-wrapped at
// MaxLen while joining is on); JhOne = a single-parameter header.

interface

procedure JhSplit(
  const PA: string;
  PB: Integer);
procedure JhLong(const PrefixOne: string; PrefixTwo: Integer;
  const PrefixThree: string; PrefixFour: Boolean);
procedure JhOne(const PA: string);

implementation

procedure JhSplit(
  const PA: string;
  PB: Integer);
begin
end;

procedure JhLong(const PrefixOne: string; PrefixTwo: Integer;
  const PrefixThree: string; PrefixFour: Boolean);
begin
end;

procedure JhOne(const PA: string);
begin
end;

end.
