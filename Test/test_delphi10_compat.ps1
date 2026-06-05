# Fixture-based tests for Delphi10Compat. Each case: format with --d10 and assert
# the expected hoisted/flagged output. Exit 0 = all pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$casesDir = Join-Path $PSScriptRoot 'Cases'
$fail = 0

function Fmt([string]$name) {
  $src = Join-Path $casesDir $name
  $tmp = Join-Path $env:TEMP ("d10_" + [IO.Path]::GetFileNameWithoutExtension($name) + ".out")
  & $exe $src --d10 --o $tmp | Out-Null
  $out = Get-Content $tmp -Raw
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}
function MustContain([string]$out, [string]$needle, [string]$label) {
  if (-not $out.Contains($needle)) {
    $script:fail++
    Write-Output "FAIL [$label]: missing >>>$($needle -replace "`r`n",'\r\n')<<<"
  }
}
function MustNotMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -match $rx) {
    $script:fail++
    Write-Output "FAIL [$label]: should not match /$rx/"
  }
}

# --- d10_explicit_basic ---
$o = Fmt 'd10_explicit_basic.pas'
MustContain $o "var`r`n  N: Integer;" 'explicit_basic: hoisted decl'
MustContain $o "N:= 5;" 'explicit_basic: assignment kept'
MustNotMatch $o 'var\s+N\s*:\s*Integer\s*:=' 'explicit_basic: no inline var left'

# --- d10_for_typed ---
$o = Fmt 'd10_for_typed.pas'
MustContain $o "var`r`n  L: Integer;" 'for_typed: hoisted loop var'
MustContain $o "for L:= 0 to 9 do" 'for_typed: loop downgraded'
MustNotMatch $o 'for\s+var\s+L' 'for_typed: no inline loop var'

# --- d10_multiname ---
$o = Fmt 'd10_multiname.pas'
MustContain $o "A: Integer;" 'multiname: A hoisted'
MustContain $o "B: Integer;" 'multiname: B hoisted'
MustNotMatch $o 'var\s+A\s*,\s*B' 'multiname: inline removed'

if ($fail -eq 0) { Write-Output "delphi10_compat: PASS"; exit 0 }
else { Write-Output "delphi10_compat: $fail FAILED"; exit 1 }
