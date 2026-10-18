# CLI error-handling tests. Unknown --flags must be rejected with a clear
# "unknown option" error and a nonzero exit code -- NOT silently treated as
# file specs (the old behavior turned a typo like --max-length into a
# confusing "no .pas files matched" / stray-file run). The positional mode
# flags (--check, --check-dir, --batch, --debug-tree) are parsed after
# ParseFlags and must keep working. Exit 0 = all pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'cli_errors' $exe

# Work on a temp copy only -- never format repo fixtures in place.
$tmpDir = Join-Path $env:TEMP ("yadf_cli_errors_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$src = Join-Path $tmpDir 'input.pas'
Copy-Item (Join-Path $PSScriptRoot 'Cases\case_labels.pas') $src

try {
  # ----- unknown flag: clear error, nonzero exit, file untouched -----
  $before = (Get-FileHash $src).Hash
  $out = & $exe --ini $ini --no-such-flag $src 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { Fail "unknown-flag exit: expected nonzero, got 0" }
  MustMatch $out 'unknown option --no-such-flag' 'unknown-flag message'
  if ((Get-FileHash $src).Hash -ne $before) { Fail "unknown-flag: input file was modified" }

  # ----- unknown --encoding value: used to be accepted silently (file then
  #       written in the INI's encoding, exit 0). Review 2026-10-14. -----
  $out = & $exe --ini $ini --encoding bogus $src 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { Fail "--encoding bogus exit: expected nonzero, got 0" }
  MustMatch $out '(?i)encoding' '--encoding bogus message names the option'
  if ((Get-FileHash $src).Hash -ne $before) { Fail "--encoding bogus: input file was modified" }

  # ----- out-of-range integer: clamped, with a warning, never silently -----
  $out = & $exe --ini $ini --indent -3 --stdout $src 2>&1 | Out-String
  MustMatch $out '(?i)warning.*Indent' '--indent -3 warns that it was clamped'

  # ----- typo'd value flag: same treatment, value arg not eaten as a file -----
  $out = & $exe --ini $ini --max-length 100 $src 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { Fail "typo-flag exit: expected nonzero, got 0" }
  MustMatch $out 'unknown option --max-length' 'typo-flag message'

  # ----- symmetric bool flags: the positive form must override an INI false -----
  # (the --no-* forms always existed; the positive twins were missing, so an
  # INI false could not be re-enabled per run)
  $ini2 = Join-Path $tmpDir 'flags.ini'
  [IO.File]::WriteAllText($ini2, "[Format]`r`nUpperHexNumbers=false`r`n", (New-Object Text.ASCIIEncoding))
  $pas = Join-Path $tmpDir 'hex.pas'
  [IO.File]::WriteAllText($pas, "unit hex;`r`ninterface`r`nconst`r`n  K = `$00ab;`r`nimplementation`r`nend.`r`n", (New-Object Text.ASCIIEncoding))
  $ho = Join-Path $tmpDir 'hex_out.pas'
  & $exe --ini $ini2 $pas --o $ho | Out-Null
  MustMatch (Get-Content $ho -Raw) '\$00ab' 'ini UpperHexNumbers=false honored (baseline)'
  & $exe --ini $ini2 $pas --upper-hex --o $ho | Out-Null
  MustMatch (Get-Content $ho -Raw) '\$00AB' '--upper-hex overrides INI false'

  # ----- --help must describe the INI it was actually handed -----
  # It used to resolve DefaultIniPath unconditionally (the help branch ran
  # BEFORE ExtractIniPath), so `--ini X --help` printed the %APPDATA% profile
  # values -- i.e. it could describe a completely different configuration than
  # `--ini X <file>` would actually use. That misled a reader into filing a
  # false bug report.
  $iniHelp = Join-Path $tmpDir 'help.ini'
  [IO.File]::WriteAllText($iniHelp, "[Format]`r`nMaxLen=77`r`n", (New-Object Text.ASCIIEncoding))
  $help = & $exe --ini $iniHelp --help 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "--ini <file> --help exit: expected 0, got $LASTEXITCODE" }
  MustMatch $help '(?m)^\s+--max-len N.*\[77\]\s*$' '--help reports MaxLen from the explicit --ini'

  # ...and a NEW --ini path is materialised by --help too (same first-run
  # template contract as a normal run; the help text itself promises it).
  $iniNew = Join-Path $tmpDir 'made_by_help.ini'
  & $exe --ini $iniNew --help | Out-Null
  if (-not (Test-Path $iniNew)) { Fail '--ini <new path> --help did not create the INI template' }

  # ----- --help: live [x=on/off] values, no static "(default)" text; INI-only keys listed -----
  $help = & $exe --ini $ini --help 2>&1 | Out-String
  if ($help -match '\(default') { Fail '--help still contains a literal "(default" string' }
  MustMatch $help '\[loop=(on|off)\]' '--help shows the live break-loop value'
  MustMatch $help '\[collapse=(on|off)\]' '--help shows the live collapse value'
  MustMatch $help 'INI-only' '--help lists the INI-only keys'
  MustMatch $help 'AlignTypeColon=(on|off)' '--help shows a live INI-only value'

  # ----- mode flags still pass through ParseFlags -----
  $fmt = Join-Path $tmpDir 'formatted.pas'
  & $exe --ini $ini $src --o $fmt | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "format setup: exit $LASTEXITCODE" }
  $chk = & $exe --ini $ini --check $fmt 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "--check exit: expected 0, got $LASTEXITCODE" }
  MustMatch $chk 'PASS' '--check still works'

  # ----- WP7: --of with two inputs of the same basename: refused up front,
  #       exit 1, nothing written (the second used to silently overwrite the first) -----
  $da = Join-Path $tmpDir 'da'; $db = Join-Path $tmpDir 'db'; $dout = Join-Path $tmpDir 'dout'
  New-Item -ItemType Directory $da, $db | Out-Null
  Copy-Item $src (Join-Path $da 'same.pas'); Copy-Item $src (Join-Path $db 'same.pas')
  $ha = (Get-FileHash (Join-Path $da 'same.pas')).Hash
  $out = & $exe --ini $ini (Join-Path $da 'same.pas') (Join-Path $db 'same.pas') --of $dout 2>&1 | Out-String
  if ($LASTEXITCODE -ne 1) { Fail "--of same basename: expected exit 1, got $LASTEXITCODE" }
  MustMatch $out '(?i)share the file name' '--of same basename message'
  if (Test-Path (Join-Path $dout 'same.pas')) { Fail '--of same basename: a file was written despite the refusal' }
  if ((Get-FileHash (Join-Path $da 'same.pas')).Hash -ne $ha) { Fail '--of same basename: an input was modified' }

  # ----- WP7: the same file named twice (spec + wildcard overlap) is processed once -----
  $dd = Join-Path $tmpDir 'dd'; New-Item -ItemType Directory $dd | Out-Null
  $fd = Join-Path $dd 'dup.pas'; Copy-Item $src $fd
  $out = & $exe --ini $ini $fd (Join-Path $dd '*.pas') $fd.ToUpper() 2>&1 | Out-String
  $n = ([regex]::Matches($out, '(?im)^(wrote|unchanged) ')).Count
  if ($n -ne 1) { Fail "duplicate input: expected 1 processed line, got $n" }

  # ----- WP8: a guard decline exits 3 (declined, file unchanged), in every mode.
  #       A NUL byte is a permanent, deterministic decline. -----
  $dn = Join-Path $tmpDir 'nulcase'; New-Item -ItemType Directory $dn | Out-Null
  $nulFile = Join-Path $dn 'declining.pas'
  $nulBytes = [Text.Encoding]::ASCII.GetBytes("unit U;`r`ninterface`r`nimplementation`r`nprocedure P;`r`nbegin`r`n  X := 1; // a") + [byte[]](0) + [Text.Encoding]::ASCII.GetBytes("b`r`nend;`r`nend.`r`n")
  [IO.File]::WriteAllBytes($nulFile, $nulBytes)
  $hn = (Get-FileHash $nulFile).Hash
  $good = Join-Path $dn 'good.pas'; Copy-Item $src $good
  $nulOut = Join-Path $tmpDir 'dec_out.pas'
  & $exe --ini $ini $nulFile | Out-Null
  if ($LASTEXITCODE -ne 3) { Fail "decline in place: expected exit 3, got $LASTEXITCODE" }
  if ((Get-FileHash $nulFile).Hash -ne $hn) { Fail 'decline in place: file was modified' }
  & $exe --ini $ini $nulFile --o $nulOut | Out-Null
  if ($LASTEXITCODE -ne 3) { Fail "decline --o: expected exit 3, got $LASTEXITCODE" }
  & $exe --ini $ini $nulFile --of (Join-Path $tmpDir 'dec_of') | Out-Null
  if ($LASTEXITCODE -ne 3) { Fail "decline --of: expected exit 3, got $LASTEXITCODE" }
  & $exe --ini $ini --batch $dn (Join-Path $tmpDir 'dec_batch') | Out-Null
  if ($LASTEXITCODE -ne 3) { Fail "decline --batch: expected exit 3, got $LASTEXITCODE" }
  & $exe --ini $ini $nulFile --stdout 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 3) { Fail "decline --stdout: expected exit 3, got $LASTEXITCODE" }
  # a decline next to a clean file is still 3; a real failure outranks it
  & $exe --ini $ini $nulFile $good | Out-Null
  if ($LASTEXITCODE -ne 3) { Fail "decline + ok: expected exit 3, got $LASTEXITCODE" }
  & $exe --ini $ini $nulFile (Join-Path $dn 'missing.pas') | Out-Null
  if ($LASTEXITCODE -eq 3 -or $LASTEXITCODE -eq 0) { Fail "decline + failure: expected the failure code, got $LASTEXITCODE" }
  & $exe --ini $ini $good | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "clean format: expected exit 0, got $LASTEXITCODE" }
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Finish 'cli_errors'
