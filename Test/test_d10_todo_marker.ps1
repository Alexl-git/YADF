# --d10 "resolve manually" flags carry a distinct marker and are owned by YADF
# (owner decision 2026-11-02, task 11 item d). Every TODO the --d10 path inserts
# starts `// TODO -oYADF -cd10 :`. A --d10 run adds each flag once and a second
# --d10 run changes nothing; a run WITHOUT --d10 removes exactly those marked
# flags (a trailing flag and an own-line flag above a `for`), never another
# comment -- a user TODO that looks alike but lacks the marker survives -- and
# the result equals the plain format of the original source.
# Usage: pwsh Test\test_d10_todo_marker.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'd10_todo_marker' $exe
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
  R: string;
begin
  X:= N;
  R:= '';
  // TODO -oYADF : a user note that only looks like a flag
  // TODO -cd10 : the user's own d10 note
  if N > 0 then
  begin
    var X: string:= 'a';
    R:= R + X;
  end;
  for var R: Integer:= 1 to N do
    Inc(X, R);
  Result:= X;
end;

end.
"@ -replace "`r?`n", "`r`n"
[IO.File]::WriteAllText($src, $text)
$marker = '// TODO -oYADF -cd10 :'
$d1 = New-TempOut '.pas'; $d2 = New-TempOut '.pas'; $p0 = New-TempOut '.pas'; $p1 = New-TempOut '.pas'
Copy-Item $src $d1; & $exe --ini $ini --d10 $d1 *> $null
if ($LASTEXITCODE -ne 0) { Fail "d10 run: exit $LASTEXITCODE" }
$o1 = [IO.File]::ReadAllText($d1)
$n1 = ([regex]::Matches($o1, [regex]::Escape($marker))).Count
if ($n1 -ne 2) { Fail "d10 run: expected 2 marked flags (trailing + for-var line), found $n1`n$o1" }
MustNotMatch $o1 '//\s*TODO -oYADF : (?!a user note)' 'd10 run: no unmarked YADF flag'
Copy-Item $d1 $d2; & $exe --ini $ini --d10 $d2 *> $null
if ($LASTEXITCODE -ne 0) { Fail "second d10 run: exit $LASTEXITCODE" }
if ([IO.File]::ReadAllText($d2) -ne $o1) { Fail 'second d10 run changed the output (flags duplicated or moved)' }
# Plain run of the d10 output vs plain run of the original.
Copy-Item $d1 $p1; $msg = & $exe --ini $ini $p1 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Fail "plain run on d10 output: exit $LASTEXITCODE -- $($msg.Trim())" }
Copy-Item $src $p0; & $exe --ini $ini $p0 *> $null
$q1 = [IO.File]::ReadAllText($p1)
MustNotMatch $q1 '-oYADF -cd10' 'plain run removes every marked flag'
MustContain  $q1 '// TODO -oYADF : a user note that only looks like a flag' 'user TODO without the marker survives'
MustContain  $q1 '// TODO -cd10 : the user''s own d10 note' 'user d10 TODO without -oYADF survives'
# The d10 run hoisted the non-colliding names; only compare when nothing was hoisted,
# i.e. the hoist left the source text otherwise equal -- here it is: both
# inline vars collide, so --d10 only adds the two flags.
if ($q1 -ne [IO.File]::ReadAllText($p0)) {
  $d = @(& git -c core.autocrlf=false diff --no-index --no-color -U0 -- $p0 $p1 2>&1 | Select-Object -Skip 4 -First 8)
  Fail "plain run of the d10 output differs from the plain format of the original`n    $($d -join "`n    ")"
}
Remove-Item $src, $ini, $d1, $d2, $p0, $p1 -Force -ErrorAction SilentlyContinue
Finish 'd10_todo_marker'
