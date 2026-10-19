# RED target: `class` / `record` / `constructor` used as a GENERIC CONSTRAINT
# were treated by ReindentByDepth as real block / routine keywords.
#
# `constructor` hit the procedure/function/constructor arm (PrevNonKind was
# ptComma, so every guard passed) and called CloseSectionIfOpen, popping the
# enclosing `type` section; `record` pushed a block nothing ever closed. The
# result: `TBaz2<TComma1, TComma2: class>` and `TBax<T1: class; T2: record>`
# landed at indent 0 and the class body after them was over-indented.
# Found 2026-09-10 (TODO.md), fixed 2026-10-14.
#
# Invariants checked (structure, not style):
#   * every type declaration in the type section is a SIBLING -> one indent;
#   * TBax's members (incl. generic methods with record/class/constructor
#     constraints) share one indent, one level deeper than TBax;
#   * TBax's `end;` is back at the type indent;
#   * the unit-level routine declarations sit at column 0;
#   * `implementation` and `end.` stay at column 0 (the stack is balanced).
#
# NOT compile-checked: the fixture is deliberately non-standalone. Besides using
# TComponent without a uses clause, it carries a constraint form dcc64 rejects
# (E2029 at the generic-method line), because it exists to exercise the indent
# engine on keyword-like constraints, not to be valid Delphi. Checks are structural.
#
# Usage: pwsh Test\test_generic_constraints.ps1   (exit 0 = pass, 1 = fail)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'generic_constraints' $exe
$src = Join-Path $PSScriptRoot 'Cases\generic_constraint_keywords.pas'

function Ind([string]$s) { $s.Length - $s.TrimStart().Length }

$tmp = Join-Path $env:TEMP ("genconstr_" + [guid]::NewGuid().ToString('N') + ".pas")
& $exe --ini $ini $src --o $tmp | Out-Null
if (-not (Test-Path $tmp)) { Fail 'generic_constraints: no output produced'; Finish 'generic_constraints'; return }
$lines = Get-Content $tmp

function LineOf([string]$pattern) {
  for ($k = 0; $k -lt $lines.Count; $k++) { if ($lines[$k] -match $pattern) { return $k } }
  return -1
}
function Show([int[]]$idx) { ($idx | ForEach-Object { if ($_ -ge 0) { "$(Ind $lines[$_]):" + $lines[$_].Trim() } else { '<missing>' } }) -join ' | ' }

$decls = @('^\s*TBaz<', '^\s*TBaz2<', '^\s*TBax<', '^\s*TSibling\s*=', '^\s*TAfterSection\s*=', '^\s*TLast\s*=') | ForEach-Object { LineOf $_ }
if ($decls -contains -1) {
  Fail ("generic_constraints: a type declaration is missing: " + (Show $decls))
}
else {
  $typeInd = Ind $lines[$decls[0]]
  $levels  = @($decls | ForEach-Object { Ind $lines[$_] } | Select-Object -Unique)
  if ($levels.Count -ne 1) { Fail ("generic_constraints: sibling type declarations at different indents: " + (Show $decls)) }

  $members = @('^\s*procedure DoStuff;', '^\s*procedure Make<', '^\s*function Build<', '^\s*procedure After;') | ForEach-Object { LineOf $_ }
  $mLevels = @($members | ForEach-Object { if ($_ -ge 0) { Ind $lines[$_] } else { -1 } } | Select-Object -Unique)
  if ($mLevels.Count -ne 1 -or $mLevels[0] -le $typeInd) {
    Fail ("generic_constraints: TBax members not aligned one level under TBax: " + (Show $members))
  }

  $endIdx = -1
  if ($members[3] -ge 0) {
    for ($k = $members[3] + 1; $k -lt $lines.Count; $k++) { if ($lines[$k] -match '^\s*end;\s*$') { $endIdx = $k; break } }
  }
  if ($endIdx -lt 0 -or (Ind $lines[$endIdx]) -ne $typeInd) { Fail "generic_constraints: TBax's end; not at the type indent ($typeInd)" }
}

foreach ($p in '^\s*procedure Global<', '^\s*procedure GlobalAfter;', '^\s*implementation\s*$', '^\s*end\.\s*$') {
  $k = LineOf $p
  if ($k -lt 0 -or (Ind $lines[$k]) -ne 0) { Fail ("generic_constraints: expected column 0: " + (Show @($k))) }
}

Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Finish 'generic_constraints'
