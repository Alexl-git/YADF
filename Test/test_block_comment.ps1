# Multi-line block comments ({...} and (*...*)) must pass through Stage 3/4
# byte-for-byte: their interior whitespace/alignment is prose, not code, and
# the line-based collapse/align passes must not touch it. Exit 0 = pass.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$ini = Join-Path $PSScriptRoot '..\yadf.ini'  # pin config: personal %APPDATA% profile must not affect tests
$src = Join-Path $PSScriptRoot 'Cases\block_comment_preserve.pas'
$fail = 0

$o1 = Join-Path $env:TEMP 'bcp1.pas'; $o2 = Join-Path $env:TEMP 'bcp2.pas'
& $exe --ini $ini $src --o $o1 | Out-Null
$out = Get-Content $o1 -Raw

function MustContain([string]$needle, [string]$label) {
  if (-not $out.Contains($needle)) {
    $script:fail++
    Write-Output "FAIL [$label]: interior collapsed, missing >>>$needle<<<"
  }
}
# Aligned interiors of a {...} brace comment.
MustContain 'Step one      -- do the first thing'  'brace: 6-space run kept'
MustContain 'Step twenty   -- do another thing'    'brace: 3-space run kept'
# Aligned interior of an (*...*) ANSI comment.
MustContain 'Beta      = 22'                        'ansi: interior columns kept'
# Indented brace comment's interior multi-space run.
MustContain 'keeps its     interior   spacing'      'indented brace: interior kept'

# Idempotency + byte-faithful round-trip.
& $exe --ini $ini $o1 --o $o2 | Out-Null
if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { $fail++; Write-Output 'FAIL [idempotent]' }
$chk = & $exe --ini $ini --check $o1 2>&1
if ("$chk" -notmatch 'PASS') { $fail++; Write-Output 'FAIL [roundtrip]' }
Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'block_comment: PASS'; exit 0 }
else { Write-Output "block_comment: $fail FAILED"; exit 1 }
