# Fixture-based tests for BreakCaseLabels (--break-case / --no-break-case).
# Default OFF keeps multi-label case arms on one line; ON splits them per
# label. Genuine var/field declarations still split per SplitMultiVarDecls
# regardless. Exit 0 = all pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$src = Join-Path $PSScriptRoot 'Cases\case_labels.pas'
$fail = 0

function Fmt([string]$flag) {
  $tmp = Join-Path $env:TEMP ("bc_" + ($flag -replace '\W','') + ".out")
  & $exe $src $flag --o $tmp | Out-Null
  $out = Get-Content $tmp -Raw
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}
function MustMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -notmatch $rx) { $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" }
}
function MustNotMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -match $rx) { $script:fail++; Write-Output "FAIL [$label]: should not match /$rx/" }
}

# ----- DEFAULT (--no-break-case): arms kept on one line -----
$off = Fmt '--no-break-case'
MustMatch    $off '0, 1, 2\s*:'          'off: numeric+assign arm intact'
MustMatch    $off '3, 4\s*:'             'off: numeric+call arm intact'
MustMatch    $off '5, 6, 7\s*:\s*begin'  'off: numeric+begin arm intact'
MustNotMatch $off '(?m)^\s*1:\s'         'off: label 1 NOT on its own line'
MustNotMatch $off '(?m)^\s*6:\s'         'off: label 6 NOT on its own line'
# Genuine declaration STILL splits.
MustMatch    $off '(?m)^\s*A: Integer;'  'off: var A split'
MustMatch    $off '(?m)^\s*B: Integer;'  'off: var B split'
MustMatch    $off '(?m)^\s*C: Integer;'  'off: var C split'

# ----- --break-case: arms split per label -----
$on = Fmt '--break-case'
MustMatch    $on '(?m)^\s*0:\s'          'on: label 0 split out'
MustMatch    $on '(?m)^\s*1:\s'          'on: label 1 split out'
MustMatch    $on '(?m)^\s*2:\s'          'on: label 2 split out'
MustMatch    $on '(?m)^\s*6:\s*begin'    'on: label 6 split with begin body'
MustNotMatch $on '0, 1, 2'               'on: no multi-label arm remains'
MustMatch    $on '(?m)^\s*A: Integer;'   'on: var A still split'

# ----- idempotency + byte-faithful round-trip for both modes -----
foreach ($flag in @('--no-break-case','--break-case')) {
  $o1 = Join-Path $env:TEMP "bc1.pas"; $o2 = Join-Path $env:TEMP "bc2.pas"
  & $exe $src $flag --o $o1 | Out-Null
  & $exe $o1  $flag --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) {
    $script:fail++; Write-Output "FAIL [idempotent]: $flag"
  }
  $chk = & $exe --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { $script:fail++; Write-Output "FAIL [roundtrip]: $flag" }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Output "break_case: PASS"; exit 0 }
else { Write-Output "break_case: $fail FAILED"; exit 1 }
