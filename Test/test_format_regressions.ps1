# Format-correctness regressions (things --check / round-trip cannot catch because
# they verify byte coverage, not the formatted shape). Exit 0 = pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win64\Debug\EXE\YADF.exe'
$casesDir = Join-Path $PSScriptRoot 'Cases'
$fail = 0

function Fmt([string]$name) {
  $src = Join-Path $casesDir $name
  $tmp = Join-Path $env:TEMP ("fmt_" + [IO.Path]::GetFileNameWithoutExtension($name) + ".out")
  & $exe $src --o $tmp | Out-Null
  $out = Get-Content $tmp -Raw
  return $out
}
function MustMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -notmatch $rx) { $script:fail++; Write-Output "FAIL [$label]: expected /$rx/" }
}
function MustNotMatch([string]$out, [string]$rx, [string]$label) {
  if ($out -match $rx) { $script:fail++; Write-Output "FAIL [$label]: should NOT match /$rx/" }
}

# --- of_object_types: 'of object' must not be parsed as an object...end block,
#     and a procedural/method-pointer type must not close the type section ---
$o = Fmt 'of_object_types.pas'
MustNotMatch $o '//\s*object' 'of_object: no spurious // object label'
MustMatch $o '(?m)^  TNotifyEvent = procedure\(Sender: TObject\) of object;' 'of_object: event type indented + intact'
MustMatch $o '(?m)^  TThing = class' 'of_object: class keeps type-section indent'
MustMatch $o '(?m)^    FHandler: function\(P1: Integer\): HResult of object stdcall;' 'of_object: method-pointer field indented + intact'
MustMatch $o '(?m)^end\.\s*$' 'of_object: unit end. unlabeled'

# --- directive_levels: {$IF}/{$ELSE}/{$ENDIF} of one group share a level (no drift) ---
$o = Fmt 'directive_levels.pas'
MustMatch    $o '(?m)^\{\$IF Defined\(MSWINDOWS\)\}' 'directives: $IF at column 0'
MustMatch    $o '(?m)^\{\$ELSE\}'  'directives: $ELSE aligned with $IF'
MustMatch    $o '(?m)^\{\$ENDIF\}' 'directives: $ENDIF aligned with $IF'
MustNotMatch $o '(?m)^\s+\{\$(ELSE|ENDIF)\}' 'directives: $ELSE/$ENDIF not drifted/indented'

if ($fail -eq 0) { Write-Output "format_regressions: PASS"; exit 0 }
else { Write-Output "format_regressions: $fail FAILED"; exit 1 }
