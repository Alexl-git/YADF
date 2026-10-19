# Compile-the-output gate.
#
# WHY: byte-goldens catch SHAPE changes, and --check catches round-trip
# losses, but neither proves the formatted output still COMPILES. The E2008
# bug class (SplitMultiVarDecls splitting an anonymous structured type) shipped
# precisely because nothing compiled the output. This gate runs the REAL
# dcc64 over every corpus fixture's formatted output.
#
# Self-classifying: a fixture whose ORIGINAL does not compile standalone
# (fragments, deliberate edge-case snippets, unit-name/file-name mismatches)
# is skipped -- not a formatter regression. A fixture whose original compiles
# but whose FORMATTED output does not is a hard FAIL.
#
# Exit 0 = pass, 1 = failures (incl. dcc64 missing), 2 = skip (YADF.exe missing).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe   = Get-YadfExe
$ini   = Get-RepoIni
$dcc   = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'

Assert-ToolOrSkip 'compile_output' $exe
# A missing compiler is a FAILURE, not a skip: a silent skip lets the gate rot.
if (-not (Test-Path $dcc)) { Write-Output "compile_output: FAIL (dcc64 missing at $dcc)"; exit 1 }

$tmpDir = Join-Path $env:TEMP ("yadf_compile_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$dcuDir = Join-Path $tmpDir 'dcu'
New-Item -ItemType Directory -Path $dcuDir | Out-Null

# Same namespace prefixes msbuild passes for a plain VCL project, so fixtures
# may use either plain (SysUtils) or dotted (System.SysUtils) unit names.
$ns = 'System;System.Win;Winapi;Vcl;Data;Soap;Xml'

function CompilesOK([string]$pasFile, [string]$incDir) {
  # -I<fixture dir>: {$I ...} include files live next to the ORIGINAL fixture,
  # and the formatted copy compiles from a temp dir.
  return (Test-DccCompiles $pasFile $incDir $dcuDir)
}

$files = Get-ChildItem (Join-Path $PSScriptRoot 'Cases'), (Join-Path $PSScriptRoot 'Snippets') -Filter *.pas -Recurse
$compiled = 0
$skipped  = 0
$changed  = 0   # outputs that differ from their input (a copy-only stub changes none)

try {
  foreach ($f in $files) {
    if (-not (Test-UnitNameMatchesFile $f.FullName)) { continue }   # E1038 mismatch = FAIL, not skip
    if (-not (CompilesOK $f.FullName $f.DirectoryName)) { $skipped++; continue }   # fragment / edge snippet
    $out = Join-Path $tmpDir $f.Name    # keep the file name: unit name must match
    if (-not (Invoke-Yadf $f.FullName $ini $out)) { continue }   # exit!=0 / decline / no output = FAIL
    if (-not (SameBytes $f.FullName $out)) { $changed++ }
    if (CompilesOK $out $f.DirectoryName) { $compiled++ }
    else { $fail++; Write-Output "FAIL [formatted output does not compile]: $($f.Name)" }
    Remove-Item $out -Force -ErrorAction SilentlyContinue
  }
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Floor: if most fixtures silently stop compiling standalone (e.g. a broken
# toolchain), the gate would 'pass' vacuously. Current corpus: 58.
$floor = 50
if ($compiled -lt $floor) { $fail++; Write-Output "FAIL [floor]: only $compiled fixtures compiled standalone (< $floor)" }

Write-Output "compile_output: $changed output(s) differ from input"
# Positive control: the gates above stay green for a copy-only stub formatter. A real run changes
# 59 of ~100 fixtures; require a floor well under that so a no-op formatter FAILS.
$changedFloor = 45
if ($changed -lt $changedFloor) { Fail "only $changed outputs differ from input (< $changedFloor): formatter looks like a no-op" }

if ($fail -eq 0) {
  Write-Output "compile_output: PASS ($compiled compiled, $skipped skipped as non-standalone)"
  exit 0
}
else { Write-Output "compile_output: $fail FAILURE(S) ($compiled ok, $skipped skipped)"; exit 1 }
