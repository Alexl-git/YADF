# Idempotence + no-decline battery over Test\Cases\idem\*.pas (BACKLOG-ZERO task 10).
# Each fixture reproduces one mechanism by which a second format changed the first
# format's output (a list decided at the source column, a trailing operator left
# alone on a line, a multi-line name list half split, a stale block-end label that
# blocked a fold, a nested case arm split at a stale column). Every fixture is run
# at nine option sets -- default, packed (the ORM3 "packed" profile), --d10, greedy (--no-break-expr), --no-reflow, --no-trim-trailing and Indent 3 / 4 / 4+TabWidth 8 --
# and must: not be declined, be a fixed point on the second run, and compile when
# the fixture itself compiles. Exit 0 = pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni
Assert-ToolOrSkip 'idempotence' $exe
$dir = Join-Path $PSScriptRoot 'Cases\idem'
$sets = [ordered]@{
  'default' = @()
  'packed'  = @('--collapse-blocks', '--pack-statements', '--no-break-loop', '--no-break-with', '--no-break-if', '--no-case-arm-on-label')
  'd10'     = @('--d10')
  # Task 11: the greedy breaker (BreakLongExpressions OFF) decided lists at the source
  # column too (idem_list_tab_indent was not a fixed point with it).
  'greedy'  = @('--no-break-expr')
  # Task 11 battery: a name list written over THREE lines and kept multi-line (no
  # reflow) was split once per line of it -- duplicate declarations, guard decline.
  'noreflow' = @('--no-reflow')
  # Task 11 battery: a block-end label appended after the trailing blanks it keeps.
  'notrim'   = @('--no-trim-trailing')
  # A comma-first list laid out by the list walker nested its items Length(', ') past
  # the item column; ReindentByDepth (run when begin placement changed the file) uses
  # one Indent step, so any Indent other than 2 moved on the next format.
  'indent3'  = @('--indent', '3')
  'indent4'  = @('--indent', '4')
  'indent4tab8' = @('--indent', '4', '--tab-width', '8', '--max-len', '100')
  # The greedy breaker continued a re-broken continuation line one Indent deeper than
  # that line (idem_greedy_continuation): the next format moved it.
  'greedy-indent4-60' = @('--no-break-expr', '--indent', '4', '--max-len', '60')
}
$files = @(Get-ChildItem $dir -Filter *.pas)
if ($files.Count -lt 5) { Fail "expected at least 5 fixtures in $dir, found $($files.Count)" }
foreach ($f in $files) {
  $work = Join-Path $env:TEMP ('idem_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $work | Out-Null
  try {
    $dcu = Join-Path $work 'dcu'; New-Item -ItemType Directory -Path $dcu | Out-Null
    $srcCompiles = Test-DccCompiles $f.FullName $f.DirectoryName $dcu
    foreach ($k in $sets.Keys) {
      $o1 = Join-Path $work ('p1_' + $k); New-Item -ItemType Directory -Path $o1 | Out-Null
      $o2 = Join-Path $work ('p2_' + $k); New-Item -ItemType Directory -Path $o2 | Out-Null
      $p1 = Join-Path $o1 $f.Name; $p2 = Join-Path $o2 $f.Name
      if (-not (Invoke-Yadf $f.FullName $ini $p1 $sets[$k])) { continue }
      if (-not (Invoke-Yadf $p1 $ini $p2 $sets[$k])) { continue }
      if (-not (SameBytes $p1 $p2)) {
        $d = @(& git -c core.autocrlf=false diff --no-index --no-color -U0 -- $p1 $p2 2>&1 | Select-Object -Skip 4 -First 8)
        Fail "not idempotent [$k]: $($f.Name)`n    $($d -join "`n    ")"
      }
      # A --d10 "resolve manually" collision flag keeps the colliding inline var, which
      # Delphi 13 rejects too (E2004, by design): no compile check for that output.
      $manual = (Get-Content -LiteralPath $p1 -Raw) -match 'resolve manually'
      if ($srcCompiles -and -not $manual -and -not (Test-DccCompiles $p1 $f.DirectoryName $dcu)) { Fail "output does not compile [$k]: $($f.Name)" }
    }
    if (-not $srcCompiles) { Fail "fixture does not compile standalone: $($f.Name)" }
  }
  finally { [IO.Directory]::Delete($work, $true) }
}
Finish 'idempotence'
