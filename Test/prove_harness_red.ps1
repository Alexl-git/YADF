# Proves the harness CAN fail (review 2026-10-14 #9): builds the copy-only
# Test\Stub\YadfStub.dpr into a temp dir and runs the suites that guard
# against a no-op formatter or a broken toolchain, each of which MUST go red:
#   encoding        no-op exe (every preserve case asserts a real reformat)
#   encoding        stub with STUB_ANSI_STDOUT=1 (non-ANSI literals on --stdout, #5)
#   compile_output  no-op exe (changed-output floor)
#   compile_output  dcc64 missing (FAIL, not skip)
#   compile_output  dcc64 that compiles nothing (compiled-fixture floor)
#   golden_format   -Capture over a tampered golden (diff shown, nothing written without -Accept)
#   option_audit    an INI key no suite exercises
# Not a test_*.ps1 (run_tests.ps1 does not run it): run it after editing the harness.
# Exit 0 = every case went red as required, 1 = a case stayed green.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$work = Join-Path $env:TEMP ('yadf_red_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null

function Expect-Red([string]$label, [string]$script, [string[]]$scriptArgs = @(), [hashtable]$envs = @{}) {
  foreach ($k in $envs.Keys) { Set-Item "Env:$k" $envs[$k] }
  try { pwsh -NoProfile -File (Join-Path $PSScriptRoot $script) @scriptArgs *> $null; $code = $LASTEXITCODE }
  finally { foreach ($k in $envs.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }
  if ($code -eq 1) { Write-Output "red as required: $label" }
  else { Fail "$label stayed exit $code (expected 1)" }
}

try {
  & (Get-Dcc64) -Q "-E$work" "-N0$work" (Join-Path $PSScriptRoot 'Stub\YadfStub.dpr') *> $null
  $stub = Join-Path $work 'YadfStub.exe'
  if (-not (Test-Path $stub)) { Fail 'stub did not build'; Finish 'prove_harness_red' }

  Expect-Red 'encoding / no-op exe' 'test_encoding.ps1' @() @{ YADF_TEST_EXE = $stub }
  Expect-Red 'encoding / ANSI stdout' 'test_encoding.ps1' @() @{ YADF_TEST_EXE = $stub; STUB_ANSI_STDOUT = '1' }
  Expect-Red 'compile_output / no-op exe' 'test_compile_output.ps1' @() @{ YADF_TEST_EXE = $stub }
  Expect-Red 'compile_output / dcc64 missing' 'test_compile_output.ps1' @() @{ YADF_TEST_DCC64 = (Join-Path $work 'no-dcc64.exe') }
  Expect-Red 'compile_output / dcc64 compiles nothing' 'test_compile_output.ps1' @() @{ YADF_TEST_DCC64 = (Join-Path $env:windir 'System32\where.exe') }

  $ini = Join-Path $work 'audit.ini'
  [IO.File]::WriteAllText($ini, [IO.File]::ReadAllText((Get-RepoIni)) + "`r`nZzUntestedOption=true`r`n")
  Expect-Red 'option_audit / untested key' 'test_option_audit.ps1' @('-IniPath', $ini)

  # Tamper one golden; -Capture must show the diff, exit 1 and leave it tampered.
  $gold = Get-ChildItem (Join-Path $PSScriptRoot 'Golden') -Filter *.golden | Sort-Object Name | Select-Object -First 1
  $orig = [IO.File]::ReadAllBytes($gold.FullName)
  try {
    [IO.File]::WriteAllBytes($gold.FullName, $orig + [Text.Encoding]::ASCII.GetBytes("// tampered`r`n"))
    Expect-Red 'golden_format -Capture / changed golden' 'test_golden_format.ps1' @('-Capture')
    if (-not ([IO.File]::ReadAllText($gold.FullName)).Contains('// tampered')) { Fail 'golden -Capture re-blessed a changed golden without -Accept' }
  }
  finally { [IO.File]::WriteAllBytes($gold.FullName, $orig) }
}
finally { [IO.Directory]::Delete($work, $true) }
Finish 'prove_harness_red'
