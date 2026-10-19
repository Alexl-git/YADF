# Option coverage, part A: one flipped-from-default run per option, each with
# one observable assertion, idempotency/round-trip (CheckStable) and a dcc64
# compile of the output. Options: TabWidth, Indent, TrimTrailing,
# MaxBlankLines, BlanksBeforeSection, BlanksBeforeType, UpperDirectives,
# FirstOccCasing, AssignNoSpaceBefore, AssignSpaceAfter, AlignConstEquals.
# Each flipped value goes in a temp copy of the repo yadf.ini (never the
# user profile). Exit 0 = pass, 1 = failures, 2 = skip.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$repoIni = Get-RepoIni
Assert-ToolOrSkip 'option_coverage_a' $exe
$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$work = Join-Path $env:TEMP ('optcov_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
$base = Get-Content $repoIni -Raw

# Temp INI = repo ini with the given keys replaced (key must exist in repo ini).
function New-Ini([hashtable]$kv) {
  $t = $base
  foreach ($k in $kv.Keys) {
    $rx = "(?m)^$k\s*=.*$"
    if ($t -notmatch $rx) { Fail "repo yadf.ini has no key $k"; continue }
    $t = [regex]::Replace($t, $rx, "$k=$($kv[$k])")
  }
  $p = Join-Path $work ([guid]::NewGuid().ToString('N') + '.ini')
  [IO.File]::WriteAllText($p, $t, (New-Object Text.ASCIIEncoding))
  return $p
}

# Formats $src with the flipped ini, runs CheckStable with the same ini and
# (when dcc64 exists and $compile) compiles the output. Output text lands in $script:res (Fail writes to the pipeline).
function Run-Case([string]$label, [hashtable]$kv, [string[]]$flags = @(), [bool]$compile = $true) {
  $script:ini = New-Ini $kv
  $d = Join-Path $work ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $d | Out-Null
  $out = Join-Path $d (Split-Path $src -Leaf)
  if (-not (Invoke-Yadf $src $script:ini $out $flags)) { $script:res = ''; return }
  CheckStable $label $flags
  if ($compile -and (Test-Path $dcc)) {
    $r = & $dcc -Q "-N0$d" "-E$d" $out 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Fail "compile: $label : $(($r -split '\r?\n' | Select-String 'Error|Fatal' | Select-Object -First 1))" }
  }
  $script:res = Get-Content $out -Raw
}

$src = Join-Path $PSScriptRoot 'Cases\OptCov.pas'

# Indent=4 (default 2): body and class members indented 4.
Run-Case 'Indent' @{ Indent = 4 }; $o = $script:res
MustMatch $o '(?m)^    Counter:= 1;'   'Indent=4: body statement at 4 spaces'
MustMatch $o '(?m)^    TFoo = class'   'Indent=4: type member at 4 spaces'

# TrimTrailing=false: the fixture line "Counter := 1;   " keeps trailing space.
Run-Case 'TrimTrailing' @{ TrimTrailing = 'false' }; $o = $script:res
MustMatch $o '(?m)Counter:= 1; +\r?$' 'TrimTrailing=false keeps trailing blank'

# MaxBlankLines=3 (default 1): the 3 blank lines in the fixture survive.
Run-Case 'MaxBlankLines' @{ MaxBlankLines = 3 }; $o = $script:res
MustMatch $o '(?m)Counter \+ 1;\r?\n\r?\n\r?\n\r?\n' 'MaxBlankLines=3 keeps 3 blank lines'

# BlanksBeforeSection=2 (default 0): two blanks before interface/implementation.
Run-Case 'BlanksBeforeSection' @{ BlanksBeforeSection = 2 }; $o = $script:res
MustMatch $o '(?m)\r?\n\r?\n\r?\ninterface\r?$'      'BlanksBeforeSection=2 before interface'
MustMatch $o '(?m)\r?\n\r?\n\r?\nimplementation\r?$' 'BlanksBeforeSection=2 before implementation'

# BlanksBeforeType=2 (default 0): two blanks before `type`.
Run-Case 'BlanksBeforeType' @{ BlanksBeforeType = 2 }; $o = $script:res
MustMatch $o '(?m)\r?\n\r?\n\r?\ntype\r?$' 'BlanksBeforeType=2 before type'

# UpperDirectives=false (default true): directive names keep authored case.
Run-Case 'UpperDirectives' @{ UpperDirectives = 'false' }; $o = $script:res
MustContain $o '{$ifdef FOO}' 'UpperDirectives=false keeps {$ifdef}'

# FirstOccCasing=false (default true): later spellings of Counter stay as written.
Run-Case 'FirstOccCasing' @{ FirstOccCasing = 'false' }; $o = $script:res
MustContain $o 'COUNTER:=' 'FirstOccCasing=false keeps COUNTER'

# AssignNoSpaceBefore=false (default true): one space before :=.
Run-Case 'AssignNoSpaceBefore' @{ AssignNoSpaceBefore = 'false' }; $o = $script:res
MustMatch $o '(?m)^  Counter := 1;' 'AssignNoSpaceBefore=false gives " :="'

# AssignSpaceAfter=false (default true): no forced space; authored ":=3" stays tight.
Run-Case 'AssignSpaceAfter' @{ AssignSpaceAfter = 'false' }; $o = $script:res
MustMatch $o '(?m)Counter:=3;' 'AssignSpaceAfter=false leaves ":=3" unspaced'

# AlignConstEquals=false (default true): const '=' not padded into a column.
Run-Case 'AlignConstEquals' @{ AlignConstEquals = 'false' }; $o = $script:res
MustMatch    $o '(?m)^  A = 1;'  'AlignConstEquals=false leaves "A = 1;"'
MustNotMatch $o '(?m)^  A  +=' 'AlignConstEquals=false: no padding before ='

# TabWidth: a tab inside an emitted comment counts TabWidth columns toward
# MaxLen. At 60 cols the line fits through width 3 and breaks from width 4 (the
# repo default), so the 3/4 pair brackets the threshold: a TabWidth that is ignored
# (or hard-wired to 4) fails the width-3 leg.
$src = Join-Path $PSScriptRoot 'Cases\option_coverage_tab.pas'
Run-Case 'TabWidth=1' @{ TabWidth = 1 } @('--max-len', '60') $false; $o = $script:res
MustMatch $o 'Foo\(Aaaaaaaaa, Bbbbbbbbb, Cccccccc, Ddddddd\);' 'TabWidth=1 keeps call on one line'
Run-Case 'TabWidth=3' @{ TabWidth = 3 } @('--max-len', '60') $false; $o = $script:res
MustMatch $o 'Foo\(Aaaaaaaaa, Bbbbbbbbb, Cccccccc, Ddddddd\);' 'TabWidth=3 still keeps the call on one line'
Run-Case 'TabWidth=4' @{ TabWidth = 4 } @('--max-len', '60') $false; $o = $script:res
MustMatch $o '(?m)Foo\(\r?\n\s+Aaaaaaaaa' 'TabWidth=4 breaks the call'

foreach ($d in Get-ChildItem $work -Directory) { [IO.Directory]::Delete($d.FullName, $true) }
[IO.Directory]::Delete($work, $true)
Finish 'option_coverage_a'
