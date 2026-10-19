# --d10 hoists an uninitialised inline var to the routine's var block. Inside
# a loop body the inline var is re-initialised (managed types: emptied) on every
# iteration, the hoisted one is not -- its value would survive iterations. The
# rewrite must emit `Name:= Default(Type);` at the declaration point. Semantic
# proof: compile + run the ORIGINAL and the --d10 OUTPUT with dcc64, same stdout.
# Usage: pwsh Test\test_d10_loop_reinit.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'd10_loop_reinit' $exe
$bin = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin'
$src = Join-Path $PSScriptRoot 'Cases\d10_loop_reinit.dpr'

function Build-AndRun([string]$dpr, [string]$dir) {
  & (Join-Path $bin 'dcc64.exe') -Q -B "-N0$dir" "-E$dir" $dpr *> $null
  if ($LASTEXITCODE -ne 0) { return $null }
  $exeFile = Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($dpr) + '.exe')
  return ((& $exeFile) -join "`n")
}

$g = [guid]::NewGuid().ToString('N')
$d1 = Join-Path $env:TEMP "d10lr1_$g"; $d2 = Join-Path $env:TEMP "d10lr2_$g"
New-Item -ItemType Directory $d1, $d2 | Out-Null
$out = Join-Path $d2 'd10_loop_reinit.dpr'
$msg = & $exe --ini $ini $src --d10 --o $out 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { Fail "d10_loop_reinit: format failed -- $msg" }
else {
  $want = Build-AndRun $src $d1
  if ($null -eq $want) { Fail 'd10_loop_reinit: ORIGINAL fixture does not compile' }
  $got = Build-AndRun $out $d2
  if ($null -eq $got) { Fail 'd10_loop_reinit: --d10 OUTPUT does not compile' }
  elseif ($want -cne $got) { Fail "d10_loop_reinit: runtime output differs. want [$($want -replace "`n",' / ')] got [$($got -replace "`n",' / ')]" }
  $txt = [IO.File]::ReadAllText($out)
  if ($txt -match '(?m)^\s*var\s+(S|A|B|T)\s*:' -or $txt -match 'inline var') { Fail 'd10_loop_reinit: inline var survived' }
}
Finish 'd10_loop_reinit'