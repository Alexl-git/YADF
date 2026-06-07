# IndentComments option (--indent-comments / --no-indent-comments) + the `//.`
# pin. Default ON re-indents comment-only lines to code depth, EXCEPT a line
# starting with `//.` which always keeps its authored indentation. OFF keeps
# every comment's authored indentation. Exit 0 = pass.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$src = Join-Path $PSScriptRoot 'Cases\comment_indent.pas'
$fail = 0

function Fmt([string]$flag) {
  $tmp = Join-Path $env:TEMP ("ci_" + ($flag -replace '\W','') + ".out")
  & $exe $src $flag --o $tmp | Out-Null
  $o = Get-Content $tmp -Raw; Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return $o
}
function MustMatch([string]$o, [string]$rx, [string]$label) {
  if ($o -notmatch $rx) { $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" }
}

# ----- DEFAULT (--indent-comments): comments snap to code depth, //. pinned -----
$on = Fmt '--indent-comments'
MustMatch $on '(?m)^  // authored at column 0'      'on: col-0 comment indented to 2'
MustMatch $on '(?m)^  // authored over-indented'    'on: over-indented comment pulled to 2'
MustMatch $on '(?m)^//\. pinned note stays'         'on: //. line stays at column 0'

# ----- --no-indent-comments: authored indentation preserved -----
$off = Fmt '--no-indent-comments'
MustMatch $off '(?m)^// authored at column 0'       'off: col-0 comment stays at 0'
MustMatch $off '(?m)^      // authored over-indented' 'off: over-indented comment preserved'
MustMatch $off '(?m)^//\. pinned note stays'        'off: //. line stays at column 0'

# ----- idempotency + round-trip, both modes -----
foreach ($flag in @('--indent-comments','--no-indent-comments')) {
  $o1 = Join-Path $env:TEMP 'ci1.pas'; $o2 = Join-Path $env:TEMP 'ci2.pas'
  & $exe $src $flag --o $o1 | Out-Null
  & $exe $o1  $flag --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { $script:fail++; Write-Output "FAIL [idempotent]: $flag" }
  $chk = & $exe --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { $script:fail++; Write-Output "FAIL [roundtrip]: $flag" }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) { Write-Output 'comment_indent: PASS'; exit 0 }
else { Write-Output "comment_indent: $fail FAILED"; exit 1 }
