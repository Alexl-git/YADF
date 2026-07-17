# Multi-line block comments ({...} and (*...*)) must pass through Stage 3/4
# byte-for-byte: their interior whitespace/alignment is prose, not code, and
# the line-based collapse/align passes must not touch it. Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'block_comment' $exe
$src = Join-Path $PSScriptRoot 'Cases\block_comment_preserve.pas'

$o1 = Join-Path $env:TEMP 'bcp1.pas'; $o2 = Join-Path $env:TEMP 'bcp2.pas'
& $exe --ini $ini $src --o $o1 | Out-Null
$out = Get-Content $o1 -Raw

# Aligned interiors of a {...} brace comment.
MustContain $out 'Step one      -- do the first thing'  'brace: 6-space run kept'
MustContain $out 'Step twenty   -- do another thing'    'brace: 3-space run kept'
# Aligned interior of an (*...*) ANSI comment.
MustContain $out 'Beta      = 22'                        'ansi: interior columns kept'
# Indented brace comment's interior multi-space run.
MustContain $out 'keeps its     interior   spacing'      'indented brace: interior kept'

# Idempotency + byte-faithful round-trip.
& $exe --ini $ini $o1 --o $o2 | Out-Null
if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail 'idempotent' }
$chk = & $exe --ini $ini --check $o1 2>&1
if ("$chk" -notmatch 'PASS') { Fail 'roundtrip' }
Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue

Finish 'block_comment'
