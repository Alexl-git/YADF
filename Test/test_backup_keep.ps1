# BackupKeep (owner design 2026-11-03): after a run writes a backup of a file,
# the OLDER backups of that SAME file beyond the newest N are deleted.
#   N = 0 (default)  keeps every backup (the behaviour before the option).
#   Only names YADF itself generates for that exact file are ever candidates:
#   sibling <file>.BCKn, or <BackupDir>\<file>.<yyyymmdd-hhnnss>[-n].bak.
#   Other files' backups -- including look-alike names -- are never touched.
#
# Usage: pwsh Test\test_backup_keep.ps1   (exit 0 = pass, 1 = fail)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'backup_keep' $exe

$root = Join-Path $env:TEMP ('bkkeep_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root -Force | Out-Null

# A source YADF always changes; $tag makes every run's ORIGINAL distinct.
function Write-Ugly([string]$path, [string]$tag) {
  $s = "unit U;`r`ninterface`r`nprocedure P;`r`nimplementation`r`nprocedure P;`r`nbegin`r`nif 1>0 then`r`nP; // $tag`r`nend;`r`nend.`r`n"
  [IO.File]::WriteAllText($path, $s, [Text.Encoding]::ASCII)
}
# Runs YADF $n times on $f, each time from a fresh ugly original tagged run1..runN.
function Run-Many([string]$f, [int]$n, [string[]]$extra) {
  for ($i = 1; $i -le $n; $i++) {
    Write-Ugly $f "run$i"
    & $exe --ini $ini @extra $f | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "exit $LASTEXITCODE for $f (run $i)" }
  }
}
function Tags([string[]]$files) {
  @($files | ForEach-Object { if ((Get-Content $_ -Raw) -match '// (run\d+)') { $Matches[1] } } | Sort-Object)
}
function Same([object[]]$a, [object[]]$b) { (($a -join ',') -eq ($b -join ',')) }

# 1. sibling backups, N = 0: all kept
$d = Join-Path $root 's0'; New-Item -ItemType Directory $d | Out-Null
$f = Join-Path $d 'same.pas'
Run-Many $f 4 @('--b')
$baks = @(Get-ChildItem $d -Filter 'same.pas.BCK*' | ForEach-Object FullName)
if ($baks.Count -ne 4) { Fail "N=0 sibling: expected 4 backups, found $($baks.Count)" }

# 2. sibling backups, N = 2, with other files' backups in the same folder
$d = Join-Path $root 's2'; New-Item -ItemType Directory $d | Out-Null
$f = Join-Path $d 'same.pas'
$other = @('other.pas.BCK1', 'other.pas.BCK2', 'other.pas.BCK3', 'xsame.pas.BCK1', 'same.pas2.BCK1', 'same.pas.BCKx', 'same.pas.BCK1.old')
foreach ($o in $other) { Set-Content (Join-Path $d $o) 'decoy' }
Run-Many $f 4 @('--b', '--backup-keep', '2')
$baks = @(Get-ChildItem $d | Where-Object { $_.Name -match '^same\.pas\.BCK\d+$' } | ForEach-Object FullName)
if ($baks.Count -ne 2) { Fail "N=2 sibling: expected 2 backups, found $($baks.Count)" }
# every run backs up its own original (run1..run4); the newest two are run3 and run4
if (-not (Same (Tags $baks) @('run3', 'run4'))) { Fail "N=2 sibling: kept $((Tags $baks) -join ',') instead of run3,run4" }
foreach ($o in $other) { if (-not (Test-Path (Join-Path $d $o))) { Fail "N=2 sibling: touched unrelated file $o" } }

# 3. backup folder, N = 2, two files sharing the folder
$d = Join-Path $root 'dir'; New-Item -ItemType Directory $d | Out-Null
$bak = Join-Path $root 'bak'
$f = Join-Path $d 'same.pas'; $g = Join-Path $d 'alien.pas'
Run-Many $g 3 @('--b', $bak)
Run-Many $f 4 @('--b', $bak, '--backup-keep', '2')
$mine = @(Get-ChildItem $bak -Filter 'same.pas.*.bak' | ForEach-Object FullName)
$theirs = @(Get-ChildItem $bak -Filter 'alien.pas.*.bak' | ForEach-Object FullName)
if ($mine.Count -ne 2) { Fail "N=2 dir: expected 2 backups of same.pas, found $($mine.Count)" }
elseif (-not (Same (Tags $mine) @('run3', 'run4'))) { Fail "N=2 dir: kept $((Tags $mine) -join ',') instead of run3,run4" }
if ($theirs.Count -ne 3) { Fail "N=2 dir: alien.pas backups touched ($($theirs.Count) left of 3)" }

# 4. INI key BackupKeep=1; the CLI flag wins over the INI
$ini2 = Join-Path $root 'k.ini'
$text = [IO.File]::ReadAllText($ini)
if ($text -match '(?im)^BackupKeep\s*=') { $text = $text -replace '(?im)^BackupKeep\s*=.*$', 'BackupKeep=1' }
else { $text = $text -replace '(?im)^\[Format\]\s*$', "[Format]`r`nBackupKeep=1" }
[IO.File]::WriteAllText($ini2, $text, [Text.Encoding]::ASCII)
$d = Join-Path $root 'ini'; New-Item -ItemType Directory $d | Out-Null
$f = Join-Path $d 'same.pas'
for ($i = 1; $i -le 3; $i++) { Write-Ugly $f "run$i"; & $exe --ini $ini2 --b $f | Out-Null }
$baks = @(Get-ChildItem $d -Filter 'same.pas.BCK*' | ForEach-Object FullName)
if (-not (Same (Tags $baks) @('run3'))) { Fail "INI BackupKeep=1: kept $((Tags $baks) -join ',') instead of run3" }
$d = Join-Path $root 'ini2'; New-Item -ItemType Directory $d | Out-Null
$f = Join-Path $d 'same.pas'
for ($i = 1; $i -le 4; $i++) { Write-Ugly $f "run$i"; & $exe --ini $ini2 --b --backup-keep 3 $f | Out-Null }
$baks = @(Get-ChildItem $d -Filter 'same.pas.BCK*')
if ($baks.Count -ne 3) { Fail "CLI --backup-keep 3 over INI 1: expected 3, found $($baks.Count)" }

# 5. no backup requested: nothing is pruned
$d = Join-Path $root 'nob'; New-Item -ItemType Directory $d | Out-Null
$f = Join-Path $d 'same.pas'
foreach ($n in 1..3) { Set-Content "$f.BCK$n" "pre$n" }
Write-Ugly $f 'run1'
& $exe --ini $ini --backup-keep 1 $f | Out-Null
if (@(Get-ChildItem $d -Filter 'same.pas.BCK*').Count -ne 3) { Fail 'no --b: existing backups were pruned' }

[IO.Directory]::Delete($root, $true)
Finish 'backup_keep'
