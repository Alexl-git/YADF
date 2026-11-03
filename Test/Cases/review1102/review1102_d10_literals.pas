program review1102_d10_literals;
{$APPTYPE CONSOLE}
// REVIEW-2026-11-02-corruption H1 + M1: --d10 must infer the type Delphi
// infers for an integer literal (Integer / Cardinal / Int64 by magnitude,
// decimal, hex, binary, digit separators) and a real type for the dot-less
// exponent form 1e3.
uses System.SysUtils;
begin
  var Small := 2147483647;
  var Big := 2147483648;
  var Big10 := 10000000000;
  var Neg := -2147483649;
  var UHex := $FFFFFFFF;
  var Big64 := $1FFFFFFFF;
  var F1 := 1.0;
  var F2 := 1e3;
  var F3 := 1.5e-3;
  var Bin := %1111;
  var Us := 1_000;
  var UsBig := 3_000_000_000;
  UHex:= UHex + 1;
  Writeln(Small, ' ', Big, ' ', Big10, ' ', Neg, ' ', UHex, ' ', Big64, ' ', Bin, ' ', Us, ' ', UsBig);
  Writeln(F1:0:1, ' ', F2:0:0, ' ', F3:0:4);
  Writeln(SizeOf(Small), SizeOf(Big), SizeOf(Big10), SizeOf(UHex), SizeOf(Big64), SizeOf(UsBig));
  for var I := 4294967294 to 4294967295 do
    Write(I, ' ');
  Writeln;
end.