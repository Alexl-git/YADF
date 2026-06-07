# RED target for DelphiAST issue #333 (class var / visibility section indentation).
# Currently FAILS on purpose -- it specifies the correct behaviour we will implement.
#
# The exact visibility indent (`protected` at class or class+1) is a style choice, so
# this test asserts only the UNAMBIGUOUS invariants the current output violates:
#   1. Every `var` / `class var` section keyword inside the class sits at the SAME indent.
#   2. Each field is indented strictly DEEPER than its owning section keyword.
#
# Usage: pwsh Test\test_class_var_333.ps1   (exit 0 = pass, 1 = fail)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$src = Join-Path $PSScriptRoot 'Cases\class_var_sections.pas'
$fail = 0
function Ind([string]$s) { $s.Length - $s.TrimStart().Length }

$tmp = Join-Path $env:TEMP "cv333.out"
& $exe $src --o $tmp | Out-Null
$lines = Get-Content $tmp

# Section-keyword lines: a line whose trimmed text is exactly 'var' or 'class var'.
$sectionIdx = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
  $tr = $lines[$i].Trim()
  if ($tr -eq 'var' -or $tr -eq 'class var') { $sectionIdx += $i }
}
if ($sectionIdx.Count -lt 3) {
  $fail++; Write-Output "FAIL [333]: expected 3 section keywords (var/class var/var), found $($sectionIdx.Count)"
}
else {
  $secInd = $sectionIdx | ForEach-Object { Ind $lines[$_] }
  if (($secInd | Select-Object -Unique).Count -ne 1) {
    $fail++; Write-Output "FAIL [333]: section keywords at inconsistent indents: $($secInd -join ', ')"
  }
  $base = $secInd[0]
  # Every field declaration (Name: Type;) must be indented deeper than $base.
  foreach ($ln in $lines) {
    if ($ln -match '^\s*\w+\s*:\s*\w+\s*;') {
      if ((Ind $ln) -le $base) {
        $fail++; Write-Output "FAIL [333]: field not indented under its var section: '$($ln.Trim())' (indent $(Ind $ln) <= section $base)"
      }
    }
  }
}

if ($fail -eq 0) { Write-Output "class_var_333: PASS"; exit 0 }
else { Write-Output "class_var_333: $fail FAILED (expected until #333 is fixed)"; exit 1 }
