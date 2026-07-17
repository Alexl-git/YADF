# Atomic declaration-alignment options: AlignTypeColon=false + AlignDeclSemicolons=false
# => plain "Name: Type;" declarations; both true (default) => colon + trailing-semicolon
# column alignment. Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe  = Get-YadfExe
Assert-ToolOrSkip 'align_declarations' $exe
$case = Join-Path $PSScriptRoot 'Cases\align_declarations.pas'
$tmp  = Join-Path $env:TEMP 'aligndecl_test'
New-Item -ItemType Directory $tmp -Force | Out-Null
function Fmt([string]$iniBody) {
  $ini = Join-Path $tmp 'o.ini'
  [IO.File]::WriteAllText($ini, "[Format]`r`n$iniBody", (New-Object Text.ASCIIEncoding))
  $out = Join-Path $tmp 'out.pas'
  & $exe $case --ini $ini --o $out | Out-Null
  return (Get-Content $out -Raw)
}

# Atomic off -> plain declarations (no colon align, no ; padding).
$off = Fmt "AlignTypeColon=false`r`nAlignDeclSemicolons=false"
MustMatch    $off '(?m)^\s*lPLUID: TGUID;'   'off: lPLUID plain (no ; padding)'
MustMatch    $off '(?m)^\s*lProv: boolean;'  'off: lProv plain (colon not aligned)'
MustNotMatch $off '(?m)lProv\s+:'            'off: no space before lProv colon'
MustNotMatch $off '(?m)TGUID[ ]+;'           'off: no padding before TGUID semicolon'

# Defaults (both on) -> aligned.
$on = Fmt 'AlignTypeColon=true'
MustMatch    $on '(?m)lProv\s+:\s*boolean;'  'on: colon aligned (lProv padded before colon)'
MustMatch    $on '(?m)TGUID[ ]+;'            'on: trailing semicolon aligned (TGUID padded)'

Finish 'align_declarations'
