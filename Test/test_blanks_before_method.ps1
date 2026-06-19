# BlanksBeforeMethod must apply to TOP-LEVEL routine declarations only, never to
# method declarations inside a class/record/interface type block. Exit 0 = pass.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$case = Join-Path $PSScriptRoot 'Cases\blanks_before_method.pas'
$tmp = Join-Path $env:TEMP 'bbm_test'
New-Item -ItemType Directory $tmp -Force | Out-Null
$ini = Join-Path $tmp 'bbm2.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`nBlanksBeforeMethod=2", (New-Object Text.ASCIIEncoding))
$out = Join-Path $tmp 'out.pas'
& $exe $case --ini $ini --o $out | Out-Null
$o = Get-Content $out -Raw
$fail = 0
function MustMatch([string]$rx,[string]$label){ if ($o -notmatch $rx){ $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" } }
function MustNotMatch([string]$rx,[string]$label){ if ($o -match $rx){ $script:fail++; Write-Output "FAIL [$label]: should NOT match /$rx/" } }

# In-class method declarations stay adjacent (no blank-line floor between members).
MustMatch    '(?m)^[ \t]+procedure DoA;\r?\n[ \t]+procedure DoB;' 'in-class methods adjacent (no injected blanks)'
# No blank line directly before an INDENTED method declaration.
MustNotMatch '(?m)\r?\n[ \t]*\r?\n[ \t]+procedure (DoA|DoB);'     'no blank before in-class method decl'
# Top-level implementation methods DO get the blank-line floor (2 blanks).
MustMatch    '(?m)end;\r?\n\r?\n\r?\nprocedure TFoo\.DoB;'        'top-level method gets BlanksBeforeMethod floor'

if ($fail -eq 0) { Write-Output "blanks_before_method: PASS"; exit 0 }
else { Write-Output "blanks_before_method: $fail FAILED"; exit 1 }
