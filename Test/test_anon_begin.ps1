# Owner rule (2026-11-03): a multi-line anonymous method's `begin` sits at the level
# of its header line (the line holding `procedure` / `function`), its statements one
# Indent in, its `end` back at the header level -- whether it is assigned
# (`X:= procedure`), wrapped onto its own line, or passed as a call argument (alone,
# after another argument, under an if). The body is never flattened onto one line.
# Fixture Test\Cases\idem\idem_anon_method_begin.pas (also run by test_idempotence
# at ten option sets and compile-checked there). Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'anon_begin' $exe
$fail = 0
$src = Join-Path $PSScriptRoot 'Cases\idem\idem_anon_method_begin.pas'
foreach ($set in @(@{ Name = 'indent2'; Flags = @(); Ind = 2 }, @{ Name = 'indent4'; Flags = @('--indent', '4'); Ind = 4 })) {
  $out = & $exe --ini $ini @($set.Flags) --stdout $src 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "[$($set.Name)] exit $LASTEXITCODE -- $out"; continue }
  $lines = $out -split "`r?`n"
  $body = [Array]::IndexOf($lines, 'procedure Shapes;')
  $seen = 0
  for ($i = $body + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '\b(procedure|function)\b' -or $lines[$i] -match '^\s*(procedure|function) \w+[;(]' -or $lines[$i] -match '^\s*end\b') { continue }
    # a comma-first item line (, procedure): the header is the item, the comma hangs left
    $hdr = $lines[$i] -replace '^(\s*)(, )?.*', '$1$2' -replace ',', ' '
    $b = $i + 1; while ($b -lt $lines.Count -and $lines[$b].Trim() -ne 'begin') { $b++ }
    $seen++
    $tag = "[$($set.Name)] header line $($i + 1) '$($lines[$i].Trim())'"
    if ($b -ge $lines.Count -or $b -gt $i + 1) { Fail "$tag`: begin not on the next line"; continue }
    if (($lines[$b] -replace '^(\s*).*', '$1') -ne $hdr) { Fail "$tag`: begin at column $($lines[$b].IndexOf('b')) (header $($hdr.Length))" }
    if (($lines[$b + 1] -replace '^(\s*).*', '$1').Length -ne $hdr.Length + $set.Ind) { Fail "$tag`: first statement not one Indent in: '$($lines[$b + 1])'" }
    $e = $b + 1; $d = 1
    while ($e -lt $lines.Count -and $d -gt 0) { if ($lines[$e] -match '^\s*(begin|case|try)\b') { $d++ } elseif ($lines[$e] -match '^\s*end\b') { $d-- }; if ($d -gt 0) { $e++ } }
    if ($e -ge $lines.Count -or ($lines[$e] -replace '^(\s*).*', '$1') -ne $hdr) { Fail "$tag`: end not at the header column" }
  }
  if ($seen -ne 7) { Fail "[$($set.Name)] expected 7 multi-line anonymous methods, found $seen" }
  MustMatch $out ('(?m)^' + (' ' * $set.Ind) + 'Writeln\(''after''\);') "[$($set.Name)] statement after the anonymous methods back at the body column"
  $r = [Array]::FindIndex($lines, [Predicate[string]]{ param($x) $x.Trim() -eq 'Result:= 0;' })
  if ($r -lt 0 -or ($lines[$r + 1] -replace '^(\s*).*', '$1').Length -ne ($lines[$r] -replace '^(\s*).*', '$1').Length - $set.Ind) { Fail "[$($set.Name)] statement after an if/else chain inside the method over-indented: '$($lines[$r + 1])'" }
}
# Owner decision (2026-11-03): `X:=` / `procedure` on two lines -- the header goes one
# Indent in as a continuation of the assignment, begin/end at the header's column,
# the body one more Indent in. Fixture Test\Cases\idem\idem_anon_assign_wrap.pas.
$src2 = Join-Path $PSScriptRoot 'Cases\idem\idem_anon_assign_wrap.pas'
foreach ($ind in 2, 4) {
  $out = & $exe --ini $ini --indent $ind --stdout $src2 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "[wrap indent$ind] exit $LASTEXITCODE -- $out"; continue }
  $lines = $out -split "`r?`n"
  $seen = 0
  for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    if ($lines[$i] -notmatch '^(\s*)\w+:=$') { continue }
    $seen++
    $col = $Matches[1].Length + $ind
    $tag = "[wrap indent$ind] '$($lines[$i].Trim())' at line $($i + 1)"
    $want = @(@($col, '(procedure|function)\b'), @($col, 'begin$'), @(($col + $ind), '\S'))
    for ($k = 0; $k -lt 3; $k++) {
      $l = $lines[$i + 1 + $k]
      if (($l -replace '^(\s*).*', '$1').Length -ne $want[$k][0] -or $l.Trim() -notmatch ('^' + $want[$k][1])) { Fail "$tag`: line +$($k + 1) '$l' not at column $($want[$k][0])" }
    }
    $e = $i + 3; $d = 1
    while ($e -lt $lines.Count -and $d -gt 0) { $e++; if ($lines[$e] -match '^\s*(begin|case|try)\b') { $d++ } elseif ($lines[$e] -match '^\s*end\b') { $d-- } }
    if (($lines[$e] -replace '^(\s*).*', '$1').Length -ne $col) { Fail "$tag`: end '$($lines[$e])' not at column $col" }
  }
  if ($seen -ne 4) { Fail "[wrap indent$ind] expected 4 wrapped assignments, found $seen" }
  MustMatch $out ('(?m)^' + (' ' * $ind) + 'Writeln\(''after''\);') "[wrap indent$ind] statement after the methods back at the body column"
  MustMatch $out ('(?m)^' + (' ' * $ind) + 'P:= procedure\r?\n' + (' ' * $ind) + 'begin') "[wrap indent$ind] same-line header keeps begin at the statement column"
}
Finish 'anon_begin'