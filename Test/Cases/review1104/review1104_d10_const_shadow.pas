program review1104_d10_const_shadow;
{$APPTYPE CONSOLE}
// --d10 follow-up to REVIEW-2026-11-04-corruption H1 (aa06318): an inline
// `const` was hoisted to the routine's const section without the shadow check
// an inline var gets, so a const whose name also binds outside its block (a
// unit global, a class field, a `with` member) captured every reference to
// that name in the routine -- a silent value change.

type
  TFoo = class
  public
    K: Integer;
    procedure Go;
  end;

  TRec = record
    A: Integer;
  end;

var
  G: Integer;

procedure UseGlobal;
begin
  if G > 0 then
  begin
    const G = 30;
    Writeln('const inner ', G);
  end;
  Writeln('const outer ', G);
end;

procedure TFoo.Go;
begin
  if K > 0 then
  begin
    const K = 40;
    Writeln('field inner ', K);
  end;
  Writeln('field outer ', K);
end;

procedure WithShadow;
var
  R: TRec;
begin
  R.A:= 7;
  with R do
  begin
    const A = 99;
    Writeln('with inner ', A);
  end;
  Writeln('with again ', R.A);
end;

// A legitimate hoist stays hoisted: C is used only inside its block.
procedure Legit;
begin
  if G > 0 then
  begin
    const C = 4;
    Writeln('legit ', C);
  end;
end;

var
  F: TFoo;
begin
  G:= 1;
  UseGlobal;
  F:= TFoo.Create;
  try
    F.K:= 2;
    F.Go;
  finally
    F.Free;
  end;
  WithShadow;
  Legit;
end.