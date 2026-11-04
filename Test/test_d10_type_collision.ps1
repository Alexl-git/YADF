# --d10, one name declared inline with DIFFERENT types in one routine (task-8c
# finding, owner 2026-11-03: "make the output at least compile in Delphi 13").
# Hoisting the first and leaving the other inline put `X: Integer` in the routine's
# var block next to an inline `var X: string` -- E2004 in Delphi 13 too. Now no
# declaration of that name is hoisted: every one stays inline with a "declared with
# different types" TODO (so the unit compiles as before), names sharing a
# statement with it are kept with it, other names are still hoisted. Each output
# must compile with dcc64 and be a fixed point of a second --d10 run.
# Usage: pwsh Test\test_d10_type_collision.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'd10_type_collision' $exe
$fail = 0
$work = Join-Path $env:TEMP ('d10tc_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$dcu = Join-Path $work 'dcu'; New-Item -ItemType Directory -Path $dcu | Out-Null
$ini = Join-Path $work 'e.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`n")
$n = 0

function D10([string]$label, [string]$body) {
  $script:n++
  $unit = "d10tc$($script:n)"
  $src = Join-Path $work "$unit.pas"
  $text = "unit $unit;`r`n`r`ninterface`r`n`r`nfunction RunCase(K: Integer): Integer;`r`n`r`nimplementation`r`n`r`n" +
          "function RunCase(K: Integer): Integer;`r`nbegin`r`n  Result:= 0;`r`n$body`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText($src, $text)
  if (-not (Test-DccCompiles $src $work $dcu)) { Fail "$label`: fixture does not compile" }
  $o1 = Join-Path $work "o1"; $o2 = Join-Path $work "o2"
  New-Item -ItemType Directory -Force -Path $o1, $o2 | Out-Null
  $p1 = Join-Path $o1 "$unit.pas"; $p2 = Join-Path $o2 "$unit.pas"
  & $exe --ini $ini --d10 $src --o $p1 *> $null
  if ($LASTEXITCODE -ne 0) { Fail "$label`: exit $LASTEXITCODE"; return '' }
  & $exe --ini $ini --d10 $p1 --o $p2 *> $null
  if ($LASTEXITCODE -ne 0) { Fail "$label`: 2nd run exit $LASTEXITCODE" }
  elseif (-not (SameBytes $p1 $p2)) { Fail "$label`: not idempotent" }
  if (-not (Test-DccCompiles $p1 $o1 $dcu)) { Fail "$label`: output does not compile (Delphi 13)" }
  return [IO.File]::ReadAllText($p1)
}
$todo = "// TODO -oYADF -cd10 : name '{0}' is declared with different types in this routine; resolve manually for Delphi 10"

# 1. Sibling blocks, Integer vs string: neither hoisted, both flagged.
$o = D10 'sibling' ("  if K > 0 then`r`n  begin`r`n    var X: Integer:= K;`r`n    Result:= X;`r`n  end`r`n  else`r`n  begin`r`n" +
                    "    var X: string:= 'x';`r`n    Result:= Length(X);`r`n  end;")
MustNotMatch $o '(?m)^\s*X\s*:\s*(Integer|string)\s*;' 'sibling: no X hoisted'
MustContain  $o ("var X: Integer:= K; " + ($todo -f 'X')) 'sibling: first kept inline + TODO'
MustContain  $o ("var X: string:= 'x'; " + ($todo -f 'X')) 'sibling: second kept inline + TODO'

# 2. A same-type duplicate before the different type: all three stay inline (the
#    duplicate's declaration was dropped -- it would be left undeclared).
$o = D10 'dup+diff' ("  begin`r`n    var X: Integer:= 1;`r`n    Inc(Result, X);`r`n  end;`r`n  begin`r`n    var X: Integer:= 2;`r`n    Inc(Result, X);`r`n  end;`r`n" +
                     "  begin`r`n    var X: string:= 'ab';`r`n    Inc(Result, Length(X));`r`n  end;")
MustNotMatch $o '(?m)^\s*X\s*:\s*(Integer|string)\s*;' 'dup+diff: no X hoisted'
MustNotMatch $o '(?m)^\s*X\s*:=\s*2;' 'dup+diff: duplicate not turned into a bare assignment'

# 3. A name sharing a statement with the colliding one stays inline with it, so
#    its own other declaration is not hoisted next to it either; Y is unrelated.
$o = D10 'cascade' ("  begin`r`n    var A, X: Integer;`r`n    A:= 1; X:= 2;`r`n    Inc(Result, A + X);`r`n  end;`r`n  begin`r`n    var A: Integer:= 3;`r`n    Inc(Result, A);`r`n  end;`r`n" +
                    "  begin`r`n    var X: string:= 'ab';`r`n    Inc(Result, Length(X));`r`n  end;`r`n  var Y: Integer:= 4;`r`n  Inc(Result, Y);")
MustNotMatch $o '(?m)^\s*(A|X)\s*:\s*(Integer|string)\s*;' 'cascade: neither A nor X hoisted'
MustMatch    $o '(?m)^\s*Y\s*:\s*Integer\s*;' 'cascade: unrelated Y still hoisted'

# 4. A for-var first, a different-type statement var later: the for keeps `for var`.
$o = D10 'for-var' ("  begin`r`n    for var I: Integer:= 0 to K do`r`n      Inc(Result, I);`r`n  end;`r`n  begin`r`n    var I: string:= 'x';`r`n    Inc(Result, Length(I));`r`n  end;")
MustNotMatch $o '(?m)^\s*I\s*:\s*(Integer|string)\s*;' 'for-var: no I hoisted'
MustMatch    $o '(?m)^\s*for var I: Integer:= 0 to K do' 'for-var: loop var kept inline'
MustContain  $o "// TODO -oYADF -cd10 : loop variable 'I' is declared with different types in this routine; resolve manually for Delphi 10" 'for-var: flag line above the for'

[IO.Directory]::Delete($work, $true)
Finish 'd10_type_collision'