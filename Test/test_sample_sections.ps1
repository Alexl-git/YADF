# Preview-sample ISOLATION suite: toggling ONE option box changes ONE block of
# Demo\Sample.pas (SPEC-2026-11-01 task 4).
#
# Demo\Sample.pas is the Options-page live preview. It is cut into blocks by
# marker lines:
#   // == Option: Ident ==          a block owned by one option
#   // == Option: Ident + Other ==  a block shared by two options that work on
#                                   the same construct (documented couplings)
#   // == Rule: text ==             a fixed rule; no option may change it
# For every option with a preview effect the sample is formatted twice -- all
# defaults, and the same with ONLY that option flipped (bool) or set to the
# value in $Toggle (int) -- and the suite asserts:
#   - at least one block owned by the option changes (the block shows it);
#   - no block NOT owned by the option changes (two options touching one
#     block = a contradiction in the sample, or an engine leak);
#   - every option has a block, unless listed in $NoBlock with the reason.
# $Global lists the options whose effect is file-wide by nature: they need a
# block, but may change other blocks too.
# Also: Sample.pas and the default output compile (dcc64), every run is
# idempotent, exit 0 / no guard decline.
#
# -WriteHelp: rewrites the "## Example" section of docs\help-site\options\
# <id>.md for every option with a block, from the REAL input / default / flipped
# output of that block (same snippets as the preview). Rerun after any engine
# or Sample.pas change, then regenerate the merged help.
#
# Exit 0 = pass, 1 = failures, 2 = skip (no exe).
param([switch]$WriteHelp, [switch]$ShowDiff)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'sample_sections' $exe
$root   = Split-Path $PSScriptRoot -Parent
$sample = Join-Path $root 'Demo\Sample.pas'

# Value used for an int option's run (bools are simply flipped).
$Toggle = [ordered]@{
  MaxLen = 150; Indent = 4; TabWidth = 8; MaxBlankLines = 2; BlanksBeforeSection = 1
  BlanksBeforeMethod = 1; BlanksBeforeType = 1; AlignMaxColumn = 50; AlignShapeMinAnchors = 6
  AlignCommentMaxShift = 30; LabelMinLines = 30
}
# File-wide by nature: may change other blocks too.
$Global = @{
  Indent = 'every indented line follows the indent step'
  AlignSmartAssign = 'master switch of every := run and shape alignment'
}
# No block in the sample, with the reason.
$NoBlock = @{
  MarkUnclosed = 'needs an unclosed begin/record, which cannot compile'
  # SPEC-2026-11-03: a preset over BreakIfBody/BreakLoopBody/BreakWithBody/
  # CaseArmOnLabelLine; a fully written INI sets those four explicitly, so the
  # preset changes nothing there and its effect is exactly those four blocks.
  PackShortBodies = 'preset over the four Short bodies rules; shown by their blocks'
}

$work = Join-Path $env:TEMP ('sample_sections_' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$dcuDir = Join-Path $work 'dcu'
[IO.Directory]::CreateDirectory($dcuDir) | Out-Null
$haveDcc = Test-Path (Get-Dcc64)

# --- defaults + the option list from a freshly written INI ------------------
$ini0 = Join-Path $work 'default.ini'
& $exe --ini $ini0 --stdout $sample *> $null
$defaults = [ordered]@{}
foreach ($l in [IO.File]::ReadAllLines($ini0)) { if ($l -match '^(\w+)\s*=\s*(.*)$') { $defaults[$Matches[1]] = $Matches[2].Trim() } }
$noPreview = @('Backup', 'BackupDir', 'BackupKeep', 'ResultDir', 'Encoding', 'Logging')

function Split-Blocks([string]$text) {
  $blocks = [ordered]@{}
  $cur = '(head)'; $buf = New-Object System.Collections.Generic.List[string]
  foreach ($l in ($text -split "`r`n")) {
    $m = [regex]::Match($l, '^\s*// == (Option|Rule): (.+?) ==\s*$')
    if ($m.Success) { $blocks[$cur] = $buf -join "`r`n"; $cur = $m.Groups[1].Value + ': ' + $m.Groups[2].Value; $buf = New-Object System.Collections.Generic.List[string]; continue }
    $buf.Add($l)
  }
  $blocks[$cur] = $buf -join "`r`n"
  return $blocks
}
function Get-Owners([string]$name) { if ($name -like 'Option: *') { @($name.Substring(8) -split '\s*\+\s*') } else { @() } }

function Format-Sample([string]$key, [string]$value) {
  $runDir = Join-Path $work ([guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($runDir) | Out-Null
  $ini = Join-Path $runDir 'run.ini'
  $body = "[Format]`r`n" + $(if ($key) { "$key=$value`r`n" } else { '' })
  [IO.File]::WriteAllText($ini, $body, [Text.Encoding]::ASCII)
  $out1 = Join-Path $runDir 'Sample.pas'
  $out2 = Join-Path $runDir 'Sample.2.pas'
  if (-not ((Invoke-Yadf $sample $ini $out1) -and (Invoke-Yadf $out1 $ini $out2))) { return $null }
  if (-not (SameBytes $out1 $out2)) { Fail "not idempotent: $key=$value" }
  return [pscustomobject]@{ Path = $out1; Text = [IO.File]::ReadAllText($out1) }
}

$passed = 0
$examples = @{}
try {
  if ($haveDcc) { if (-not (Test-DccCompiles $sample (Split-Path $sample) $dcuDir)) { Fail 'Demo\Sample.pas does not compile' } }
  else { Fail "dcc64 missing at $(Get-Dcc64)" }
  $src  = [IO.File]::ReadAllText($sample)
  $inB  = Split-Blocks $src
  $base = Format-Sample '' ''
  if ($null -eq $base) { throw 'default run failed' }
  # Idempotence at the small MaxLen values that broke BreakLongExpressions (task 5a:
  # ShowReflow's `Pos(` list was laid out comma-first, the next format rejoined it).
  # The MaxLen toggle above stays 150 only because Sample.pas's MaxLen block (and
  # its help example) is written for 150.
  foreach ($ml in 100, 120, 130) { if ($null -eq (Format-Sample 'MaxLen' $ml)) { Fail "MaxLen=$ml run failed" } }
  if ($haveDcc -and -not (Test-DccCompiles $base.Path $work $dcuDir)) { Fail 'default output of Sample.pas does not compile' }
  $baseB = Split-Blocks $base.Text
  if (@($inB.Keys) -join '|' -ne (@($baseB.Keys) -join '|')) { Fail 'block markers changed by formatting' }

  $owned = @{}
  foreach ($k in $baseB.Keys) { foreach ($o in (Get-Owners $k)) { if (-not $defaults.Contains($o)) { Fail "block '$k' names unknown option '$o'" }; $owned[$o] = $true } }

  foreach ($opt in $defaults.Keys) {
    if ($noPreview -contains $opt) { continue }
    if ($NoBlock.ContainsKey($opt)) { if ($owned[$opt]) { Fail "$opt is in NoBlock but owns a block" }; continue }
    if (-not $owned[$opt]) { Fail "$opt has no block in Sample.pas"; continue }
    $d = $defaults[$opt]
    $v = if ($d -eq 'true') { 'false' } elseif ($d -eq 'false') { 'true' } elseif ($Toggle.Contains($opt)) { [string]$Toggle[$opt] } else { Fail "$opt needs a Toggle value"; continue }
    $run = Format-Sample $opt $v
    if ($null -eq $run) { continue }
    $runB = Split-Blocks $run.Text
    if (@($runB.Keys) -join '|' -ne (@($baseB.Keys) -join '|')) { Fail "${opt}=${v}: block markers changed"; continue }
    $own = @(); $leak = @()
    foreach ($k in $baseB.Keys) {
      if ($baseB[$k] -ceq $runB[$k]) { continue }
      if ((Get-Owners $k) -contains $opt) { $own += $k } else { $leak += $k }
    }
    $bad = @()
    if ($own.Count -eq 0) { $bad += 'its own block does not change' }
    if ($leak.Count -gt 0 -and -not $Global.ContainsKey($opt)) { $bad += "also changes: $($leak -join '; ')" }
    if ($bad.Count) {
      Fail "${opt}=${v}: $($bad -join ' | ')"
      if ($ShowDiff) { foreach ($k in $leak) { Write-Output "  --- [$k] default:`n$($baseB[$k])`n  --- ${opt}=${v}:`n$($runB[$k])" } }
      continue
    }
    $passed++
    $examples[$opt] = [pscustomobject]@{ Value = $v; Default = $d; Blocks = @($baseB.Keys | Where-Object { (Get-Owners $_) -contains $opt })
      Base = $baseB; Run = $runB }
  }

  if ($WriteHelp) {
    $optDir = Join-Path $root 'docs\help-site\options'
    $enc = New-Object System.Text.UTF8Encoding($false)
    function Get-Code([string]$block) {
      # drop the explanatory comment lines right under the marker, and blank edges
      $ls = @($block -split "`r`n")
      $i = 0
      while ($i -lt $ls.Count -and $ls[$i] -match '^\s*//') { $i++ }
      $ls = @($ls | Select-Object -Skip $i)
      while ($ls.Count -and $ls[0].Trim() -eq '') { $ls = @($ls | Select-Object -Skip 1) }
      while ($ls.Count -and $ls[-1].Trim() -eq '') { $ls = @($ls | Select-Object -First ($ls.Count - 1)) }
      return ($ls -join "`n")
    }
    foreach ($opt in $examples.Keys) {
      $e = $examples[$opt]
      $id = ($opt -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLower()
      $p = Join-Path $optDir "$id.md"
      if (-not (Test-Path $p)) { Fail "no help leaf for $opt ($id.md)"; continue }
      $parts = @()
      foreach ($k in $e.Blocks) {
        $parts += "// input`n" + (Get-Code $inB[$k]) + "`n`n// $opt = $($e.Default) (default)`n" + (Get-Code $e.Base[$k]) +
                  "`n`n// $opt = $($e.Value)`n" + (Get-Code $e.Run[$k])
      }
      $ex = "## Example`n`nReal YADF output for the `"$($e.Blocks[0].Substring(8))`" block of the preview sample (Demo\Sample.pas), " +
            "all other options at their defaults:`n`n" + '```pascal' + "`n" + ($parts -join "`n`n") + "`n" + '```' + "`n"
      if ($ex -match '[^\x00-\x7F]') { Fail "non-ASCII example for $opt"; continue }
      $t = [IO.File]::ReadAllText($p) -replace "`r`n", "`n"
      $rx = [regex]'(?s)## Example\n.*?(?=\n## |\z)'
      if ($rx.IsMatch($t)) { $t = $rx.Replace($t, $ex.TrimEnd("`n") + "`n", 1) }
      elseif ($t -match '\n## Related\n') { $t = $t.Replace("`n## Related`n", "`n$ex`n## Related`n") }
      else { $t = $t.TrimEnd("`n") + "`n`n$ex" }
      [IO.File]::WriteAllText($p, $t, $enc)
    }
    Write-Output "sample_sections: wrote ## Example into $($examples.Count) help leaves"
  }
}
finally { [IO.Directory]::Delete($work, $true) }

if ($script:fail -eq 0) {
  Write-Output ("sample_sections: PASS ({0} options isolated, {1} global, {2} without a block)" -f $passed, $Global.Count, $NoBlock.Count)
  exit 0
}
Write-Output ("sample_sections: {0} FAILED ({1} passed)" -f $script:fail, $passed)
exit 1
