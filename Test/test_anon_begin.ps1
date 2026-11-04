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
Finish 'anon_begin'