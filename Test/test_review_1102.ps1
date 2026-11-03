# Repros from .private\REVIEW-2026-11-02-corruption.md and -options.md, one
# section per finding. Fixtures live in Test\Cases\review1102 (the option
# battery formats them under every set too). A program fixture is compiled
# and RUN before and after formatting: the stdout must be identical (a silent
# value change is the HIGH class of the corruption review).
# Usage: pwsh Test\test_review_1102.ps1   (exit 0 = pass)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'review_1102' $exe
$fail = 0
$cases = Join-Path $PSScriptRoot 'Cases\review1102'
$dcc   = Get-Dcc64
$work  = Join-Path $env:TEMP ('rev1102_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
$ini = Join-Path $work 'plain.ini'
[IO.File]::WriteAllText($ini, "[Format]`r`n")

function Format-To([string]$src, [string]$iniPath, [string[]]$flags, [string]$tag) {
  $dir = Join-Path $work $tag
  New-Item -ItemType Directory -Force $dir | Out-Null
  $out = Join-Path $dir ([IO.Path]::GetFileName($src))
  $msg = & $exe --ini $iniPath $src @flags --o $out 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "$tag $([IO.Path]::GetFileName($src)): exit $LASTEXITCODE -- $($msg.Trim())"; return $null }
  return $out
}
function Run-Program([string]$pas) {
  # Always under $work (never next to a fixture in Test\Cases).
  $dir = Join-Path $work ('bin_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force $dir | Out-Null
  $log = & $dcc -Q -NSSystem "-N0$dir" "-E$dir" $pas 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { return "<does not compile: $((@($log -split "`n") -match 'Error' | Select-Object -First 2) -join ' | ')>" }
  return (& (Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($pas) + '.exe')) 2>&1 | Out-String)
}
function Same-Run([string]$src, [string]$out, [string]$label) {
  $a = Run-Program $src; $b = Run-Program $out
  if ($a -ne $b) { Fail "${label}: program output changed`n    in : $($a.Trim())`n    out: $($b.Trim())" }
}
function Idempotent([string]$out, [string]$iniPath, [string[]]$flags, [string]$label) {
  $o2 = Format-To $out $iniPath $flags ($label -replace '\W', '_') + '_2'
  if ($o2 -and ([IO.File]::ReadAllText($o2) -ne [IO.File]::ReadAllText($out))) {
    $d = @(& git -c core.autocrlf=false diff --no-index --no-color -U0 -- $out $o2 2>&1 | Select-Object -Skip 4 -First 8)
    Fail "${label}: second run changed the output`n    $($d -join "`n    ")"
  }
}

# ---- corruption H1 + M1: --d10 literal type inference ----
$src = Join-Path $cases 'review1102_d10_literals.pas'
$o = Format-To $src $ini @('--d10') 'h1'
if ($o) {
  $t = [IO.File]::ReadAllText($o)
  MustMatch $t '(?m)^\s*Small\s*:\s*Integer\s*;' 'H1: 2147483647 -> Integer'
  MustMatch $t '(?m)^\s*Big\s*:\s*Cardinal\s*;' 'H1: 2147483648 -> Cardinal'
  MustMatch $t '(?m)^\s*Big10\s*:\s*Int64\s*;' 'H1: 10000000000 -> Int64'
  MustMatch $t '(?m)^\s*UHex\s*:\s*Cardinal\s*;' 'H1: $FFFFFFFF -> Cardinal'
  MustMatch $t '(?m)^\s*Big64\s*:\s*Int64\s*;' 'H1: $1FFFFFFFF -> Int64'
  MustMatch $t '(?m)^\s*UsBig\s*:\s*Cardinal\s*;' 'H1: 3_000_000_000 -> Cardinal'
  MustMatch $t '(?m)^\s*F2\s*:\s*Extended\s*;' 'M1: 1e3 -> Extended'
  MustMatch $t '(?m)^\s*I\s*:\s*Cardinal\s*;' 'H1: for var I := 4294967294 -> Cardinal'
  Same-Run $src $o 'H1/M1 --d10'
  Idempotent $o $ini @('--d10') 'H1/M1 --d10'
  # options L3: every comment --d10 inserts carries the -cd10 marker ...
  MustNotMatch $t '//(?! TODO -oYADF -cd10 :)[^\r\n]*(inferred|verify)' 'options L3: a d10 verify comment without the marker'
  MustMatch $t '// TODO -oYADF -cd10 : inferred type, verify' 'options L3: inferred-type comment is marked'
  MustMatch $t '// TODO -oYADF -cd10 : inferred loop type, verify' 'options L3: inferred-loop comment is marked'
  # ... and a run without --d10 removes them all (the hoisted declarations stay).
  $p = Format-To $o $ini @() 'l3'
  if ($p) {
    $pt = [IO.File]::ReadAllText($p)
    MustNotMatch $pt '-cd10|inferred|verify' 'options L3: plain run removes every d10 comment'
    MustMatch $pt '(?m)^\s*Big\s*:\s*Cardinal\s*;' 'options L3: hoisted declaration kept'
    Same-Run $src $p 'options L3 d10 -> plain'
  }
}

# ---- corruption L1: text after `end.` is left verbatim, not declined ----
$src = Join-Path $cases 'review1102_after_end.pas'
foreach ($set in @(@(), @('--max-len', '60'), @('--no-reflow'))) {
  $tag = 'l1' + (($set -join '') -replace '\W', '')
  $o = Format-To $src $ini $set $tag
  if ($o) {
    $t = [IO.File]::ReadAllText($o)
    MustContain $t "end.`r`nTrailing junk after end. with an 'unbalanced quote and { open brace`r`nand more junk`r`n" "corruption L1 [$($set -join ' ')]: tail after end. verbatim"
    Same-Run $src $o "corruption L1 [$($set -join ' ')]"
    Idempotent $o $ini $set "corruption L1 $($set -join ' ')"
  }
}

# ---- corruption L2 a-d: second pass must not change the first ----
$repoIni = Get-RepoIni
foreach ($c in @(
    @{ F = 'review1102_l2a_ifdef_params.pas'; Flags = @() },
    @{ F = 'review1102_l2a_ifdef_params.pas'; Flags = @('--max-len', '60', '--break-params', '--break-case', '--no-case-arm-on-label') },
    @{ F = 'review1102_l2b_collapse_chain.pas'; Flags = @('--pack-statements', '--collapse-blocks') },
    @{ F = 'review1102_l2c_anon_wrap.pas'; Flags = @('--max-len', '60') },
    @{ F = 'review1102_l2d_trailing_op.pas'; Flags = @() })) {
  $o = Format-To (Join-Path $cases $c.F) $repoIni $c.Flags ('l2' + $c.F.Substring(11, 3))
  if ($o) { Idempotent $o $repoIni $c.Flags "corruption L2 $($c.F) $($c.Flags -join ' ')" }
}
$o = Join-Path $work 'l2l2a\review1102_l2a_ifdef_params.pas'
if (Test-Path $o) { MustMatch ([IO.File]::ReadAllText($o)) '(?m)^\s+Writeln\(1\);\r?$' 'corruption L2a: statements after the {$IFDEF} header are split in pass 1' }

# ---- options H1: greedy breaker (BreakLongExpressions=false) at MaxLen <= 60 ----
foreach ($ml in 60, 50) {
  $gIni = Join-Path $work "greedy$ml.ini"
  [IO.File]::WriteAllText($gIni, "[Format]`r`nBreakLongExpressions=false`r`nMaxLen=$ml`r`n")
  foreach ($f in 'idem_nested_case_arm.pas', 'idem_nested_case_arm2.pas') {
    $o = Format-To (Join-Path $PSScriptRoot "Cases\idem\$f") $gIni @() "g$ml"
    if ($o) {
      MustNotMatch ([IO.File]::ReadAllText($o)) '\[[^\]\r\n]*\r\n' "options H1 greedy MaxLen=${ml} ${f}: no break inside [...]"
      Idempotent $o $gIni @() "options H1 greedy MaxLen=$ml $f"
    }
  }
}

# ---- options M1: LabelMinLines=1 must not label an asm `end` (2nd run declined) ----
$lIni = Join-Path $work 'labels1.ini'
[IO.File]::WriteAllText($lIni, "[Format]`r`nLabelLongBlocks=true`r`nLabelMinLines=1`r`n")
$o = Format-To (Join-Path $PSScriptRoot 'Cases\asm_blocks.pas') $lIni @() 'l1'
if ($o) {
  MustNotMatch ([IO.File]::ReadAllText($o)) '(?m)^end; // asm' 'options M1: no label on an asm end'
  Idempotent $o $lIni @() 'options M1 LabelMinLines=1 asm_blocks'
}

# ---- options M4: two-phase resolution; --pack-bodies order- and source-independent ----
$pb = Join-Path $PSScriptRoot 'Cases\pack_bodies.pas'
$bare = Join-Path $work 'bare.ini';   [IO.File]::WriteAllText($bare, "[Format]`r`n")
$aliasIf = Join-Path $work 'aliasif.ini'; [IO.File]::WriteAllText($aliasIf, "[Format]`r`nPackShortBodies=true`r`nBreakIfBody=true`r`n")
$keepIf  = Join-Path $work 'keepif.ini';  [IO.File]::WriteAllText($keepIf, "[Format]`r`nBreakIfBody=true`r`n")
$aliasNo = Join-Path $work 'aliasno.ini'; [IO.File]::WriteAllText($aliasNo, "[Format]`r`nPackShortBodies=true`r`n")
function Txt([string]$iniPath, [string[]]$flags, [string]$tag) { $o = Format-To $pb $iniPath $flags $tag; if ($o) { [IO.File]::ReadAllText($o) } else { '' } }
$a1 = Txt $bare @('--pack-bodies', '--break-if') 'm4a'
$a2 = Txt $bare @('--break-if', '--pack-bodies') 'm4b'
if ($a1 -ne $a2) { Fail 'options M4: --pack-bodies --break-if differs from --break-if --pack-bodies' }
MustMatch $a1 '(?m)^\s+DoIt;' 'options M4: explicit --break-if wins over --pack-bodies'
MustMatch $a1 'for I:= 0 to N do Inc\(N\);' 'options M4: --pack-bodies still packs the loop body'
$b1 = Txt $keepIf @('--pack-bodies') 'm4c'
$b2 = Txt $aliasIf @() 'm4d'
if ($b1 -ne $b2) { Fail 'options M4: --pack-bodies + INI BreakIfBody=true differs from INI PackShortBodies=true + BreakIfBody=true' }
MustMatch $b1 '(?m)^\s+DoIt;' 'options M4: INI BreakIfBody=true wins over --pack-bodies'
$c1 = Txt $aliasNo @('--no-pack-bodies') 'm4e'
$c2 = Txt $bare @() 'm4f'
if ($c1 -ne $c2) { Fail 'options M4: --no-pack-bodies does not cancel INI PackShortBodies=true' }
$help = & $exe --ini $bare --help 2>&1 | Out-String
MustMatch $help '--pack-bodies\s' 'options M4: --pack-bodies listed in --help'
# M3/L7: an out-of-range INI value is reported like a CLI one
$clampIni = Join-Path $work 'clamp.ini'; [IO.File]::WriteAllText($clampIni, "[Format]`r`nMaxLen=10`r`n")
$err = & $exe --ini $clampIni $pb --o (Join-Path $work 'clamp.pas') 2>&1 | Out-String
MustMatch $err 'MaxLen 10 -> 40' 'options M3/L7: INI clamp reported on stderr'

[IO.Directory]::Delete($work, $true)
Finish 'review_1102'
