# Column alignment must never pad inside a uses clause.
#
# WHY: a qualified unit name (System.Win.Registry) is ONE identifier. The shape
# aligner treats every `.` as an anchor, so two comma-first entries sharing the
# [, . .] skeleton had their dots padded into columns -- `System.Win     .Registry`.
# That is not a layout, it is noise, and the 1.0.13.1 self-format pass wrote it
# into YADF's own uses clauses. Uses-clause lines are now alignment-ineligible.
#
# Exit 0 = pass.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: a personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'uses_no_align' $exe
$src = Join-Path $PSScriptRoot 'Cases\uses_no_align.pas'
$tmp = Join-Path $env:TEMP ('uses_no_align_' + [guid]::NewGuid().ToString('N') + '.pas')
& $exe --ini $ini $src --o $tmp | Out-Null
$o = Get-Content $tmp -Raw

# The clause is still broken one-unit-per-line, comma-first (we suppressed
# ALIGNMENT, not the uses layout).
MustMatch $o '(?m)^\s*, System\.Generics\.Collections\s*$' 'interface: Generics.Collections unpadded'
MustMatch $o '(?m)^\s*, System\.Win\.Registry\s*$'         'interface: Win.Registry unpadded'
MustMatch $o '(?m)^\s*, System\.Generics\.Defaults\s*$'    'implementation: Generics.Defaults unpadded'
MustMatch $o '(?m)^\s*, System\.Win\.ComObj\s*$'           'implementation: Win.ComObj unpadded'

# The defect itself, stated generically: no run of whitespace may sit between a
# unit-name segment and the dot that follows it, anywhere in the file.
MustNotMatch $o '(?m)^\s*,?\s*\w[\w.]*\s+\.' 'no padding before a dot in a uses entry'

# The fixture's implementation clause arrives pre-padded, so this fixture is the
# one place that proves the tighten CONVERGES: format(format(x)) = format(x), and
# the round-trip stays byte-faithful. (CheckStable reads $exe/$ini/$src.)
CheckStable 'uses_no_align' @()

Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Finish 'uses_no_align'
