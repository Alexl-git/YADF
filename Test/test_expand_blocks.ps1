# CollapseShortBlocks OFF (the default) EXPANDS a control-statement begin..end
# block that the source wrote on one line (or half-broken): `begin` stays where
# the author put it, one statement per line, `end` on its own line. The mirror
# of --collapse-blocks. A block holding a comment or a {$...} directive is left
# exactly as written (splitting it is not provably safe). Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'expand_blocks' $exe
$src = Join-Path $PSScriptRoot 'Cases\expand_short_blocks.pas'

$tmp = New-TempOut
if (-not (Invoke-Yadf $src $ini $tmp @('--no-collapse-blocks'))) { Finish 'expand_blocks' }
$off = [IO.File]::ReadAllText($tmp)
[IO.File]::Delete($tmp)

# if/else, both branches one-liners
MustMatch $off '(?m)^  if C then begin\r\n    Log\(3\);\r\n    Exit;\r\n  end\r\n  else begin\r\n    Log\(4\);\r\n  end;\r?$' 'if/else expanded'
# for..do
MustMatch $off '(?m)^  for I:= 0 to 3 do begin\r\n    X\(I\);\r\n    Y;\r\n  end;\r?$' 'for expanded'
# half-broken block: begin line and end line both split
MustMatch $off '(?m)^  if B then begin\r\n    Log\(2\);\r\n    Exit;\r\n  end;\r?$' 'partly broken block expanded'
# nested one-line block inside a one-line block expands recursively
MustMatch $off '(?m)^  while I > 0 do begin\r\n    Dec\(I\);\r\n    if C then begin\r\n      Log\(I\);\r\n      Y;\r\n    end;\r\n  end;\r?$' 'nested expanded'
# a string holding ; begin end is not a split point
MustMatch $off "(?m)^    S:= 'a; b begin end';\r?$" 'string literal kept whole'
# comment / directive inside: left exactly as written
MustMatch $off '(?m)^  if C then begin Log\(5\); \{ keep \} Y; end;\r?$' 'comment block untouched'
MustMatch $off '(?m)^  if B then begin \{\$IFDEF DEBUG\} Log\(9\); \{\$ENDIF\} Y; end;\r?$' 'directive block untouched'
# end else <stmt> keeps the else on the end line
MustMatch $off '(?m)^  if B then begin\r\n    Log\(6\);\r\n    Y;\r\n  end else Log\(7\);\r?$' 'end else stmt'
# begin on its own line after the header
MustMatch $off '(?m)^  if C then\r\n  begin\r\n    Log\(8\);\r\n    Y;\r\n  end;\r?$' 'begin-led line expanded'

CheckStable 'off' @('--no-collapse-blocks')
CheckStable 'on'  @('--collapse-blocks')
Finish 'expand_blocks'
