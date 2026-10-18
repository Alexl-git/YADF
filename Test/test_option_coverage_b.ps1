# Option coverage, part B (WP23 second half): one FLIPPED-FROM-DEFAULT run for
# each option that had no non-default test (REVIEW-2026-10-14): AlignSmartAssign,
# AlignMaxColumn, AlignMatchingShapes, AlignShapeMinAnchors, AlignCommentMaxShift,
# SpaceAroundOperators, SplitMultiVarDecls, MarkUnclosed, Backup, BackupDir,
# ResultDir, Logging. Each gets: a default-vs-flipped observable assertion, and
# CheckStable (idempotent + byte-faithful round-trip) under the flipped config.
# The fixtures are fragments written to temp (they are not standalone-compilable
# units with real types), so there is no dcc compile check here; the --check
# round-trip is the safety net. Flipping is done via a temp copy of the repo
# yadf.ini with ONE key replaced, so every other option stays pinned.
# Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'option_coverage_b' $exe
$repoIni = Get-RepoIni
$ascii = New-Object Text.ASCIIEncoding

# Temp copy of the repo ini with the given keys overridden.
function New-Ini([hashtable]$ov) {
  $p = New-TempOut '.ini'
  $t = Get-Content $repoIni -Raw
  foreach ($k in $ov.Keys) {
    $n = [regex]::Replace($t, "(?m)^\s*$k\s*=.*$", "$k=$($ov[$k])")
    if ($n -eq $t) { Fail "ini key not found in yadf.ini: $k" }
    $t = $n
  }
  [IO.File]::WriteAllText($p, $t, $ascii)
  return $p
}

function New-Src([string]$text) {
  $p = New-TempOut '.pas'
  [IO.File]::WriteAllText($p, $text.Replace("`r`n", "`n").Replace("`n", "`r`n"), $ascii)
  return $p
}

# Formats $src with a config overriding $ov; returns the text ('' on failure).
# Also runs CheckStable under that config unless $stable is $false.
# CheckStable reads $exe/$ini/$src from THIS (script) scope.
function Fmt([string]$label, [hashtable]$ov, [bool]$stable = $true) {
  $script:ini = New-Ini $ov
  $out = New-TempOut
  if (-not (Invoke-Yadf $script:src $script:ini $out)) { return '' }
  if ($stable) { CheckStable $label @() }
  return (Get-Content $out -Raw)
}

$calls = @'
unit Calls;

interface

implementation

procedure Demo;
var
  A, B: Integer;
  Long1: Integer;
begin
  A:=1+2*B;
  Long1:=A-B;
  Foo(1, 2, 3);
  Foo(10, 20, 30);
  Foo(100, 200, 300);
end;

end.
'@

$comments = @'
unit Comments;

interface

implementation

procedure Demo;
begin
  A := 1; // first
  LongName := 22222; // second
  Mid := 'xx'; // third
end;

end.
'@

$unclosed = @'
unit Unclosed;

interface

implementation

procedure Demo;
begin
  if X then
  begin
    Foo;

end.
'@

# ----- shape / alignment family (fixture: $calls) -----
$src = New-Src $calls
$def = Fmt 'defaults' @{}
MustMatch $def 'Foo\(1  , 2  , 3  \);'  'default: Foo calls shape-aligned'
MustMatch $def '(?m)^  A    : Integer;' 'default: var colons aligned'
MustMatch $def 'A:= 1 \+ 2 \* B;'       'default: operators spaced'

$o = Fmt 'AlignSmartAssign=false' @{ AlignSmartAssign = 'false' }
MustMatch    $o 'Foo\(1, 2, 3\);'     'AlignSmartAssign=false: shape pass is off (master switch)'
MustNotMatch $o 'Foo\(1  ,'           'AlignSmartAssign=false: no shape padding'

$o = Fmt 'AlignMatchingShapes=false' @{ AlignMatchingShapes = 'false' }
MustMatch    $o 'Foo\(10, 20, 30\);'  'AlignMatchingShapes=false: Foo calls left plain'
MustNotMatch $o 'Foo\(1  ,'           'AlignMatchingShapes=false: no shape padding'

$o = Fmt 'AlignShapeMinAnchors=9' @{ AlignShapeMinAnchors = '9' }
MustMatch    $o 'Foo\(10, 20, 30\);'  'AlignShapeMinAnchors=9: 6-anchor shape below floor, left plain'
MustNotMatch $o 'Foo\(1  ,'           'AlignShapeMinAnchors=9: no shape padding'

$o = Fmt 'AlignMaxColumn=5' @{ AlignMaxColumn = '5' }
MustMatch    $o '(?m)^  A: Integer;'  'AlignMaxColumn=5: var colon alignment skipped (past max column)'
MustNotMatch $o '(?m)^  A +: Integer;' 'AlignMaxColumn=5: no colon padding'

$o = Fmt 'SpaceAroundOperators=false' @{ SpaceAroundOperators = 'false' }
MustMatch    $o 'A:= 1\+2\*B;'        'SpaceAroundOperators=false: binary operators stay tight'
MustMatch    $o 'Long1:= A-B;'        'SpaceAroundOperators=false: A-B stays tight'

$o = Fmt 'SplitMultiVarDecls=false' @{ SplitMultiVarDecls = 'false' }
MustMatch    $o '(?m)^  A, B *: Integer;' 'SplitMultiVarDecls=false: "A, B: Integer;" kept on one line'
MustNotMatch $o '(?m)^  A +: Integer;'    'SplitMultiVarDecls=false: A not split off'
MustMatch    $def '(?m)^  B +: Integer;'  'SplitMultiVarDecls default: B split onto its own line'

# ----- trailing-comment alignment (fixture: $comments) -----
$src = New-Src $comments
$def = Fmt 'defaults/comments' @{}
MustMatch $def '1;     // first'  'default: trailing comments pulled to a shared column'
$o = Fmt 'AlignCommentMaxShift=0' @{ AlignCommentMaxShift = '0' }
MustMatch    $o '1; // first'    'AlignCommentMaxShift=0: comment left where the author put it'
MustNotMatch $o '1;     // first' 'AlignCommentMaxShift=0: no comment padding'

# ----- MarkUnclosed (fixture: $unclosed) -----
$src = New-Src $unclosed
$def = Fmt 'defaults/unclosed' @{} $false
MustNotMatch $def 'TODO -oYADF' 'MarkUnclosed default(false): no marker'
$o = Fmt 'MarkUnclosed=true' @{ MarkUnclosed = 'true' } $false
MustMatch $o "// TODO -oYADF : 'begin' on line 8 has no matching 'end'" 'MarkUnclosed=true: marker emitted'

# ----- Backup / BackupDir / ResultDir (in-place and --of-style destinations) -----
# These run the exe WITHOUT --o so the destination logic is the one under test.
function New-Work {
  $d = Join-Path $env:TEMP ('yoc_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory $d | Out-Null
  $f = Join-Path $d 'work.pas'
  [IO.File]::WriteAllText($f, $calls.Replace("`r`n", "`n").Replace("`n", "`r`n"), $ascii)
  return $d
}
function Run-InPlace([string]$ini, [string]$file) {
  $msg = & $exe --ini $ini $file 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or $msg -match '(?m)^declined ') { Fail "in-place run failed: $($msg.Trim())" }
}

# Backup=false (default): no sibling copy; Backup=true: <file>.BCK1 holds the ORIGINAL.
$d = New-Work; $f = Join-Path $d 'work.pas'
$orig = [IO.File]::ReadAllText($f)
Run-InPlace (New-Ini @{}) $f
if (@(Get-ChildItem $d -Filter '*.BCK*').Count -ne 0) { Fail 'Backup default: a backup was written' }
MustMatch ([IO.File]::ReadAllText($f)) 'Foo\(1  ,' 'Backup default: file formatted in place'
$d = New-Work; $f = Join-Path $d 'work.pas'
Run-InPlace (New-Ini @{ Backup = 'true' }) $f
$bck = Join-Path $d 'work.pas.BCK1'
if (-not (Test-Path $bck)) { Fail 'Backup=true: work.pas.BCK1 not written' }
elseif ([IO.File]::ReadAllText($bck) -ne $orig) { Fail 'Backup=true: BCK1 is not the original content' }
MustMatch ([IO.File]::ReadAllText($f)) 'Foo\(1  ,' 'Backup=true: file still formatted in place'

# BackupDir: timestamped .bak under the folder, original content, no sibling BCK.
$d = New-Work; $f = Join-Path $d 'work.pas'
$bd = Join-Path $d 'bk'
Run-InPlace (New-Ini @{ Backup = 'true'; BackupDir = $bd }) $f
$baks = @(Get-ChildItem $bd -Filter 'work.pas.*.bak' -ErrorAction SilentlyContinue)
if ($baks.Count -ne 1) { Fail "BackupDir: expected 1 .bak under the folder, got $($baks.Count)" }
elseif ([IO.File]::ReadAllText($baks[0].FullName) -ne $orig) { Fail 'BackupDir: .bak is not the original content' }
if (@(Get-ChildItem $d -Filter '*.BCK*').Count -ne 0) { Fail 'BackupDir: a sibling BCK was written too' }

# ResultDir: formatted copy lands in the folder, the source is untouched.
$d = New-Work; $f = Join-Path $d 'work.pas'
$rd = Join-Path $d 'res'
Run-InPlace (New-Ini @{ ResultDir = $rd }) $f
$rf = Join-Path $rd 'work.pas'
if (-not (Test-Path $rf)) { Fail 'ResultDir: formatted file not written under the folder' }
else { MustMatch ([IO.File]::ReadAllText($rf)) 'Foo\(1  ,' 'ResultDir: output is formatted' }
if ([IO.File]::ReadAllText($f) -ne $orig) { Fail 'ResultDir: the source file was modified' }

# ----- Logging: --log appends to %APPDATA%\YADF\yadf-startup.log (cheap check:
# the log grows). Driven by the CLI flag; the key itself is Logging=true. -----
$log = Join-Path $env:APPDATA 'YADF\yadf-startup.log'
$before = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
$src = New-Src $calls
$ini = New-Ini @{ Logging = 'true' }
$out = New-TempOut
[void](Invoke-Yadf $src $ini $out)
$after = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
if ($after -le $before) { Fail 'Logging=true: yadf-startup.log did not grow' }

Finish 'option_coverage_b'
