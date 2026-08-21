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

  # ----- mode flags still pass through ParseFlags -----
  $fmt = Join-Path $tmpDir 'formatted.pas'
  & $exe --ini $ini $src --o $fmt | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "format setup: exit $LASTEXITCODE" }
  $chk = & $exe --ini $ini --check $fmt 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "--check exit: expected 0, got $LASTEXITCODE" }
  MustMatch $chk 'PASS' '--check still works'
}
finally {
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Finish 'cli_errors'
