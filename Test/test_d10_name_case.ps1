# --d10 name collisions are CASE-INSENSITIVE (task-8 finding, BACKLOG-ZERO):
# Delphi identifiers ignore case, so inline vars `DcR` and `dcr` in two sibling
# blocks are ONE name. Hoisting both would redeclare it (E2004); a different
# type must keep the second inline + TODO, the same type must be hoisted once.
# Casing normalisation is OFF (--no-first-occ) so the spellings stay distinct;
# the dcr regexes are case-SENSITIVE ((?-i)), -match is not.
# Usage: pwsh Test\test_d10_name_case.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'd10_name_case' $exe
$fail = 0
$ini = New-TempOut '.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`n")

function D10([string]$body) {
  $src = New-TempOut '.pas'
  $unit = [IO.Path]::GetFileNameWithoutExtension($src)
  $text = "unit $unit;`r`n`r`ninterface`r`n`r`nfunction RunCase(K: Integer): Integer;`r`n`r`nimplementation`r`n`r`n" +
          "function RunCase(K: Integer): Integer;`r`nbegin`r`n$body`r`nend;`r`n`r`nend.`r`n"
  [IO.File]::WriteAllText($src, $text)
  $out = & $exe --ini $ini --d10 --no-first-occ --stdout $src 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "d10_name_case: exit $LASTEXITCODE -- $out" }
  return $out
}

# Different types: a collision -> neither is hoisted, both stay inline with the TODO (2026-11-03:
# hoisting one redeclared it next to the other, E2004 in Delphi 13 too).
$diff = D10 ("  if K > 0 then`r`n  begin`r`n    var DcR: Integer:= K;`r`n    Result:= DcR;`r`n  end`r`n  else`r`n  begin`r`n" +
             "    var dcr: string:= 'x';`r`n    Result:= Length(dcr);`r`n  end;")
MustNotMatch $diff '(?m)^\s*DcR: Integer;\r?$' 'diff type: first name NOT hoisted'
MustMatch    $diff "(?m-i)^\s*var DcR: Integer:= K; // TODO -oYADF -cd10 : name 'DcR' is declared with different types" 'diff type: first kept inline + TODO'
MustMatch    $diff "(?m-i)^\s*var dcr: string:= 'x'; // TODO -oYADF -cd10 : name 'dcr' is declared with different types" 'diff type: second kept inline + TODO'
MustNotMatch $diff '(?m-i)^\s*dcr\s*: string\s*;' 'diff type: second NOT hoisted'

# Same type: one declaration, both assignments kept.
$same = D10 ("  if K > 0 then`r`n  begin`r`n    var DcR: Integer:= K;`r`n    Result:= DcR;`r`n  end`r`n  else`r`n  begin`r`n" +
             "    var dcr: Integer:= 2;`r`n    Result:= dcr;`r`n  end;")
MustMatch    $same '(?m)^\s*DcR: Integer;\r?$' 'same type: hoisted once'
MustNotMatch $same '(?m-i)^\s*dcr\s*: Integer\s*;' 'same type: no second declaration'
MustMatch    $same '(?m-i)^\s*dcr\s*:= 2;\r?$' 'same type: assignment kept'
# Same name AND spelling, same type: the guard must accept the dropped duplicate
# declaration with casing normalisation off (it counted the dropped `Integer`).
$dup = D10 ("  if K > 0 then`r`n  begin`r`n    var DcR: Integer:= K;`r`n    Result:= DcR;`r`n  end`r`n  else`r`n  begin`r`n" +
            "    var DcR: Integer:= 2;`r`n    Result:= DcR;`r`n  end;")
MustMatch    $dup '(?m)^\s*DcR: Integer;\r?$' 'same spelling: hoisted once'
MustMatch    $dup '(?m)^\s*DcR\s*:= 2;\r?$' 'same spelling: assignment kept'
Finish 'd10_name_case'