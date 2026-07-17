# File-encoding preservation tests. A BOM-less file that is valid UTF-8 with
# multi-byte sequences must be READ as UTF-8 (not the historical blind-ANSI
# fallback, which mojibakes on rewrite) and, under the default Encoding=ANSI
# ("preserve") setting, written back byte-compatible without a BOM. A file
# WITH a BOM keeps its BOM + encoding under the default. An explicit
# --encoding utf8/utf16 remains a conversion request -- but must convert the
# real text, not the mojibake (the old double-encode turned C3 A9 into
# C3 83 C2 A9). Exit 0 = all pass, 1 = any fail, 2 = skip (exe not built).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'encoding' $exe

$tmpDir = Join-Path $env:TEMP ("yadf_encoding_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null

# Deliberately ugly source (so the formatter always rewrites) with a marker
# comment we inject per-case in the encoding under test.
$srcTemplate = @"
unit EncSample;
interface
// MARKER
procedure Go(X:Integer);
implementation
procedure Go(X:Integer);begin if X>0 then Inc(X) else Dec(X); end;
end.
"@

function WriteCase([string]$name, [byte[]]$markerBytes, [byte[]]$preamble) {
  $path = Join-Path $tmpDir $name
  $ascii = [Text.Encoding]::ASCII
  $parts = $srcTemplate -split 'MARKER'
  $bytes = $preamble + $ascii.GetBytes($parts[0]) + $markerBytes + $ascii.GetBytes($parts[1])
  [IO.File]::WriteAllBytes($path, $bytes)
  return $path
}

function BytesContain([byte[]]$hay, [byte[]]$needle) {
  for ($i = 0; $i -le $hay.Length - $needle.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $needle.Length; $j++) {
      if ($hay[$i + $j] -ne $needle[$j]) { $ok = $false; break }
    }
    if ($ok) { return $true }
  }
  return $false
}

function CountBytes([byte[]]$hay, [byte[]]$needle) {
  $n = 0
  for ($i = 0; $i -le $hay.Length - $needle.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $needle.Length; $j++) {
      if ($hay[$i + $j] -ne $needle[$j]) { $ok = $false; break }
    }
    if ($ok) { $n++ }
  }
  return $n
}

$utf8Bom  = [byte[]](0xEF, 0xBB, 0xBF)
$eAcute8  = [byte[]](0xC3, 0xA9)          # U+00E9 as UTF-8
$eAcuteA  = [byte[]](0xE9)                # U+00E9 as cp1252 ANSI
$mojibake = [byte[]](0xC3, 0x83, 0xC2, 0xA9)  # the double-encode signature

try {
  # ----- 1. BOM-less UTF-8, default (preserve): bytes stay UTF-8, no BOM -----
  $f = WriteCase 'utf8_nobom.pas' ([byte[]]($eAcute8 + $eAcute8)) @()
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  if ($b[0] -eq 0xEF) { Fail 'utf8-nobom: BOM appeared' }
  if ((CountBytes $b $eAcute8) -ne 2) { Fail 'utf8-nobom: UTF-8 e-acute pair not preserved' }
  if (BytesContain $b $mojibake) { Fail 'utf8-nobom: double-encoded mojibake' }

  # ----- 2. BOM-less UTF-8 + explicit --encoding utf8: converts REAL text -----
  $f = WriteCase 'utf8_convert.pas' $eAcute8 @()
  & $exe --ini $ini --encoding utf8 $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { Fail 'utf8-convert: BOM missing' }
  if (BytesContain $b $mojibake) { Fail 'utf8-convert: double-encoded mojibake' }
  if ((CountBytes $b $eAcute8) -ne 1) { Fail 'utf8-convert: e-acute not preserved as single UTF-8 pair' }

  # ----- 3. Plain ANSI (cp1252 0xE9), default: stays ANSI, no BOM, no UTF-8 -----
  # A lone 0xE9 followed by ASCII is INVALID UTF-8, so detection must fall
  # back to ANSI (guards against overzealous UTF-8 sniffing).
  $f = WriteCase 'ansi.pas' $eAcuteA @()
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  if ($b[0] -eq 0xEF) { Fail 'ansi: BOM appeared' }
  if (-not (BytesContain $b $eAcuteA)) { Fail 'ansi: 0xE9 byte lost' }
  if (BytesContain $b $eAcute8) { Fail 'ansi: byte was re-encoded as UTF-8' }

  # ----- 4. UTF-8 WITH BOM, default (preserve): BOM + encoding survive -----
  $f = WriteCase 'utf8_bom.pas' $eAcute8 $utf8Bom
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { Fail 'utf8-bom: BOM stripped' }
  if ((CountBytes $b $eAcute8) -ne 1) { Fail 'utf8-bom: UTF-8 e-acute not preserved' }

  # ----- 5. Pure-ASCII file, default: no BOM, still ASCII (nothing sniffed) -----
  $f = WriteCase 'ascii.pas' ([Text.Encoding]::ASCII.GetBytes('plain')) @()
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  if ($b[0] -eq 0xEF -or $b[0] -eq 0xFF -or $b[0] -eq 0xFE) { Fail 'ascii: BOM appeared' }
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Finish 'encoding'
