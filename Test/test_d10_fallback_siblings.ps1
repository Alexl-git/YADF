# --d10, review 2026-11-03 M1: a name a TODO fallback leaves inline (a
# non-inferable initialiser, a non-inferable `for var V in L`, an inline var
# inside {$IFDEF}) must not be hoisted from a sibling block either: the hoisted
# `Y: T` next to the inline `var Y` was E2004 (and the guard did not see it).
# Now every declaration of such a name stays inline with a TODO, so the output
# compiles in Delphi 13 exactly as the source did. Each output must compile with
# dcc64 and be a fixed point of a second --d10 run; unrelated names still hoist.
# Usage: pwsh Test\test_d10_fallback_siblings.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'd10_fallback_siblings' $exe
$fail = 0
$work = Join-Path $env:TEMP ('d10fs_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$dcu = Join-Path $work 'dcu'; New-Item -ItemType Directory -Path $dcu | Out-Null
$ini = Join-Path $work 'e.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`n")
$n = 0

function D10([string]$label, [string]$body) {
  $script:n++
  $unit = "d10fs$($script:n)"
  $src = Join-Path $work "$unit.pas"
  $text = "unit $unit;`r`n`r`ninterface`r`n`r`nuses`r`n  System.Generics.Collections;`r`n`r`nfunction RunCase(K: Integer; L: TList<Integer>): Integer;`r`n`r`nimplementation`r`n`r`n" +
          "function RunCase(K: Integer; L: TList<Integer>): Integer;`r`nbegin`r`n  Result:= 0;`r`n$body`r`nend;`r`n`r`nend.`r`n"
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

# 1. Non-inferable initialiser in the then-block, inferable literal in the else.
$o = D10 'inferred' ("  if K > 0 then`r`n  begin`r`n    var Y:= K * 2;`r`n    Inc(Result, Y);`r`n  end`r`n  else`r`n  begin`r`n" +
                     "    var Y:= 'neg';`r`n    Inc(Result, Length(Y));`r`n  end;`r`n  var Z: Integer:= 4;`r`n  Inc(Result, Z);")
MustNotMatch $o '(?m)^\s*Y\s*:\s*\w+\s*;' 'inferred: Y not hoisted'
MustMatch    $o "(?m)^\s*var Y:= 'neg';\s*// TODO -oYADF" 'inferred: literal sibling kept inline + TODO'
MustMatch    $o '(?m)^\s*Z\s*:\s*Integer\s*;' 'inferred: unrelated Z still hoisted'

# 2. A non-inferable for-in loop var and a for-to loop var of the same name.
$o = D10 'for-in' ("  for var V in L do`r`n    Inc(Result, V);`r`n  for var V:= 0 to 1 do`r`n    Inc(Result, V);")
MustNotMatch $o '(?m)^\s*V\s*:\s*Integer\s*;' 'for-in: V not hoisted'
MustMatch    $o '(?m)^\s*for var V:= 0 to 1 do' 'for-in: for-to loop var kept inline'

# 3. An inline var inside {$IFNDEF} and an explicit one of the same name outside.
$o = D10 'ifdef' ("  if K > 0 then`r`n  begin`r`n    var N: Integer:= K;`r`n    Inc(Result, N);`r`n  end`r`n  else`r`n  begin`r`n" +
                  "    {`$IFNDEF YADF_NEVER_DEFINED}`r`n    var N: string:= 'ifdef';`r`n    Inc(Result, Length(N));`r`n    {`$ENDIF}`r`n  end;")
MustNotMatch $o '(?m)^\s*N\s*:\s*(Integer|string)\s*;' 'ifdef: N not hoisted'
MustMatch    $o '(?m)^\s*var N: Integer:= K;\s*// TODO -oYADF' 'ifdef: explicit sibling kept inline + TODO'

[IO.Directory]::Delete($work, $true)
Finish 'd10_fallback_siblings'
