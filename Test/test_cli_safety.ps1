# Write-path safety (review 2026-10-14, reviewer #5) -- every case is a way
# the CLI could leave the user without a copy of their original source:
#
#   1. `--b foo.pas`  : --b swallowed the file as a BackupDir name; nothing
#                       was formatted. Now: sibling backup + formatted file.
#   2. BackupDir      : two inputs with the same basename in one second wrote
#                       the SAME .bak name with overwrite -> first backup lost.
#   3. `--o <input>`  : output resolving to the input overwrote it with no
#                       backup even with --b. Now: in-place path, backup kept.
#   4. `--of <srcdir>`: same, for the result-dir mode.
#   5. `--batch d d`  : refused (exit 1), file untouched.
#
# Usage: pwsh Test\test_cli_safety.ps1   (exit 0 = pass, 1 = fail)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'cli_safety' $exe

$ugly = "unit U;`r`ninterface`r`nprocedure P;`r`nimplementation`r`nprocedure P;`r`nbegin`r`nif 1>0 then`r`nP;`r`nend;`r`nend.`r`n"
function New-Case([string]$sub) {
  $d = Join-Path $env:TEMP ("clisafe_" + [guid]::NewGuid().ToString('N') + "\$sub")
  New-Item -ItemType Directory $d -Force | Out-Null
  $f = Join-Path $d 'same.pas'
  [IO.File]::WriteAllText($f, $ugly, [Text.Encoding]::ASCII)
  return $f
}
function Hash([string]$p) { (Get-FileHash $p).Hash }
$uglyHash = $null

# 1. --b followed by the file
$f = New-Case 'one'
$uglyHash = Hash $f
& $exe --ini $ini --b $f | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "--b <file>: exit $LASTEXITCODE" }
if ((Hash $f) -eq $uglyHash) { Fail '--b <file>: the file was not formatted (argument swallowed as BackupDir?)' }
$bck = "$f.BCK1"
if (-not (Test-Path $bck) -or (Hash $bck) -ne $uglyHash) { Fail '--b <file>: no sibling .BCK1 holding the original' }

# 2. BackupDir collision: same basename, one run
$a = New-Case 'a'; $b = Join-Path (Split-Path (Split-Path $a)) 'b\same.pas'
New-Item -ItemType Directory (Split-Path $b) -Force | Out-Null
[IO.File]::WriteAllText($b, $ugly.Replace('P;', 'Q;'), [Text.Encoding]::ASCII)
$ha = Hash $a; $hb = Hash $b
$bak = Join-Path (Split-Path (Split-Path $a)) 'bak'
& $exe --ini $ini $a $b --b $bak | Out-Null
$baks = @(Get-ChildItem $bak -File -ErrorAction SilentlyContinue)
$hs = @($baks | ForEach-Object { Hash $_.FullName })
if ($baks.Count -ne 2 -or -not ($hs -contains $ha) -or -not ($hs -contains $hb)) {
  Fail "BackupDir: expected 2 backups holding both originals, found $($baks.Count)"
}

# 3. --o pointing at the input itself, with --b
$f = New-Case 'o'
$h0 = Hash $f
& $exe --ini $ini $f --o $f --b | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "--o <input>: exit $LASTEXITCODE" }
if (-not (Test-Path "$f.BCK1") -or (Hash "$f.BCK1") -ne $h0) { Fail '--o <input> --b: original overwritten without a backup' }

# 4. --of pointing at the input's own folder, with --b
$f = New-Case 'of'
$h0 = Hash $f
& $exe --ini $ini $f --of (Split-Path $f) --b | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "--of <srcdir>: exit $LASTEXITCODE" }
if (-not (Test-Path "$f.BCK1") -or (Hash "$f.BCK1") -ne $h0) { Fail '--of <srcdir> --b: original overwritten without a backup' }

# 5. --batch with in == out
$f = New-Case 'batch'
$h0 = Hash $f
& $exe --ini $ini --batch (Split-Path $f) (Split-Path $f) | Out-Null
if ($LASTEXITCODE -eq 0) { Fail '--batch d d: accepted (expected a refusal, exit 1)' }
if ((Hash $f) -ne $h0) { Fail '--batch d d: source was modified' }

# 6. in-place format keeps the file identity: Hidden attribute + alternate data stream (review 2026-10-14 #5)
$f = New-Case 'ads'
Set-Content -LiteralPath $f -Stream 'yadf.test' -Value 'keepme'
(Get-Item -LiteralPath $f).Attributes = 'Hidden,Archive'
& $exe --ini $ini $f | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "ads: exit $LASTEXITCODE" }
if ((Hash $f) -eq $uglyHash) { Fail 'ads: file was not formatted' }
if (-not ((Get-Item -LiteralPath $f -Force).Attributes -band [IO.FileAttributes]::Hidden)) { Fail 'in-place format dropped the Hidden attribute' }
$s = Get-Content -LiteralPath $f -Stream 'yadf.test' -ErrorAction SilentlyContinue
if ($s -ne 'keepme') { Fail 'in-place format dropped the alternate data stream' }

Finish 'cli_safety'
