# On-demand option battery (BACKLOG-ZERO task 8, checked in as a script in task 11).
# Every fixture under Test\Cases and Test\Snippets is formatted under ~70 option
# sets -- the compiled-in defaults, every Boolean option flipped on its own, the
# Integer options at other values, and the combined profiles that real users run
# (packed, --d10, greedy breaker, ReflowLines off, small MaxLen) -- and each run must
#   1. not be declined by the content guard (exit 3) or fail (any other non-zero),
#   2. be a fixed point: formatting the output again under the same set gives the
#      same bytes (idempotence).
# Not part of run_tests.ps1 (about 20 000 YADF runs; ~5-10 min with -Throttle 8).
# Usage:
#   pwsh Test\battery_options.ps1                 all sets, all fixtures
#   pwsh Test\battery_options.ps1 -Sets default,packed -Throttle 4
#   pwsh Test\battery_options.ps1 -List           print the option sets and exit
# Exit 0 = every run passed, 1 = at least one decline / failure / non-idempotent run.
param([string[]]$Sets, [int]$Throttle = 8, [switch]$List, [int]$ShowDiff = 6)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = (Resolve-Path (Get-YadfExe)).Path
Assert-ToolOrSkip 'battery_options' $exe

# ---- compiled-in defaults (a fresh INI written by YADF.exe) ------------------
$work = Join-Path $env:TEMP ('battery_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
$ini0 = Join-Path $work 'default.ini'; $pas0 = Join-Path $work 'a.pas'
[IO.File]::WriteAllText($pas0, "unit A;`r`ninterface`r`nimplementation`r`nend.`r`n")
& $exe --ini $ini0 --stdout $pas0 *> $null
$def = [ordered]@{}
foreach ($l in [IO.File]::ReadAllLines($ini0)) { if ($l -match '^(\w+)\s*=\s*(.*)$') { $def[$Matches[1]] = $Matches[2].Trim() } }
if ($def.Count -lt 40) { throw "default INI holds only $($def.Count) keys" }

# ---- option sets: name -> overrides ------------------------------------------
$noEffect = 'Backup', 'Logging', 'BackupDir', 'BackupKeep', 'ResultDir', 'Encoding'
$all = [ordered]@{ 'default' = @{} }
foreach ($k in $def.Keys) {
  if ($k -in $noEffect) { continue }
  if ($def[$k] -in 'true', 'false') { $all["$k=$(if ($def[$k] -eq 'true') { 'false' } else { 'true' })"] = @{ $k = $(if ($def[$k] -eq 'true') { 'false' } else { 'true' }) } }
}
$ints = [ordered]@{
  MaxLen = 60, 80, 100, 140; Indent = 4, 3; TabWidth = 2, 8; MaxBlankLines = 0, 2; BlanksBeforeSection = 1
  BlanksBeforeMethod = 1, 2; BlanksBeforeType = 1; AlignMaxColumn = 60; AlignShapeMinAnchors = 2
  AlignCommentMaxShift = 0, 40; LabelMinLines = 1, 3
}
foreach ($k in $ints.Keys) { foreach ($v in $ints[$k]) { $all["$k=$v"] = @{ $k = "$v" } } }
$packed = @{ CollapseShortBlocks = 'true'; PackStatements = 'true'; BreakLoopBody = 'false'; BreakWithBody = 'false'; BreakIfBody = 'false'; CaseArmOnLabelLine = 'false' }
$all['packed']           = $packed
$all['packed+d10']       = $packed + @{ Delphi10Compat = 'true' }
$all['d10+MaxLen=80']    = @{ Delphi10Compat = 'true'; MaxLen = '80' }
$all['greedy+MaxLen=80'] = @{ BreakLongExpressions = 'false'; MaxLen = '80' }
$all['greedy+MaxLen=120']= @{ BreakLongExpressions = 'false'; MaxLen = '120' }
# REVIEW-2026-11-02 options H1: the greedy breaker at a small MaxLen (case-arm moves)
$all['greedy+MaxLen=60'] = @{ BreakLongExpressions = 'false'; MaxLen = '60' }
$all['greedy+MaxLen=50'] = @{ BreakLongExpressions = 'false'; MaxLen = '50' }
$all['collapse+labels1'] = @{ CollapseShortBlocks = 'true'; LabelMinLines = '1' }
$all['noreflow+MaxLen=80'] = @{ ReflowLines = 'false'; MaxLen = '80' }
$all['caselabels+armsplit']  = @{ BreakCaseLabels = 'true'; CaseArmOnLabelLine = 'false' }
$all['begin-on-header+packed'] = $packed + @{ BeginOnHeaderLine = 'true' }
$all['params+commalast'] = @{ BreakParamsOnePerLine = 'true'; UsesCommaLast = 'true'; UsesAlwaysBreak = 'false' }
$all['noalign']          = @{ AlignSmartAssign = 'false'; AlignConstEquals = 'false'; AlignTypeColon = 'false'; AlignDeclSemicolons = 'false'; AlignMatchingShapes = 'false' }
$all['indent4+tab8+MaxLen=100'] = @{ Indent = '4'; TabWidth = '8'; MaxLen = '100' }
$all['greedy+packed']    = $packed + @{ BreakLongExpressions = 'false' }
$all['d10+greedy']       = @{ Delphi10Compat = 'true'; BreakLongExpressions = 'false' }
$all['noreflow+packed']  = $packed + @{ ReflowLines = 'false' }
$all['collapse+labels3'] = @{ CollapseShortBlocks = 'true'; LabelMinLines = '3' }
$all['d10+params']       = @{ Delphi10Compat = 'true'; BreakParamsOnePerLine = 'true' }
$all['noalign+packed']   = $packed + @{ AlignSmartAssign = 'false'; AlignMatchingShapes = 'false' }
$all['begin-on-header+caselabels'] = @{ BeginOnHeaderLine = 'true'; BreakCaseLabels = 'true' }
if ($List) { foreach ($n in $all.Keys) { Write-Output ("{0,-28} {1}" -f $n, (($all[$n].GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')) }; Write-Output "$($all.Count) sets"; exit 0 }
if ($Sets) { $pick = [ordered]@{}; foreach ($n in $Sets) { if (-not $all.Contains($n)) { throw "unknown set '$n' (see -List)" }; $pick[$n] = $all[$n] }; $all = $pick }

# One INI per set: the defaults with the set's overrides.
$jobs = @()
$fixtures = @(Get-ChildItem (Join-Path $PSScriptRoot 'Cases'), (Join-Path $PSScriptRoot 'Snippets') -Recurse -Filter *.pas)
$i = 0
foreach ($n in $all.Keys) {
  $i++
  $ini = Join-Path $work ("set{0:D2}.ini" -f $i)
  $lines = @('[Format]') + @(foreach ($k in $def.Keys) { "$k=$(if ($all[$n].ContainsKey($k)) { $all[$n][$k] } else { $def[$k] })" })
  [IO.File]::WriteAllLines($ini, $lines)
  foreach ($f in $fixtures) { $jobs += [pscustomobject]@{ Set = $n; Ini = $ini; Src = $f.FullName; Dir = (Join-Path $work ("o{0:D2}" -f $i)) } }
}
$fixtures | Out-Null
foreach ($d in ($jobs | Select-Object -ExpandProperty Dir -Unique)) { New-Item -ItemType Directory -Force (Join-Path $d '1'), (Join-Path $d '2') | Out-Null }

$results = $jobs | ForEach-Object -ThrottleLimit $Throttle -Parallel {
  $exe = $using:exe; $j = $_
  $leaf = [IO.Path]::GetFileName($j.Src)
  $sub  = [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($j.Src))
  $p1 = Join-Path $j.Dir "1\${sub}_$leaf"; $p2 = Join-Path $j.Dir "2\${sub}_$leaf"
  $m1 = & $exe --ini $j.Ini $j.Src --o $p1 2>&1 | Out-String; $rc1 = $LASTEXITCODE
  if ($rc1 -ne 0) { return [pscustomobject]@{ Set = $j.Set; File = $leaf; Kind = $(if ($rc1 -eq 3) { 'DECLINED' } else { "EXIT $rc1" }); Detail = $m1.Trim() } }
  $m2 = & $exe --ini $j.Ini $p1 --o $p2 2>&1 | Out-String; $rc2 = $LASTEXITCODE
  if ($rc2 -ne 0) { return [pscustomobject]@{ Set = $j.Set; File = $leaf; Kind = $(if ($rc2 -eq 3) { 'DECLINED (2nd run)' } else { "EXIT $rc2 (2nd run)" }); Detail = $m2.Trim() } }
  $b1 = [IO.File]::ReadAllBytes($p1); $b2 = [IO.File]::ReadAllBytes($p2)
  if (-not [Linq.Enumerable]::SequenceEqual($b1, $b2)) {
    $d = @(& git -c core.autocrlf=false diff --no-index --no-color -U0 -- $p1 $p2 2>&1 | Select-Object -Skip 4 -First $using:ShowDiff)
    return [pscustomobject]@{ Set = $j.Set; File = $leaf; Kind = 'NOT IDEMPOTENT'; Detail = ($d -join "`n") }
  }
  [pscustomobject]@{ Set = $j.Set; File = $leaf; Kind = 'ok'; Detail = '' }
}
$bad = @($results | Where-Object Kind -ne 'ok')
foreach ($r in $bad) { Write-Output "$($r.Kind) [$($r.Set)] $($r.File)`n    $($r.Detail -replace "`n", "`n    ")" }
Write-Output ("battery_options: {0} sets x {1} fixtures = {2} runs (x2 passes), {3} bad" -f $all.Count, $fixtures.Count, $results.Count, $bad.Count)
[IO.Directory]::Delete($work, $true)
exit $(if ($bad.Count -eq 0) { 0 } else { 1 })
