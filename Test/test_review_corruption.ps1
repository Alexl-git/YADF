# RED targets from the 2026-10-14 software review -- confirmed CORRUPTION
# (output that no longer compiles or silently loses bytes, guard did not
# decline). Each case asserts the property, not a style:
#
#   asm_blocks.pas       every BASM instruction line survives verbatim (same
#                        text, same count, one per line); the output compiles
#                        with dcc32 AND dcc64; the routine after an asm-bodied
#                        routine is not indented (asm body balanced).
#   ml_string_include.pas  both real {$I params.inc} directives survive; the
#                        {$I ...} / {$INCLUDE ...} TEXT inside the ''' strings
#                        is byte-identical; the shield sentinel never leaks.
#
# Every run uses a fresh GUID temp file, checks the exit code and that the
# output exists, and treats a guard decline as a failure (the fixtures are
# formattable; a decline would mean the fix only made YADF give up).
#
# Usage: pwsh Test\test_review_corruption.ps1   (exit 0 = pass, 1 = fail)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'review_corruption' $exe
$cases = Join-Path $PSScriptRoot 'Cases'
$bin   = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin'

function Format-Case([string]$name) {
  $tmpDir = Join-Path $env:TEMP ("revcorr_" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory $tmpDir | Out-Null
  $out = Join-Path $tmpDir $name
  $msg = & $exe --ini $ini (Join-Path $cases $name) --o $out 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0)        { Fail "review_corruption: $name exit $LASTEXITCODE -- $msg"; return $null }
  if ($msg -match '(?i)declin')   { Fail "review_corruption: $name was DECLINED -- $msg"; return $null }
  if (-not (Test-Path $out))      { Fail "review_corruption: $name produced no output"; return $null }
  return $out
}

function Compiles([string]$dcc, [string]$file) {
  $dir = Split-Path $file
  & (Join-Path $bin $dcc) -Q -B "-N0$dir" "-E$dir" "-I$cases" $file *> $null
  return ($LASTEXITCODE -eq 0)
}

# ---- asm_blocks ----
$asmSrc = Join-Path $cases 'asm_blocks.pas'
$asmOut = Format-Case 'asm_blocks.pas'
if ($asmOut) {
  $re = '^\s*(mov|add|and|jmp|cmp|je|@@\w+:)'
  $want = @(Get-Content $asmSrc | Where-Object { $_ -match $re } | ForEach-Object { $_.Trim() })
  $got  = @(Get-Content $asmOut | Where-Object { $_ -match $re } | ForEach-Object { $_.Trim() })
  if (($want -join "`n") -cne ($got -join "`n")) {
    Fail ("review_corruption: asm instruction lines changed. want [" + ($want -join ' | ') + "] got [" + ($got -join ' | ') + "]")
  }
  foreach ($c in 'dcc32', 'dcc64') {
    if (Test-Path (Join-Path $bin "$c.exe")) {
      if (-not (Compiles $c $asmOut)) { Fail "review_corruption: formatted asm_blocks.pas does not compile with $c" }
    } else { Fail "review_corruption: $c.exe missing -- cannot prove the asm output compiles" }
  }
  $after = Get-Content $asmOut | Where-Object { $_ -match '^\s*function AfterAsm' }
  foreach ($l in $after) { if ($l -match '^\s+') { Fail "review_corruption: routine after asm bodies is indented: [$l]" } }
}

# ---- ml_string_include ----
$incSrc = Join-Path $cases 'ml_string_include.pas'
$incOut = Format-Case 'ml_string_include.pas'
if ($incOut) {
  $txt = [IO.File]::ReadAllText($incOut)
  if ($txt -match 'ZQYADF') { Fail 'review_corruption: include-shield sentinel ZQYADF leaked into the output' }
  $n = ([regex]::Matches($txt, '\{\$I params\.inc\}')).Count
  if ($n -ne 2) { Fail "review_corruption: expected 2 real {`$I params.inc} directives, found $n" }
  foreach ($s in "don't {`$I foo.inc}", "plain {`$INCLUDE bar.inc}") {
    if (-not $txt.Contains($s)) { Fail "review_corruption: string content altered, missing: $s" }
  }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $incOut)) { Fail 'review_corruption: formatted ml_string_include.pas does not compile with dcc64' }
  }
}

# ---- NUL byte: the lexer stops at #0, so everything after it used to vanish
# (83 -> 38 bytes, "wrote", exit 0). Now the file must be left byte-identical.
$nulDir = Join-Path $env:TEMP ("revcorr_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $nulDir | Out-Null
$nulFile = Join-Path $nulDir 'nul_inside.pas'
$bytes = [Text.Encoding]::ASCII.GetBytes("unit nul_inside;`r`ninterface`r`nconst A = 'x") + [byte]0 + [Text.Encoding]::ASCII.GetBytes("y';`r`nimplementation`r`nend.`r`n")
[IO.File]::WriteAllBytes($nulFile, $bytes)
$msg = & $exe --ini $ini $nulFile 2>&1 | Out-String
$after = [IO.File]::ReadAllBytes($nulFile)
if ([Convert]::ToBase64String($after) -ne [Convert]::ToBase64String($bytes)) {
  Fail "review_corruption: a file containing a NUL byte was rewritten ($($bytes.Length) -> $($after.Length) bytes) -- $msg"
}

Finish 'review_corruption'
