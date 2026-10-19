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

function Format-Case([string]$name, [string[]]$flags = @()) {
  $tmpDir = Join-Path $env:TEMP ("revcorr_" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory $tmpDir | Out-Null
  $out = Join-Path $tmpDir $name
  $msg = & $exe --ini $ini (Join-Path $cases $name) @flags --o $out 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0)        { Fail "review_corruption: $name exit $LASTEXITCODE -- $msg" | Out-Host; return $null }
  if ($msg -match '(?m)^declined ') { Fail "review_corruption: $name was DECLINED -- $msg" | Out-Host; return $null }
  if (-not (Test-Path $out))      { Fail "review_corruption: $name produced no output" | Out-Host; return $null }
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

# ---- asm_same_line: an instruction on the `asm` line itself must be shielded
#      too (it used to leave the file DECLINED); instructions stay verbatim ----
$asl = Format-Case 'asm_same_line.pas'
if ($asl) {
  $txt = [IO.File]::ReadAllText($asl)
  foreach ($s in 'asm mov eax,[rcx+8]', 'lea eax,[rcx+rdx]', 'add eax,1') {
    if (-not $txt.Contains($s)) { Fail "review_corruption: asm_same_line lost/changed instruction: $s" }
  }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $asl)) { Fail 'review_corruption: formatted asm_same_line.pas does not compile with dcc64' }
  }
}

# ---- dispid_negative: `function F: IUnknown; dispid -4;` -- the directive word
#      follows the routine's own `;`, so the sign must stay unary (cosmetic
#      `dispid - 4` otherwise; both sites that decide this must agree) ----
$dpo = Format-Case 'dispid_negative.pas'
if ($dpo) {
  $txt = [IO.File]::ReadAllText($dpo)
  foreach ($s in 'dispid -4;', 'dispid -2;') {
    if (-not $txt.Contains($s)) { Fail "review_corruption: dispid_negative lost unary sign: $s" }
  }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $dpo)) { Fail 'review_corruption: formatted dispid_negative.pas does not compile with dcc64' }
  }
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

# ---- review_r1_semantics: exponent alignment, directive tail on a split,
#      casing of external imports / enum members (all default settings) ----
$r1Out = Format-Case 'review_r1_semantics.pas'
if ($r1Out) {
  $txt = [IO.File]::ReadAllText($r1Out)
  if ($txt -notmatch 'Eps:=\s*1E-9;')  { Fail 'review_corruption: signed exponent 1E-9 was split' }
  if ($txt -cnotmatch 'function GetTickCount\b') { Fail 'review_corruption: external import GetTickCount was re-cased (load-time entry point)' }
  if ($txt -cnotmatch 'TColor\s*=\s*\(Red, Green\)') { Fail 'review_corruption: enum member Red was re-cased (RTTI name)' }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $r1Out)) { Fail 'review_corruption: formatted review_r1_semantics.pas does not compile with dcc64' }
  }
}

# ---- review_r2_declines: code must never be moved into a // comment
#      (Format-Case fails on a guard decline) ----
$r2Out = Format-Case 'review_r2_declines.pas'
if ($r2Out) {
  $txt = [IO.File]::ReadAllText($r2Out)
  if ($txt -notmatch '// second\s*\r?\n') { Fail 'review_corruption: code was appended to the // second comment' }
  if ($txt -notmatch '// see what we do\s*\r?\n') { Fail 'review_corruption: the // see what we do comment was altered' }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $r2Out)) { Fail 'review_corruption: formatted review_r2_declines.pas does not compile with dcc64' }
  }
}

# ---- --d10 must not hoist an inline var/const out of a conditional ----
$d10Out = Format-Case 'review_d10_ifdef.pas' @('--d10')
if ($d10Out) {
  $txt = [IO.File]::ReadAllText($d10Out)
  $ifdefAt = $txt.IndexOf('{$IFDEF')
  $hoisted = [regex]::Match($txt, '(?m)^\s*X\s*:\s*TOnlyWhenDefined\s*;')
  if ($hoisted.Success -and $hoisted.Index -lt $ifdefAt) { Fail 'review_corruption: --d10 hoisted X out of the {$IFDEF}' }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $d10Out)) { Fail 'review_corruption: --d10 output of review_d10_ifdef.pas does not compile with dcc64' }
  }
}

# ---- continuation lines of `if A and // c` stay deeper than the `if` ----
$ifcOut = Format-Case 'review_r3_if_comment.pas'
if ($ifcOut) {
  $ls = @(Get-Content $ifcOut)
  $ifAt = ($ls | Select-String -SimpleMatch 'if Foo(1) and').LineNumber
  if (-not $ifAt) { Fail 'review_corruption: if_comment: the if line is missing' }
  else {
    $ifInd = ($ls[$ifAt - 1] -replace '\S.*$').Length
    foreach ($k in 0, 1) {
      $cont = $ls[$ifAt + $k]
      $ind = ($cont -replace '\S.*$').Length
      if ($ind -le $ifInd) { Fail "review_corruption: if_comment: continuation [$cont] is not deeper than the if (indent $ind vs $ifInd)" }
    }
  }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $ifcOut)) { Fail 'review_corruption: formatted review_r3_if_comment.pas does not compile with dcc64' }
  }
}

# ---- a method line must not drag the field-semicolon column out ----
$fmOut = Format-Case 'review_r3_field_method.pas'
if ($fmOut) {
  $txt = [IO.File]::ReadAllText($fmOut)
  if ($txt -notmatch '(?m)^\s*FVar2\s*:\s*string {0,2};') { Fail 'review_corruption: field_method: FVar2 semicolon padded out by the method line below' }
  if (Test-Path (Join-Path $bin 'dcc64.exe')) {
    if (-not (Compiles 'dcc64' $fmOut)) { Fail 'review_corruption: formatted review_r3_field_method.pas does not compile with dcc64' }
  }
}

# ---- a `class function` line must not drag a preceding field colon out ----
$cfOut = Format-Case 'generic_constraint_keywords.pas'
if ($cfOut) {
  $txt = [IO.File]::ReadAllText($cfOut)
  if ($txt -notmatch '(?m)^\s*FInst\s{0,1}: TAfterSection;') { Fail 'review_corruption: class_function_boundary: FInst colon padded out by the class function below' }
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
