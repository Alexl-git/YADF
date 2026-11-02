# --d10 SeedDeclaredNames scope (task 10, TODO "guard cannot see a DUPLICATE
# declaration"): the names a routine already declares are found even when a local
# record type or a nested routine sits between its var section and its begin.
# Scanning back used to stop at that block's `end`, so an inline var of an
# already-declared name was hoisted as a SECOND declaration (E2004) -- and the
# guard, which compares token bags, cannot see a duplicate. The nested routine's
# own locals must NOT count as the outer routine's names.
# Usage: pwsh Test\test_d10_seed_scope.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'd10_seed_scope' $exe
$fail = 0
$ini = New-TempOut '.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`n")
$src = New-TempOut '.pas'
$unit = [IO.Path]::GetFileNameWithoutExtension($src)
$text = @"
unit $unit;

interface

function Outer(N: Integer): Integer;

implementation

function Outer(N: Integer): Integer;
var
  X: Integer;
  S: string;
type
  TPair = record
    A: Integer;
    B: Integer;
  end;

  procedure Bump(var V: Integer);
  var
    Y: Integer;
  begin
    Y:= 1;
    V:= V + Y;
  end;

begin
  X:= N;
  S:= '';
  Bump(X);
  if N > 0 then
  begin
    var Y: string:= 'a';
    S:= S + Y;
  end;
  if N > 1 then
  begin
    var X: Integer:= 2;
    Result:= X + Length(S);
  end
  else
    Result:= X;
end;

end.
"@ -replace "`r?`n", "`r`n"
[IO.File]::WriteAllText($src, $text)
$out = & $exe --ini $ini --d10 --stdout $src 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Fail "d10_seed_scope: exit $LASTEXITCODE -- $out" }
$xDecls = ([regex]::Matches($out, '(?m)^\s*X\s*:\s*Integer\s*;')).Count
if ($xDecls -ne 1) { Fail "d10_seed_scope: expected ONE 'X: Integer' declaration, found $xDecls" }
MustMatch    $out '(?m)^\s*X\s*:= 2;\r?$'            'same-type duplicate: assignment kept'
# The nested routine's local Y (Integer) is not the outer routine's: the outer
# inline `var Y: string` is hoisted, not flagged as a different-type collision.
MustMatch    $out '(?m)^\s*Y\s*:\s*string\s*;'        'outer Y hoisted'
MustNotMatch $out "name 'Y' already hoisted"          'nested local Y not seen as an outer name'
Remove-Item $src, $ini -Force -ErrorAction SilentlyContinue
Finish 'd10_seed_scope'
