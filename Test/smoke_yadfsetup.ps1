$ErrorActionPreference = 'Stop'
# YADFSetup.exe is Win64-ONLY -- build_all.bat builds it for Win64 alone, and the
# release matrix ships only the Win64 binary. This script used to look under
# Win32\, where nothing has been built since the Win64 switch; it found whatever
# ancient relic happened to still be sitting there and smoke-tested THAT. The
# same Win32-fallback mistake let `drag-lint format` run a 2026-06-02 YADF.exe
# and corrupt source (docs/INBOX-yadf-splits-inline-multi-var-declarations.md).
# Release first, Debug second, and NO fallback to a platform we do not build.
$exe = Join-Path $PSScriptRoot '..\Win64\Release\EXE\YADFSetup.exe'
if (-not (Test-Path $exe)) {
  $exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADFSetup.exe'
}
if (-not (Test-Path $exe)) {
  Write-Error "YADFSetup.exe not found under Win64\Release or Win64\Debug -- run build_all.bat"; exit 1
}

# ensure the sample is reachable next to the exe
$sampleSrc = Join-Path $PSScriptRoot '..\Demo\Sample.pas'
$sampleDst = Join-Path (Split-Path $exe) 'Sample.pas'
if (Test-Path $sampleSrc) { Copy-Item $sampleSrc $sampleDst -Force }

$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 3
if ($p.HasExited) { Write-Error "YADFSetup exited immediately (code $($p.ExitCode))"; exit 1 }
$p.Refresh()
if (-not $p.MainWindowHandle -or $p.MainWindowHandle -eq 0) {
  Stop-Process -Id $p.Id -Force
  Write-Error "YADFSetup has no main window"; exit 1
}
Stop-Process -Id $p.Id -Force
Write-Output "SMOKE OK: YADFSetup launched, window present, survived 3s"
