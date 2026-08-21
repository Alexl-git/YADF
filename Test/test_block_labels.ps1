# Block-end label lifecycle (`end; // procedure`).
#
# The marker is decided by a POST-PASS over the FINAL line-broken text, not
# during the structural token walk. That distinction is the whole point: the
# walk measures a block BEFORE BreakLongLines/reflow/collapse have changed its
# line count, so it could decide "too short" on pass 1 and "long enough" on
# pass 2 -- formatting twice yielded different files. These cases lock the
# post-pass semantics down. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'block_labels' $exe

# Formats $text twice and returns both passes, so every case also asserts the
# fixed point that motivated the design.
function Fmt([string]$text, [string[]]$flags) {
  $g   = [guid]::NewGuid().ToString('N')
  $src = Join-Path $env:TEMP "lbl_${g}_in.pas"
  $o1  = Join-Path $env:TEMP "lbl_${g}_1.pas"
  $o2  = Join-Path $env:TEMP "lbl_${g}_2.pas"
  Set-Content -Path $src -Value $text -Encoding ascii
  & $exe --ini $ini $src $flags --o $o1 | Out-Null
  & $exe --ini $ini $o1  $flags --o $o2 | Out-Null
  $r = [pscustomobject]@{ Pass1 = (Get-Content $o1 -Raw); Pass2 = (Get-Content $o2 -Raw) }
  Remove-Item $src, $o1, $o2 -Force -ErrorAction SilentlyContinue
  return $r
}

# A procedure whose body is THREE physical lines as written, but explodes to
# ~25 once the long sum is broken one component per line.
$terms = (11..33 | ForEach-Object { "F($_)" }) -join ' + '
$short = @(
  'unit lbl;'
  'interface'
  'implementation'
  'function F(X: Integer): Integer;'
  'begin'
  '  Result := X * 2;'
  'end;'
  'procedure P;'
  'var'
  '  Z: Integer;'
  'begin'
  "  Z := $terms;"
  'end;'
  'end.'
) -join "`r`n"

# ----- The regression: the label must appear on pass 1, not pass 2 -----
# Pre-break the body spans 2 lines (under the threshold); post-break it spans
# far more. Measured in the walk, that flipped between runs.
$grown = Fmt $short @('--break-expr', '--label-min-lines', '10', '--max-len', '80')
MustMatch $grown.Pass1 '(?m)^end; // procedure\s*$' 'post-break block is labelled on pass 1'
if ($grown.Pass1 -ne $grown.Pass2) { Fail 'idempotent: label decided on the final line shape' }

# Control: the SAME source with the greedy breaker stays short, so it must NOT
# be labelled. Proves the marker follows the final shape, not the source shape.
$flat = Fmt $short @('--no-break-expr', '--label-min-lines', '10', '--max-len', '80')
MustNotMatch $flat.Pass1 '(?m)// procedure\s*$' 'short final shape is not labelled'
if ($flat.Pass1 -ne $flat.Pass2) { Fail 'idempotent: greedy control' }

# ----- The option gates the whole pass -----
$off = Fmt $short @('--break-expr', '--no-label-blocks', '--label-min-lines', '10', '--max-len', '80')
MustNotMatch $off.Pass1 '(?m)//\s*procedure\s*$' 'no-label-blocks emits no marker'
if ($off.Pass1 -ne $off.Pass2) { Fail 'idempotent: labels off' }

# ----- An existing trailing comment on the `end` line is never doubled -----
$noted = $short -replace [regex]::Escape('end;' + "`r`n" + 'end.'), ("end; // keep this note`r`nend.")
$kept  = Fmt $noted @('--break-expr', '--label-min-lines', '10', '--max-len', '80')
MustMatch    $kept.Pass1 '(?m)^end; // keep this note\s*$' 'author comment on the end line survives'
MustNotMatch $kept.Pass1 'keep this note // procedure'     'author comment is not doubled with a label'
if ($kept.Pass1 -ne $kept.Pass2) { Fail 'idempotent: pre-commented end line' }

# ----- Rules 2 and 3: remove ONLY what this pass would itself have written ----
# A short block carrying a marker. $tail is whatever trails its closing `end`.
function ShortProc([string]$tail) {
  @(
    'unit lbl;'
    'interface'
    'implementation'
    'procedure P;'
    'begin'
    '  A;'
    "end;$tail"
    'end.'
  ) -join "`r`n"
}

# Same, but the marked `end` closes a `while` body -- FindBlockLabel says
# `while` for it, so `// procedure` there is somebody's note, not our marker.
function ShortLoop([string]$tail) {
  @(
    'unit lbl;'
    'interface'
    'implementation'
    'procedure P;'
    'begin'
    '  while A do'
    '  begin'
    '    B;'
    "  end;$tail"
    'end;'
    'end.'
  ) -join "`r`n"
}

# REMOVE: below LabelMinLines and an exact match for THIS block.
$gone = Fmt (ShortProc ' // procedure') @()
MustMatch    $gone.Pass1 '(?m)^end;\s*$'          'stale exact-match marker is removed'
MustNotMatch $gone.Pass1 '// procedure'           'removed marker leaves no trace'
if ($gone.Pass1 -ne $gone.Pass2) { Fail 'idempotent: removal' }

$loopGone = Fmt (ShortLoop ' // while') @()
MustNotMatch $loopGone.Pass1 '// while'           'stale while marker is removed'
if ($loopGone.Pass1 -ne $loopGone.Pass2) { Fail 'idempotent: removal on a while block' }

# LEAVE ALONE -- one case each, exactly as the design table lists them.
$keep = @(
  @{ Src = (ShortProc ' // procedure -- see ticket 42'); Rx = '// procedure -- see ticket 42'; Why = 'trailing prose after the keyword' },
  @{ Src = (ShortProc ' //procedure')                  ; Rx = '//procedure'                  ; Why = 'no space after //'              },
  @{ Src = (ShortProc ' { procedure }')                ; Rx = '\{ procedure \}'               ; Why = 'brace comment, not //'          },
  @{ Src = (ShortProc ' // TODO -oYADF : look here')   ; Rx = '// TODO -oYADF : look here'   ; Why = 'not a label at all'             },
  @{ Src = (ShortLoop ' // procedure')                 ; Rx = '// procedure'                 ; Why = 'keyword names another construct' }
)
foreach ($k in $keep) {
  $r = Fmt $k.Src @()
  MustMatch $r.Pass1 $k.Rx ("kept: " + $k.Why)
  if ($r.Pass1 -ne $r.Pass2) { Fail ("idempotent: kept -- " + $k.Why) }
}

# A marker is never REWRITTEN either: `// if` on a long `while` block stays
# `// if`, it does not become `// while`.
$longLoop = @(
  'unit lbl;'
  'interface'
  'implementation'
  'procedure P;'
  'begin'
  '  while A do'
  '  begin'
) + (1..12 | ForEach-Object { "    B($_);" }) + @(
  '  end; // if'
  'end;'
  'end.'
) -join "`r`n"
$noRewrite = Fmt $longLoop @('--label-min-lines', '10')
MustMatch    $noRewrite.Pass1 '(?m)^  end; // if\s*$' 'a long block keeps its hand-written marker verbatim'
MustNotMatch $noRewrite.Pass1 '// while'              'a mismatched marker is never re-derived'
if ($noRewrite.Pass1 -ne $noRewrite.Pass2) { Fail 'idempotent: marker never rewritten' }

# ----- Round-trip: --check still passes on output that lost a label -----
$rt  = Join-Path $env:TEMP 'lbl_rt.pas'
$rto = Join-Path $env:TEMP 'lbl_rt_out.pas'
Set-Content -Path $rt -Value (ShortProc ' // procedure') -Encoding ascii
& $exe --ini $ini $rt --o $rto | Out-Null
$chk = & $exe --ini $ini --check $rto 2>&1
if ("$chk" -notmatch 'PASS') { Fail 'roundtrip: output that removed a label' }
Remove-Item $rt, $rto -Force -ErrorAction SilentlyContinue

Finish 'block_labels'
