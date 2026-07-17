# Runs the YADF.Options console tests (OptionsTest.dpr) -- descriptor-table
# completeness, INI round-trip, comment preservation, help coverage.
# The exe must be built first:
#   msbuild /t:Build /p:Config=Debug /p:Platform=Win32 Test\OptionsTest.dproj
# Exit 0 = all pass, 1 = failures, 2 = exe not built (skip).
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'Win32\Debug\EXE\OptionsTest.exe'

if (-not (Test-Path $exe)) { Write-Output "options: SKIP (build OptionsTest.dproj first)"; exit 2 }

& $exe
if ($LASTEXITCODE -eq 0) { Write-Output "options: PASS"; exit 0 }
else { Write-Output "options: $LASTEXITCODE FAILED"; exit 1 }
