unit polarity_params;

// BreakParamsOnePerLine polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\break-params-one-per-line.md. ParamsInline = 2 params
// on one line; ParamsGrouped = grouped "const PC, PD"; ParamsSpread = already
// one parameter per line; the call in CallSite must never be touched.

interface

procedure ParamsInline(const PA: string; PB: Integer);
procedure ParamsGrouped(const PC, PD: string);
procedure ParamsSpread(
  const PE: string;
  PF: Integer);

implementation

procedure ParamsInline(const PA: string; PB: Integer);
begin
end;

procedure ParamsGrouped(const PC, PD: string);
begin
end;

procedure ParamsSpread(
  const PE: string;
  PF: Integer);
begin
end;

procedure CallSite;
begin
  ParamsInline('a', 1);
end;

end.
