$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win32\Release\EXE\YADFSetup.exe'
if (-not (Test-Path $exe)) {
  $exe = Join-Path $PSScriptRoot '..\Win32\Debug\EXE\YADFSetup.exe'
}
if (-not (Test-Path $exe)) { Write-Error "YADFSetup.exe not found"; exit 1 }

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
