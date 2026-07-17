# Runs the YADF.Guard console tests (GuardTest.dpr) -- the post-format
# content-preservation safety net. The exe must be built first:
#   msbuild /t:Build /p:Config=Debug /p:Platform=Win32 Test\GuardTest.dproj
# Exit 0 = all pass, 1 = failures, 2 = exe not built (skip).
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'Win32\Debug\EXE\GuardTest.exe'

if (-not (Test-Path $exe)) { Write-Output "guard: SKIP (build GuardTest.dproj first)"; exit 2 }

& $exe
if ($LASTEXITCODE -eq 0) { Write-Output "guard: PASS"; exit 0 }
else { Write-Output "guard: $LASTEXITCODE FAILED"; exit 1 }
