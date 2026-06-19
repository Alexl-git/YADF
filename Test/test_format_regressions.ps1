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

# --- anon_array_split: a combined var/field whose type is an ANONYMOUS structured
#     type must NOT be split -- each split copy is a DISTINCT type, so shared-type
#     code stops compiling (E2008). NAMED/simple types must STILL split.
#     (SplitMultiVarDecls anonymous-type guard, 2026-06-18.) ---
$o = Fmt 'anon_array_split.pas'
MustMatch    $o '(?m)^\s*RowPrev, RowCurr\s*:'   'anon: dynamic array stays combined'
MustNotMatch $o '(?m)^\s*RowPrev\s*:\s*array'    'anon: dynamic array not split'
MustMatch    $o '(?m)^\s*MatA, MatB\s*:'         'anon: static array stays combined'
MustMatch    $o '(?m)^\s*SetA, SetB\s*:'         'anon: set stays combined'
MustMatch    $o '(?m)^\s*FileA, FileB\s*:'       'anon: file stays combined'
MustMatch    $o '(?m)^\s*PackA, PackB\s*:'       'anon: packed array stays combined'
MustMatch    $o '(?m)^\s*RecA, RecB\s*:'         'anon: inline record stays combined'
MustMatch    $o '(?m)^\s*PtrA, PtrB\s*:'         'anon: typed pointer stays combined'
# NAMED / simple types must STILL split (one shared named type either way):
MustMatch    $o '(?m)^\s*NamedA\s*:\s*Integer'   'named: Integer DOES split (A)'
MustMatch    $o '(?m)^\s*NamedB\s*:\s*Integer'   'named: Integer DOES split (B)'
MustNotMatch $o '(?m)^\s*NamedA, NamedB\s*:'     'named: Integer not left combined'
MustMatch    $o '(?m)^\s*ObjA\s*:\s*TObject'     'named: TObject DOES split (A)'
MustMatch    $o '(?m)^\s*ObjB\s*:\s*TObject'     'named: TObject DOES split (B)'

# --- anon_proc_split: anonymous PROCEDURAL types must NOT split, AND a leading
#     procedure/function var type must NOT open a proc region (which used to
#     over-indent the routine's begin/end). ---
$o = Fmt 'anon_proc_split.pas'
MustMatch    $o '(?m)^\s*ProcA, ProcB\s*:'       'anon: procedure-of-object stays combined'
MustNotMatch $o '(?m)^\s*ProcA\s*:\s*procedure'  'anon: procedure-of-object not split'
MustMatch    $o '(?m)^\s*FuncA, FuncB\s*:'       'anon: function type stays combined'
MustMatch    $o '(?m)^\s*NamedA\s*:\s*Integer'   'proc-fixture: Integer DOES split'
MustMatch    $o '(?m)^begin\b'                   'proc-fixture: routine begin at column 0'
MustNotMatch $o '(?m)^\s+begin\b'                'proc-fixture: begin not over-indented'
MustMatch    $o '(?m)^  NamedA\s*:\s*Integer'    'proc-fixture: split var at routine var depth'
MustMatch    $o '(?m)^end\.'                     'proc-fixture: unit end. at column 0'

if ($fail -eq 0) { Write-Output "format_regressions: PASS"; exit 0 }
else { Write-Output "format_regressions: $fail FAILED"; exit 1 }
