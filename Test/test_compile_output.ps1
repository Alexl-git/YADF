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
# Exit 0 = pass, 1 = failures, 2 = skip (YADF.exe or dcc64 missing).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe   = Get-YadfExe
$ini   = Get-RepoIni
$dcc   = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'

Assert-ToolOrSkip 'compile_output' $exe
Assert-ToolOrSkip 'compile_output' $dcc

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
  & $dcc -Q "-NS$ns" "-N0$dcuDir" "-E$dcuDir" "-I$incDir" $pasFile *> $null
  return ($LASTEXITCODE -eq 0)
}

$files = Get-ChildItem (Join-Path $PSScriptRoot 'Cases'), (Join-Path $PSScriptRoot 'Snippets') -Filter *.pas -Recurse
$compiled = 0
$skipped  = 0

try {
  foreach ($f in $files) {
    if (-not (CompilesOK $f.FullName $f.DirectoryName)) { $skipped++; continue }   # fragment / edge snippet
    $out = Join-Path $tmpDir $f.Name    # keep the file name: unit name must match
    & $exe $f.FullName --ini $ini --o $out | Out-Null
    if (-not (Test-Path $out)) { $fail++; Write-Output "FAIL [no output]: $($f.Name)"; continue }
    if (CompilesOK $out $f.DirectoryName) { $compiled++ }
    else { $fail++; Write-Output "FAIL [formatted output does not compile]: $($f.Name)" }
    Remove-Item $out -Force -ErrorAction SilentlyContinue
  }
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fail -eq 0) {
  Write-Output "compile_output: PASS ($compiled compiled, $skipped skipped as non-standalone)"
  exit 0
}
else { Write-Output "compile_output: $fail FAILURE(S) ($compiled ok, $skipped skipped)"; exit 1 }
