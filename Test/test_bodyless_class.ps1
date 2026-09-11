# RED target: "ladder" indentation of bodyless class / interface declarations.
#
# A declaration with no body (`E = class(Exception);`, `T = class;`,
# `I = interface;`, `TC = class of T;`) ends at its `;` and never reaches an
# `end`. ReindentByDepth pushed a stack level on `= class` / `= interface` and
# popped it only on `end`, so each bodyless declaration leaked one level and
# every following sibling stepped one indent deeper -- a staircase.
#
# Reported 2026-09-10 against C:\Projects\DB\ORM3\COMMON\CommonExceptions.pas,
# where nine sibling exception classes rendered as a nine-step ladder.
#
# The assertion is the unambiguous invariant, not a style choice: every type
# declaration in the block is a SIBLING, so they must all share one indent.
#
# Usage: pwsh Test\test_bodyless_class.ps1   (exit 0 = pass, 1 = fail)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'bodyless_class' $exe
$src = Join-Path $PSScriptRoot 'Cases\bodyless_class_decls.pas'

function Ind([string]$s) { $s.Length - $s.TrimStart().Length }

$tmp = Join-Path $env:TEMP ("bodyless_" + [guid]::NewGuid().ToString('N') + ".pas")
& $exe --ini $ini $src --o $tmp | Out-Null
if (-not (Test-Path $tmp)) { Fail 'bodyless: no output produced'; Finish 'bodyless_class'; return }
$lines = Get-Content $tmp

# Collect the type-declaration lines: `Name = <something>` at the start of a
# declaration. Only those between `type` and `implementation`, and only ones
# not nested inside a class body (a member line never matches `X = ...`).
$declInd = @{}
$inType  = $false
foreach ($ln in $lines) {
  $tr = $ln.Trim()
  if ($tr -eq 'type')           { $inType = $true;  continue }
  if ($tr -eq 'implementation') { $inType = $false; continue }
  if (-not $inType) { continue }
  if ($tr -match '^[A-Za-z_]\w*\s*=\s*(class|interface|record)\b') {
    $declInd[$tr] = (Ind $ln)
  }
}

if ($declInd.Count -lt 10) {
  Fail "bodyless: expected >= 10 type declarations, found $($declInd.Count)"
}
else {
  $levels = $declInd.Values | Select-Object -Unique
  if ($levels.Count -ne 1) {
    Fail ("bodyless: sibling type declarations at {0} different indents ({1}) -- ladder" -f $levels.Count, (($levels | Sort-Object) -join ', '))
    foreach ($k in ($declInd.Keys | Sort-Object { $declInd[$_] })) {
      Write-Output ("       indent {0,2} : {1}" -f $declInd[$k], $k)
    }
  }
  elseif ($levels[0] -ne 2) {
    Fail "bodyless: sibling type declarations sit at indent $($levels[0]), expected 2"
  }
}

# The stack must be balanced afterwards: `implementation` and `end.` stay at 0.
foreach ($ln in $lines) {
  $tr = $ln.Trim()
  if (($tr -eq 'implementation') -or ($tr -eq 'end.')) {
    if ((Ind $ln) -ne 0) { Fail "bodyless: '$tr' indented to $(Ind $ln), expected 0" }
  }
}

# A bodied class must still indent its own members deeper than its header.
$ownerInd = $null
foreach ($ln in $lines) {
  if ($ln.Trim() -match '^TOwner\s*=\s*class') { $ownerInd = Ind $ln }
  elseif ($null -ne $ownerInd -and $ln.Trim() -eq 'private') {
    if ((Ind $ln) -le $ownerInd) { Fail "bodyless: TOwner's 'private' not indented under its class header" }
    break
  }
}

Remove-Item $tmp -Force -ErrorAction SilentlyContinue
Finish 'bodyless_class'
