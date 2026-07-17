# Regression test: YADF must preserve the interior of multi-line ('''...''') string
# literals verbatim when formatting. Round-trip (--check) cannot catch this class of
# bug (it only verifies byte coverage), so we assert the literal text survives format.
#
# Usage: pwsh Test\test_multiline_preserve.ps1
# Exit 0 = pass, 1 = fail.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
$src = Join-Path $PSScriptRoot 'Cases\multiline_closing_at_col1.pas'

Assert-ToolOrSkip 'multiline_preserve' $exe
if (-not (Test-Path $src)) { Write-Error "source not found: $src"; exit 2 }

$tmp = [System.IO.Path]::GetTempFileName()
try {
    & $exe --ini $ini $src --o $tmp | Out-Null
    $out = Get-Content $tmp -Raw

    # Each multi-line literal must appear verbatim in the formatted output --
    # interiors are the string VALUE and must pass through byte-for-byte,
    # including apostrophes, doubled quotes, keyword-like words, and spacing.
    $needles = @(
        "'''`r`nHello world;`r`nSecond line;`r`n'''",
        "'''`r`nIndented open, closing at col1;`r`n'''",
        "'''`r`nit's a test; don't break it`r`nbegin end { not a brace } // not a comment`r`n    keep   this    spacing;`r`n'''"
    )

    $fail = $false
    foreach ($n in $needles) {
        if (-not $out.Contains($n)) {
            $fail = $true
            Write-Output "FAIL: multi-line literal not preserved verbatim:"
            Write-Output ("       expected to find >>>" + ($n -replace "`r`n","\r\n") + "<<<")
        }
    }

    # The begin/end INSIDE the string must not corrupt indentation of real code
    # that follows: the if-body WriteLn must be indented one step under `if`.
    if ($out -notmatch "(?m)^  if True then`r?`n    WriteLn\(CMsg3\);") {
        $fail = $true
        Write-Output "FAIL: real code after a keyword-bearing multi-line string is mis-indented"
    }

    if ($fail) {
        Write-Output ""
        Write-Output "--- actual formatted output ---"
        Write-Output $out
        Write-Output "multiline_preserve: FAIL"
        exit 1
    }
    Write-Output "multiline_preserve: PASS"
    exit 0
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
