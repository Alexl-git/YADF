# Regressions from ORM3 COMMON\BASICS.PAS (2026-10-13):
#  1. `UTF8String = type AnsiString` -- the alias's `type` was taken for a
#     section opener: the line broke after it and the phantom section pushed
#     the following resourcestring block one level right.
#  2. resourcestring / threadvar were not section keywords: indented under the
#     previous section, first entry merged onto the keyword.
#  3. Comments inside a uses clause: +2 spaces of indent on EVERY format (the
#     collector copied whitespace tokens into the item), and in the comma-last
#     and inline styles the guard declined the whole file.
# Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'section_and_uses_comments' $exe
$tmp = Join-Path $env:TEMP 'sec_uses_test'
New-Item -ItemType Directory $tmp -Force | Out-Null

function Fmt([string]$case, [string]$iniBody) {
  $script:ini = Join-Path $tmp 'o.ini'
  [IO.File]::WriteAllText($script:ini, "[Format]`r`n$iniBody", (New-Object Text.ASCIIEncoding))
  $out = Join-Path $tmp 'out.pas'
  if (-not (Invoke-Yadf (Join-Path $PSScriptRoot "Cases\$case") $script:ini $out)) { return '' }
  return (Get-Content $out -Raw)
}

# --- 1 + 2: section keywords --------------------------------------------
$s = Fmt 'section_keywords.pas' 'UsesAlwaysBreak=true'
MustMatch    $s '(?m)^  UTF8String = type AnsiString;\s*$' 'type alias stays on one line'
MustMatch    $s '(?m)^  TName\s+= type string;\s*$'        'type alias before a class stays on one line'
MustMatch    $s '(?m)^resourcestring\s*$'                  'resourcestring at column 0, alone on its line'
MustMatch    $s '(?m)^  SDotStar = '                       'resourcestring entry indented one level'
MustMatch    $s '(?m)^threadvar\s*$'                       'threadvar at column 0, alone on its line'
MustMatch    $s '(?m)^  GCount: Integer;\s*$'              'threadvar entry indented one level'
MustMatch    $s '(?m)^const\s*$'                           'const after the alias section still at column 0'

# --- 3: comments in a uses clause, all three styles ---------------------
$cf = Fmt 'uses_comments.pas' 'UsesAlwaysBreak=true'
MustMatch    $cf '(?m)^  //  , Winapi\.ShellAPI\s*$'                        'comma-first: commented unit level with the unit lines'
MustMatch    $cf '(?m)^  , System\.Win\.Registry // for the registry read access\s*$' 'comma-first: after-comma comment stays with its unit'
MustMatch    $cf '(?m)^  , Vcl\.Graphics\s*$'                               'comma-first: unit after a comment is a normal row'
MustMatch    $cf '(?m)^  //stNVList,\s*$'                                   'comma-first: own-line comment above the next unit'
MustMatch    $cf '(?m)^  // MachineControlObject_TLB,\r?\n  ;'               'comma-first: trailing comment before the ;'

$cl = Fmt 'uses_comments.pas' "UsesAlwaysBreak=true`r`nUsesCommaLast=true"
MustMatch    $cl '(?m)^  System\.Win\.Registry, // for the registry read access\s*$' 'comma-last: comma before the trailing comment'
MustMatch    $cl '(?m)^  System\.Math, //stList,\s*$'                         'comma-last: comma not swallowed by //'
MustMatch    $cl '(?m)^  // MachineControlObject_TLB,\r?\n  ;'               'comma-last: own-line tail comment stays inside the clause'

$il = Fmt 'uses_comments.pas' 'UsesAlwaysBreak=false'
MustNotMatch $il '(?m)^uses [A-Z]'                                          'inline: a clause holding comments is never joined'

# Idempotency + round-trip in every style (the +2 drift was a pass-2 defect).
foreach ($v in @('UsesAlwaysBreak=true', "UsesAlwaysBreak=true`r`nUsesCommaLast=true", 'UsesAlwaysBreak=false')) {
  foreach ($c in 'uses_comments.pas', 'section_keywords.pas') {
    [IO.File]::WriteAllText($ini, "[Format]`r`n$v", (New-Object Text.ASCIIEncoding))
    $src = Join-Path $PSScriptRoot "Cases\$c"
    CheckStable "$c [$($v -replace "`r`n", ' ')]" @()
  }
}

Finish 'section_and_uses_comments'
