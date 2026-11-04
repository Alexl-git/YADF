# Online-help tree (docs\help-site): every index.json entry has its file, every
# leaf is indexed, every relative link resolves, and the tree is exactly what the
# generator produces from the option table (so a leaf summary can never differ
# from the Hint shown in YADFSetup / the IDE page, and a new option without a
# leaf fails here). Exit 0 = all pass, 1 = any fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'help_site' $exe
$site = Join-Path $PSScriptRoot '..\docs\help-site'

$idx = Get-Content (Join-Path $site 'index.json') -Raw | ConvertFrom-Json
$gids = @($idx.groups | ForEach-Object { $_.id })
foreach ($o in $idx.options) {
  $f = Join-Path $site $o.file
  if (-not (Test-Path $f)) { Fail "index entry $($o.id): missing file $($o.file)"; continue }
  $t = [IO.File]::ReadAllText($f)
  if ($t -notmatch "(?m)^id: $([regex]::Escape($o.id))\s*$") { Fail "$($o.file): front matter id != $($o.id)" }
  if ([regex]::Matches($t, '(?m)^id: ').Count -ne 1) { Fail "$($o.file): front matter repeated (gen_help_site stacked it)" }
  if ($t -notmatch "(?m)^summary: $([regex]::Escape($o.summary))\s*$") { Fail "$($o.file): summary differs from index.json" }
  if ($o.group -notin $gids) { Fail "$($o.id): group $($o.group) not in groups list" }
  if ($o.id -notmatch '^[a-z0-9-]{1,60}$') { Fail "$($o.id): bad slug" }
}
$ids = @($idx.options | ForEach-Object { $_.id })
foreach ($f in Get-ChildItem (Join-Path $site 'options') -Filter '*.md') {
  if ($f.BaseName -notin $ids) { Fail "$($f.Name): leaf not in index.json" }
  $t = [IO.File]::ReadAllText($f.FullName)
  if ($t -match '[^\x00-\x7F]') { Fail "$($f.Name): non-ASCII" }
  foreach ($m in [regex]::Matches($t, '\]\(([^)\s]+)\)')) {
    $l = $m.Groups[1].Value
    if ($l -match '^(https?:|#|mailto:)') { continue }
    if ($l -match '^(/|\\)|^\w+:') { Fail "$($f.Name): link not relative: $l"; continue }
    if (-not (Test-Path (Join-Path $f.DirectoryName ($l -replace '#.*$', '')))) { Fail "$($f.Name): dead link $l" }
  }
}

# Regenerate into a copy: must be a no-op against the committed tree.
$tmp = Join-Path $env:TEMP ('yadf_help_' + [guid]::NewGuid().ToString('N'))
Copy-Item $site $tmp -Recurse
try {
  & (Join-Path $PSScriptRoot 'gen_help_site.ps1') -OutDir $tmp | Out-Null
  foreach ($f in Get-ChildItem $tmp -Recurse -File) {
    $rel = $f.FullName.Substring($tmp.Length)
    $orig = Join-Path $site $rel
    if (-not (Test-Path $orig)) { Fail "generator would add $rel (run Test\gen_help_site.ps1)"; continue }
    if (-not (SameBytes $f.FullName $orig)) { Fail "generator would change $rel (hint/default drift; run Test\gen_help_site.ps1)" }
  }
} finally { [IO.Directory]::Delete($tmp, $true) }
Finish 'help_site'
