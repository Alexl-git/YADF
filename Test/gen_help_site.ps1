# Generates docs\help-site from the option table (YADF.Options.pas OptionTable),
# the compiled-in defaults (YADF.exe writes them to a fresh INI) and the long
# descriptions in yadf.ini. Re-runnable: front matter of table-driven leaves is
# refreshed, an existing body is KEPT (hand edits survive); a missing leaf is
# created with a body built from the yadf.ini comment. Leaves with
# "manual: true" in their front matter are never touched, only indexed.
# index.json is rebuilt from the front matter of every options\*.md leaf.
param([string]$OutDir, [string]$Since)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$out  = if ($OutDir) { $OutDir } else { Join-Path $root 'docs\help-site' }
$optDir = Join-Path $out 'options'
New-Item -ItemType Directory -Force $optDir | Out-Null
$enc = New-Object System.Text.UTF8Encoding($false)
# `since` of a NEW leaf = the current family version (YADF.Version.inc) unless -Since is
# given (e.g. the next, unreleased version). Existing leaves keep the value they carry.
if (-not $Since) { $Since = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'YADF.Version.inc')), "YADF_VERSION\s*=\s*'([\d.]+)'").Groups[1].Value }
if (-not $Since) { throw 'cannot read YADF_VERSION from YADF.Version.inc' }

function Write-Ascii([string]$p, [string]$text) {
  if ($text -match '[^\x00-\x7F]') { throw "non-ASCII text for $p" }
  [IO.File]::WriteAllText($p, ($text -replace "`r`n", "`n"), $enc)
}

# ---- 1. parse the option table --------------------------------------------
$src = [IO.File]::ReadAllText((Join-Path $root 'YADF.Options.pas'))
$lit = "(?:'(?:[^']|'')*'\s*(?://[^\r\n]*)?\s*\+?\s*)+"
$rx  = "MakeOpt\('(\w+)',\s*'([^']*)',\s*'([^']*)',\s*($lit),\s*ok(\w+)"
$opts = @()
foreach ($m in [regex]::Matches($src, $rx)) {
  $hint = ([regex]::Matches($m.Groups[4].Value, "'((?:[^']|'')*)'") | ForEach-Object { $_.Groups[1].Value -replace "''", "'" }) -join ''
  $opts += [pscustomobject]@{ Ident = $m.Groups[1].Value; Group = $m.Groups[2].Value
    Caption = $m.Groups[3].Value; Hint = $hint; Kind = $m.Groups[5].Value }
}
if ($opts.Count -lt 40) { throw "option table parse found only $($opts.Count) options" }

# ---- 2. compiled-in defaults via a freshly written INI ---------------------
$exe = if ($env:YADF_TEST_EXE) { $env:YADF_TEST_EXE } else { Join-Path $root 'Win64\Debug\EXE\YADF.exe' }
$tmp = Join-Path $env:TEMP ('gen_help_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp | Out-Null
$ini0 = Join-Path $tmp 'default.ini'; $pas0 = Join-Path $tmp 'a.pas'
[IO.File]::WriteAllText($pas0, "unit A;`r`ninterface`r`nimplementation`r`nend.`r`n")
& $exe --ini $ini0 --stdout $pas0 *> $null
$def = @{}
foreach ($l in [IO.File]::ReadAllLines($ini0)) { if ($l -match '^(\w+)\s*=\s*(.*)$') { $def[$Matches[1]] = $Matches[2].Trim() } }

# ---- 3. long descriptions from the commented yadf.ini ----------------------
$desc = @{}; $cur = $null; $buf = @()
foreach ($l in [IO.File]::ReadAllLines((Join-Path $root 'yadf.ini'))) {
  if ($l -match '^; (\w+)\s*$') { $cur = $Matches[1]; $buf = @(); continue }
  if ($cur -and $l -match '^;( {3}(.*)|)$') { $buf += ($(if ($Matches[2] -ne $null) { $Matches[2] } else { '' })); continue }
  if ($cur -and $l -match '^(\w+)=') { $desc[$cur] = ($buf -join "`n").Trim(); $cur = $null; continue }
  if ($cur -and $l -notmatch '^;') { $cur = $null }
}

# ---- 4. ids, groups, CLI flags ---------------------------------------------
function Get-Kebab([string]$s) { ($s -creplace '([a-z0-9])([A-Z])', '$1-$2').ToLower() }
$groupMap = [ordered]@{}
$grpIdFix = @{ 'Line length & indentation' = 'line-layout' }
$mainSrc  = [IO.File]::ReadAllText((Join-Path $root 'YadfMain.pas'))
$perGroup = @{}
# Ident -> flag, parsed from the ParseFlags table (BoolFlag/IntFlag/BodyFlag rows) plus the hand-coded path flags.
$flagMap = @{ Backup = '--b'; BackupDir = '--b'; ResultDir = '--of'; PackShortBodies = '--pack-bodies' }
foreach ($m in [regex]::Matches($mainSrc, "(?:Bool|Int|Body)Flag\('(--[a-z0-9-]+)'.*?AOpts\.(\w+)[,)]")) { $flagMap[$m.Groups[2].Value] = $m.Groups[1].Value }
foreach ($o in $opts) {
  if (-not $groupMap.Contains($o.Group)) { $groupMap[$o.Group] = $groupMap.Count + 1 }
  $o | Add-Member id (Get-Kebab $o.Ident)
  $o | Add-Member gid $(if ($grpIdFix.ContainsKey($o.Group)) { $grpIdFix[$o.Group] } else { (($o.Group.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')) })
  if (-not $perGroup.ContainsKey($o.gid)) { $perGroup[$o.gid] = @() }
  $perGroup[$o.gid] += $o
  $flag = '--' + $o.id
  if ($flagMap.ContainsKey($o.Ident)) { $flag = $flagMap[$o.Ident] }
  $o | Add-Member cli $(if ($mainSrc.Contains("'$flag'")) { $flag } else { '' })
}

# ---- 5. write / refresh the leaves -----------------------------------------
$groupsSeen = @{}
foreach ($o in $opts) {
  $gOrder = $groupMap[$o.Group] * 10
  $groupsSeen[$o.gid] = [pscustomobject]@{ id = $o.gid; title = $o.Group; order = $gOrder }
  $sibs = @($perGroup[$o.gid] | Where-Object { $_.id -ne $o.id } | Select-Object -First 3)
  $order = 10 * (1 + [array]::IndexOf(@($perGroup[$o.gid]), $o))
  $d = if ($def.ContainsKey($o.Ident)) { $def[$o.Ident] } else { '' }
  $fm = "---`nid: $($o.id)`ntitle: $($o.Caption)`nsummary: $($o.Hint)`ngroup: $($o.gid)`norder: $order`n" +
        "default: `"$d`"`nini: $($o.Ident)`n" + $(if ($o.cli) { "cli: $($o.cli)`n" } else { '' }) +
        "since: `"$Since`"`nstatus: `"stable`"`n---`n"
  $p = Join-Path $optDir ($o.id + '.md')
  $body = $null
  if (Test-Path $p) {
    $old = [IO.File]::ReadAllText($p)
    if ($old -match '(?m)^manual: true') { continue }
    $sinceKeep = [regex]::Match($old, '(?m)^since: ("[^"]*")').Groups[1].Value
    if ($sinceKeep) { $fm = $fm -replace ('since: "' + [regex]::Escape($Since) + '"'), "since: $sinceKeep" }
    $body = $old.Substring($old.IndexOf("`n---`n", 4) + 5)
  } else {
    $long = if ($desc.ContainsKey($o.Ident)) { $desc[$o.Ident] } else { $o.Hint }
    $body = "`n# $($o.Caption)`n`n$long`n"
    if ($sibs.Count) { $body += "`n## Related`n`n" + (($sibs | ForEach-Object { "- [$($_.Caption)]($($_.id).md) - $($_.Hint)" }) -join "`n") + "`n" }
  }
  Write-Ascii $p ($fm + $body)
}

# ---- 6. index.json from all leaf front matter ------------------------------
$items = @()
foreach ($f in Get-ChildItem $optDir -Filter '*.md') {
  $t = [IO.File]::ReadAllText($f.FullName)
  $fmText = [regex]::Match($t, '(?s)\A---\n(.*?)\n---\n').Groups[1].Value
  $h = @{}
  foreach ($l in $fmText -split "`n") { if ($l -match '^(\w+):\s*(.*)$') { $h[$Matches[1]] = $Matches[2].Trim().Trim('"') } }
  $items += [pscustomobject][ordered]@{ id = $h.id; title = $h.title; summary = $h.summary; group = $h.group
    order = [int]$h.order; since = $h.since; file = 'options/' + $f.Name }
  if (-not $groupsSeen.ContainsKey($h.group)) {
    $gt = if ($h.groupTitle) { $h.groupTitle } else { $h.group }
    $groupsSeen[$h.group] = [pscustomobject]@{ id = $h.group; title = $gt; order = 900 }
  }
}
$items = $items | Sort-Object { $groupsSeen[$_.group].order }, order, id
$groups = $groupsSeen.Values | Sort-Object order, id
# Hand-rolled JSON: ConvertTo-Json formats differently in Windows PowerShell 5 and pwsh 7.
function J([object]$v) { if ($v -is [int]) { "$v" } else { '"' + (([string]$v) -replace '\\', '\\' -replace '"', '\"') + '"' } }
function JObj($o) { '{' + (($o.PSObject.Properties | ForEach-Object { (J $_.Name) + ': ' + (J $_.Value) }) -join ', ') + '}' }
$json = "{`n  `"product`": `"yadf`",`n  `"groups`": [`n    " + (($groups | ForEach-Object { JObj $_ }) -join ",`n    ") +
        "`n  ],`n  `"options`": [`n    " + (($items | ForEach-Object { JObj $_ }) -join ",`n    ") + "`n  ]`n}`n"
Write-Ascii (Join-Path $out 'index.json') $json
[IO.Directory]::Delete($tmp, $true)
Write-Host "help-site: $($opts.Count) table options, $($items.Count) leaves indexed"
