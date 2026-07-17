# BlanksBeforeMethod must apply to TOP-LEVEL routine declarations only, never to
# method declarations inside a class/record/interface type block. Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'blanks_before_method' $exe
$case = Join-Path $PSScriptRoot 'Cases\blanks_before_method.pas'
$tmp = Join-Path $env:TEMP 'bbm_test'
New-Item -ItemType Directory $tmp -Force | Out-Null
$ini = Join-Path $tmp 'bbm2.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`nBlanksBeforeMethod=2", (New-Object Text.ASCIIEncoding))
$out = Join-Path $tmp 'out.pas'
& $exe $case --ini $ini --o $out | Out-Null
$o = Get-Content $out -Raw

# In-class method declarations stay adjacent (no blank-line floor between members).
MustMatch    $o '(?m)^[ \t]+procedure DoA;\r?\n[ \t]+procedure DoB;' 'in-class methods adjacent (no injected blanks)'
# No blank line directly before an INDENTED method declaration.
MustNotMatch $o '(?m)\r?\n[ \t]*\r?\n[ \t]+procedure (DoA|DoB);'     'no blank before in-class method decl'
# Top-level implementation methods DO get the blank-line floor (2 blanks).
MustMatch    $o '(?m)end;\r?\n\r?\n\r?\nprocedure TFoo\.DoB;'        'top-level method gets BlanksBeforeMethod floor'

Finish 'blanks_before_method'
