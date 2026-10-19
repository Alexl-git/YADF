# Line-ending policy: YADF output is CRLF-always. A source with bare-LF line
# endings must come back with CRLF EVERYWHERE -- including inside the atoms that
# the formatter shields and restores verbatim (multi-line strings, multi-line
# block comments, asm bodies). Before WP10 those restored byte-for-byte with
# their LF, leaving a mixed-EOL file. (Eol=preserve and LF editor buffers are a
# declined option; see README.) Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'eol_normalize' $exe

$lf = @(
  'unit U;'
  'interface'
  'implementation'
  'const'
  "  CMsg = '''"
  '    first line'
  '    second line'
  "    ''';"
  'procedure P;'
  'begin'
  '  { a block'
  '    comment }'
  '  X:= 1;'
  '  (* another'
  '     one *)'
  'end;'
  'procedure Q; assembler;'
  'asm'
  '  mov eax, 1'
  '  ret'
  'end;'
  'end.'
) -join "`n"

$in  = New-TempOut
$out = New-TempOut
[IO.File]::WriteAllText($in, $lf + "`n", (New-Object Text.ASCIIEncoding))
if (Invoke-Yadf $in $ini $out) {
  $bytes = [IO.File]::ReadAllBytes($out)
  $bare = 0
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) { $bare++ }
  }
  if ($bare -ne 0) { Fail "output has $bare bare LF byte(s); expected CRLF everywhere" }
  $text = [Text.Encoding]::ASCII.GetString($bytes)
  MustContain $text "'''`r`n    first line`r`n    second line`r`n    '''" 'multi-line string kept, CRLF'
  MustContain $text "{ a block`r`n    comment }"                         'brace comment kept, CRLF'
  MustContain $text "(* another`r`n     one *)"                          'paren comment kept, CRLF'
  MustMatch   $text '(?m)^\s*mov eax, 1\r$'                              'asm body kept, CRLF'
}
[IO.File]::Delete($in)
if (Test-Path $out) { [IO.File]::Delete($out) }

# A source with CR-ONLY (classic Mac) line endings: a lone CR inside a block
# comment used to survive, giving a mixed-EOL file. The output has no bare CR.
$crSrc = ("unit U;`r`ninterface`r`nconst`r`n  T = 'x'; { c`r`n  d }`r`nimplementation`r`nprocedure P;`r`nbegin`r`n  { a block`r`n    comment }`r`n  X:= 1;`r`nend;`r`nend.`r`n") -replace "`r`n", "`r"
$in2  = New-TempOut
$out2 = New-TempOut
[IO.File]::WriteAllText($in2, $crSrc, (New-Object Text.ASCIIEncoding))
if (Invoke-Yadf $in2 $ini $out2) {
  $b2 = [IO.File]::ReadAllBytes($out2)
  $bareCr = 0
  for ($i = 0; $i -lt $b2.Length; $i++) {
    if ($b2[$i] -eq 13 -and ($i + 1 -ge $b2.Length -or $b2[$i + 1] -ne 10)) { $bareCr++ }
  }
  if ($bareCr -ne 0) { Fail "CR-only source: output has $bareCr bare CR byte(s); expected CRLF everywhere" }
  MustContain ([Text.Encoding]::ASCII.GetString($b2)) "{ c`r`n  d }" 'CR-only: block comment kept, CRLF'
}
[IO.File]::Delete($in2)
if (Test-Path $out2) { [IO.File]::Delete($out2) }

Finish 'eol_normalize'
