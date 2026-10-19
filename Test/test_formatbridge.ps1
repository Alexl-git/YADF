# Runs the YADF.FormatBridge console tests (FormatBridgeTest.dpr) -- UTF-8 round trip, decline-returns-original,
# selection->line mapping, caret remap (the IOTACodeFormatter adapter seams).
# The exe must be built first:
#   msbuild /t:Build /p:Config=Debug /p:Platform=Win64 Test\FormatBridgeTest.dproj
# Exit 0 = all pass, 1 = failures, 2 = exe not built (skip).
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'Win64\Debug\EXE\FormatBridgeTest.exe'

if (-not (Test-Path $exe)) { Write-Output "formatbridge: SKIP (build FormatBridgeTest.dproj first)"; exit 2 }

& $exe
if ($LASTEXITCODE -eq 0) { Write-Output "formatbridge: PASS"; exit 0 }
else { Write-Output "formatbridge: $LASTEXITCODE FAILED"; exit 1 }
