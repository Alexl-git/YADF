# UsesCommaLast: default false -> comma-first broken uses; true -> comma-last.
# Exit 0 = pass.
$ErrorActionPreference = 'Stop'
$exe  = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$case = Join-Path $PSScriptRoot 'Cases\uses_comma_last.pas'
$tmp  = Join-Path $env:TEMP 'uses_cl_test'
New-Item -ItemType Directory $tmp -Force | Out-Null
function Fmt([string]$iniBody) {
  $ini = Join-Path $tmp 'o.ini'
  [IO.File]::WriteAllText($ini, "[Format]`r`n$iniBody", (New-Object Text.ASCIIEncoding))
  $out = Join-Path $tmp 'out.pas'
  & $exe $case --ini $ini --o $out | Out-Null
  return (Get-Content $out -Raw)
}
$fail = 0
function MustMatch([string]$o,[string]$rx,[string]$label){ if ($o -notmatch $rx){ $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" } }
function MustNotMatch([string]$o,[string]$rx,[string]$label){ if ($o -match $rx){ $script:fail++; Write-Output "FAIL [$label]: should NOT match /$rx/" } }

# Default (UsesCommaLast=false) -> comma-FIRST: leading comma, ';' on its own line.
$cf = Fmt 'UsesAlwaysBreak=true'
MustMatch    $cf '(?m)^\s*, System\.StrUtils'   'comma-first: leading comma before StrUtils'
MustMatch    $cf '(?m)^\s*;\s*$'                'comma-first: semicolon on its own line'
MustNotMatch $cf '(?m)System\.SysUtils,'        'comma-first: no trailing comma'

# UsesCommaLast=true -> comma-LAST: trailing comma per unit, ';' on the last unit.
$cl = Fmt "UsesAlwaysBreak=true`r`nUsesCommaLast=true"
MustMatch    $cl '(?m)^\s*System\.SysUtils,\s*$' 'comma-last: trailing comma after SysUtils'
MustMatch    $cl '(?m)^\s*System\.StrUtils,\s*$' 'comma-last: trailing comma after StrUtils'
MustMatch    $cl '(?m)^\s*System\.Classes;\s*$'  'comma-last: semicolon on the last unit'
MustNotMatch $cl '(?m)^\s*, System'              'comma-last: no leading comma'
MustNotMatch $cl '(?m)^\s*;\s*$'                 'comma-last: no lone-semicolon line'

if ($fail -eq 0) { Write-Output "uses_comma_last: PASS"; exit 0 }
else { Write-Output "uses_comma_last: $fail FAILED"; exit 1 }
