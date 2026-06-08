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
function MustMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -notmatch $rx) {
    $script:fail++
    Write-Output "FAIL [$label]: expected match /$rx/"
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

# --- d10_for_untyped: untyped `for var K := 0 to N` -> Integer inference ---
$o = Fmt 'd10_for_untyped.pas'
MustMatch    $o 'K: Integer; // YADF Delphi10: inferred loop type' 'for_untyped: hoisted K: Integer + verify note'
MustContain  $o 'for K:= 0 to N do' 'for_untyped: loop downgraded'
MustNotMatch $o 'for\s+var\s+K' 'for_untyped: no inline for-var left'

# --- d10_inline_const: inline const hoisted to a const section ---
$o = Fmt 'd10_inline_const.pas'
MustMatch    $o '(?m)^const\r?$' 'inline_const: a const section exists'
MustMatch    $o 'Factor\s*=\s*2;' 'inline_const: Factor moved to const section'
MustMatch    $o "Tag: string\s*=\s*'x';" 'inline_const: typed const kept'
MustContain  $o 'WriteLn(Factor, Tag)' 'inline_const: body references survive'
MustNotMatch $o '(?ms)\bbegin\b.*\bconst\s+Factor' 'inline_const: no inline const left inside begin'

# --- d10_flag: non-inferable residuals get a TODO; nothing silently downgraded ---
$o = Fmt 'd10_flag.pas'
MustMatch $o '// TODO -oYADF : inline loop var cannot be type-inferred' 'flag: for-in flagged'
MustMatch $o '(?m)^\s*for var X in Coll do' 'flag: for-in left in place on its own line'
MustMatch $o 'const Local = 5; // TODO -oYADF : inline const inside an anonymous method' 'flag: anon const flagged'

# --- d10_multiname ---
$o = Fmt 'd10_multiname.pas'
MustContain $o "A: Integer;" 'multiname: A hoisted'
MustContain $o "B: Integer;" 'multiname: B hoisted'
MustNotMatch $o 'var\s+A\s*,\s*B' 'multiname: inline removed'

# --- d10_novarsection ---
$o = Fmt 'd10_novarsection.pas'
MustContain $o "var`r`n  Acc: Integer;" 'novarsection: var block created'
MustContain $o "const`r`n  Step = 2;" 'novarsection: existing const intact'
MustContain $o ":= Step;" 'novarsection: assignment kept'
MustNotMatch $o 'var\s+Acc\s*:\s*Integer\s*:=' 'novarsection: inline removed'

# --- d10_infer ---
$o = Fmt 'd10_infer.pas'
MustMatch $o 'N: Integer\s*; // YADF Delphi10: inferred type, verify -- was: var N:= 5;' 'infer: int'
MustMatch $o 'R: Extended\s*; // YADF Delphi10: inferred type, verify -- was: var R:= 1\.5;' 'infer: real'
MustMatch $o "S: string\s*; // YADF Delphi10: inferred type, verify -- was: var S:= 'hi';" 'infer: string'
MustMatch $o 'B: Boolean\s*; // YADF Delphi10: inferred type, verify -- was: var B:= True;' 'infer: bool'
MustMatch $o 'L: TStringList; // YADF Delphi10: inferred type, verify -- was: var L:= TStringList\.Create;' 'infer: ctor'
MustMatch $o 'N:= 5;' 'infer: int assignment kept'

# --- d10_fallback ---
$o = Fmt 'd10_fallback.pas'
MustContain $o "var X:= AInput.GetThing; // TODO -oYADF : add an explicit type to hoist for Delphi 10 -- was: var X:= AInput.GetThing;" 'fallback: left + TODO'

# --- d10_collision ---
$o = Fmt 'd10_collision.pas'
MustContain $o "var`r`n  I: Integer;" 'collision: first hoisted'
MustContain $o "var I: string:= 'x'; // TODO -oYADF : name 'I' already hoisted with a different type; resolve manually for Delphi 10 -- was: var I: string:= 'x';" 'collision: second flagged'

# --- d10_nested ---
$o = Fmt 'd10_nested.pas'
MustContain $o "  procedure Inner;`r`n  var`r`n    K: Integer;`r`n  begin" 'nested: hoisted to Inner'
# --- d10_anon ---
$o = Fmt 'd10_anon.pas'
MustContain $o "var Z: Integer:= 3; // TODO -oYADF : inline var inside an anonymous method is not auto-hoisted for Delphi 10 -- was: var Z: Integer:= 3;" 'anon: flagged'

# --- consolidated guards: idempotency + transformed round-trip over every fixture ---
Get-ChildItem $casesDir -Filter 'd10_*.pas' | ForEach-Object {
  $o1 = Join-Path $env:TEMP ($_.BaseName + '.1.pas')
  $o2 = Join-Path $env:TEMP ($_.BaseName + '.2.pas')
  & $exe $_.FullName --d10 --o $o1 | Out-Null
  & $exe $o1 --d10 --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) {
    $script:fail++; Write-Output "FAIL [idempotent]: $($_.Name)"
  }
  $chk = & $exe --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { $script:fail++; Write-Output "FAIL [roundtrip]: $($_.Name)" }
  Remove-Item $o1 -Force -ErrorAction SilentlyContinue
  Remove-Item $o2 -Force -ErrorAction SilentlyContinue
}

# --- option OFF must not hoist ---
$tmp = Join-Path $env:TEMP "d10_off.pas"
& $exe (Join-Path $casesDir 'd10_explicit_basic.pas') --no-d10 --o $tmp | Out-Null
$off = Get-Content $tmp -Raw
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
MustMatch $off 'var N: Integer:= 5;' 'option-off: inline var preserved'

if ($fail -eq 0) { Write-Output "delphi10_compat: PASS"; exit 0 }
else { Write-Output "delphi10_compat: $fail FAILED"; exit 1 }
