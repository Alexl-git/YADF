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

# Deliberately mis-indented source (so the formatter always rewrites) with a marker
# comment we inject per-case in the encoding under test.
$srcTemplate = @"
unit EncSample;
interface
// MARKER
procedure Go(X:Integer);
implementation
procedure Go(X:Integer);
begin
if X > 0 then Inc(X) else Dec(X);
end;
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

# The source is deliberately mis-indented (`if` flush-left inside begin..end); a
# formatter that no-ops (or a decline that leaves the file untouched) must not
# pass the byte-preservation checks, so every case also asserts the text really
# was reformatted (the `if` is indented by the engine).
function MustBeFormatted([byte[]]$b, [string]$label) {
  $t = [Text.Encoding]::GetEncoding(28591).GetString($b)
  if ($t -notmatch '(?m)^  if X > 0 then') { Fail "${label}: output was not reformatted (expected indented 'if X > 0 then')" }
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

function BytesContain([byte[]]$hay, [byte[]]$needle) { (CountBytes $hay $needle) -gt 0 }

$utf8Bom  = [byte[]](0xEF, 0xBB, 0xBF)
$eAcute8  = [byte[]](0xC3, 0xA9)          # U+00E9 as UTF-8
$eAcuteA  = [byte[]](0xE9)                # U+00E9 as cp1252 ANSI
$mojibake = [byte[]](0xC3, 0x83, 0xC2, 0xA9)  # the double-encode signature

try {
  # ----- 1. BOM-less UTF-8, default (preserve): bytes stay UTF-8, no BOM -----
  $f = WriteCase 'utf8_nobom.pas' ([byte[]]($eAcute8 + $eAcute8)) @()
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  MustBeFormatted $b 'utf8-nobom'
  if ($b[0] -eq 0xEF) { Fail 'utf8-nobom: BOM appeared' }
  if ((CountBytes $b $eAcute8) -ne 2) { Fail 'utf8-nobom: UTF-8 e-acute pair not preserved' }
  if (BytesContain $b $mojibake) { Fail 'utf8-nobom: double-encoded mojibake' }

  # ----- 2. BOM-less UTF-8 + explicit --encoding utf8: converts REAL text -----
  $f = WriteCase 'utf8_convert.pas' $eAcute8 @()
  & $exe --ini $ini --encoding utf8 $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  MustBeFormatted $b 'utf8-convert'
  if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { Fail 'utf8-convert: BOM missing' }
  if (BytesContain $b $mojibake) { Fail 'utf8-convert: double-encoded mojibake' }
  if ((CountBytes $b $eAcute8) -ne 1) { Fail 'utf8-convert: e-acute not preserved as single UTF-8 pair' }

  # ----- 3. Plain ANSI (cp1252 0xE9), default: stays ANSI, no BOM, no UTF-8 -----
  # A lone 0xE9 followed by ASCII is INVALID UTF-8, so detection must fall
  # back to ANSI (guards against overzealous UTF-8 sniffing).
  $f = WriteCase 'ansi.pas' $eAcuteA @()
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  MustBeFormatted $b 'ansi'
  if ($b[0] -eq 0xEF) { Fail 'ansi: BOM appeared' }
  if (-not (BytesContain $b $eAcuteA)) { Fail 'ansi: 0xE9 byte lost' }
  if (BytesContain $b $eAcute8) { Fail 'ansi: byte was re-encoded as UTF-8' }

  # ----- 4. UTF-8 WITH BOM, default (preserve): BOM + encoding survive -----
  $f = WriteCase 'utf8_bom.pas' $eAcute8 $utf8Bom
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  MustBeFormatted $b 'utf8-bom'
  if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { Fail 'utf8-bom: BOM stripped' }
  if ((CountBytes $b $eAcute8) -ne 1) { Fail 'utf8-bom: UTF-8 e-acute not preserved' }

  # ----- 5b. ANSI input + --encoding utf8: DETECT then transcode -----
  # The source must be decoded as what it IS (ANSI), not as the conversion
  # target: decoding cp1252 0xE9 as UTF-8 yields U+FFFD and destroys the char.
  $f = WriteCase 'ansi_convert.pas' $eAcuteA @()
  & $exe --ini $ini --encoding utf8 $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  MustBeFormatted $b 'ansi-convert'
  if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) { Fail 'ansi-convert: BOM missing' }
  if ((CountBytes $b $eAcute8) -ne 1) { Fail 'ansi-convert: e-acute not transcoded to UTF-8' }
  if (BytesContain $b ([byte[]](0xEF, 0xBF, 0xBD))) { Fail 'ansi-convert: U+FFFD replacement char in output' }

  # ----- 5. Pure-ASCII file, default: no BOM, still ASCII (nothing sniffed) -----
  $f = WriteCase 'ascii.pas' ([Text.Encoding]::ASCII.GetBytes('plain')) @()
  & $exe --ini $ini $f | Out-Null
  $b = [IO.File]::ReadAllBytes($f)
  MustBeFormatted $b 'ascii'
  if ($b[0] -eq 0xEF -or $b[0] -eq 0xFF -or $b[0] -eq 0xFE) { Fail 'ascii: BOM appeared' }

  # ----- 6. --stdout emits EXACTLY the bytes --o would write (WP9): same
  #       detected/explicit encoding, BOM iff the file would carry one. -----
  $stdoutCases = @(
    @{ n = 'so_utf8_nobom'; marker = [byte[]]($eAcute8 + $eAcute8); pre = [byte[]]@(); flags = @() },
    @{ n = 'so_utf8_bom';   marker = $eAcute8;                       pre = $utf8Bom;    flags = @() },
    @{ n = 'so_ansi';       marker = $eAcuteA;                       pre = [byte[]]@(); flags = @() },
    @{ n = 'so_ansi_to_u8'; marker = $eAcuteA;                       pre = [byte[]]@(); flags = @('--encoding', 'utf8') }
  )
  foreach ($c in $stdoutCases) {
    $f = WriteCase ($c.n + '.pas') $c.marker $c.pre
    $oFile = Join-Path $tmpDir ($c.n + '_o.pas')
    $sFile = Join-Path $tmpDir ($c.n + '.stdout')
    & $exe --ini $ini @($c.flags) $f --o $oFile | Out-Null
    $argl = @('--ini', $ini) + @($c.flags) + @($f, '--stdout')
    Start-Process -FilePath $exe -ArgumentList $argl -RedirectStandardOutput $sFile -NoNewWindow -Wait
    $ob = [IO.File]::ReadAllBytes($oFile)
    $sb = [IO.File]::ReadAllBytes($sFile)
    MustBeFormatted $ob ($c.n + ' (--o)')
    if ($ob.Length -ne $sb.Length -or (Compare-Object $ob $sb -SyncWindow 0)) {
      Fail "$($c.n): --stdout bytes differ from --o bytes (stdout $($sb.Length) vs o $($ob.Length))"
    }
  }
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Finish 'encoding'
