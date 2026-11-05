# --d10 inline-const shadowing (follow-up to REVIEW-2026-11-04-corruption H1):
# an inline `const` whose name also binds outside its block -- a unit global, a
# class field, a `with` member -- must stay inline with a TODO, like an inline
# var. Hoisting it to the routine's const section made every reference outside
# the block read the const (silent value change; the guard accepted it). The
# fixture is compiled and RUN before and after formatting: the stdout must be
# identical. A legitimate const hoist in the same file must still happen.
# Usage: pwsh Test\test_d10_const_shadow.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'd10_const_shadow' $exe
$fail = 0
$dcc  = Get-Dcc64
$work = Join-Path $env:TEMP ('d10cshadow_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
$ini = Join-Path $work 'plain.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`n")
$src = Join-Path $PSScriptRoot 'Cases\review1104\review1104_d10_const_shadow.pas'

function Run-Program([string]$pas) {
  $dir = Join-Path $work ('bin_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $dir | Out-Null
  $log = & $dcc -Q -NSSystem "-N0$dir" "-E$dir" $pas 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { return "<does not compile: $((@($log -split "`n") -match 'Error' | Select-Object -First 2) -join ' | ')>" }
  return (& (Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($pas) + '.exe')) 2>&1 | Out-String)
}

$outDir = Join-Path $work 'out'
New-Item -ItemType Directory $outDir | Out-Null
$out = Join-Path $outDir ([IO.Path]::GetFileName($src))
$msg = & $exe --ini $ini $src --d10 --o $out 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Fail "d10_const_shadow: exit $LASTEXITCODE -- $($msg.Trim())" }
else {
  $t = [IO.File]::ReadAllText($out)
  MustMatch    $t '(?m)^\s*const G = 30;'                  'global shadow: G stays inline'
  MustMatch    $t '(?m)^\s*const K = 40;'                  'field shadow: K stays inline'
  MustMatch    $t '(?m)^\s*const A = 99;'                  'with member: A stays inline'
  MustMatch    $t "name 'G' is referenced outside its block" 'global shadow: TODO names G'
  MustMatch    $t "name 'A' is declared inside a ``with`` body"  'with member: TODO names A'
  MustMatch    $t '(?m)^const\r?\n\s*C = 4;'               'legit: C hoisted'
  $a = Run-Program $src; $b = Run-Program $out
  if ($a -ne $b) { Fail "d10_const_shadow: program output changed`n    in : $($a.Trim())`n    out: $($b.Trim())" }
  $out2 = Join-Path $work 'second.pas'
  $msg = & $exe --ini $ini $out --d10 --o $out2 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "d10_const_shadow second pass: exit $LASTEXITCODE -- $($msg.Trim())" }
  elseif ([IO.File]::ReadAllText($out2) -ne $t) { Fail 'd10_const_shadow: second --d10 pass changed the output' }
}
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Finish 'd10_const_shadow'
