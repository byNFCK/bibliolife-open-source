param([string[]]$Scenario, [switch]$Overwrite, [string]$Adb = 'adb')

$ErrorActionPreference = 'Stop'

$package = 'app.bibliolife.reader'
$output = Join-Path $PSScriptRoot '..\build\diagnostics\selection_ranges'
$scenarios = [ordered]@{
  A_short_single_line = 'Select a short single-line phrase.'
  B_multiline_same_paragraph = 'Select text spanning multiple lines in one paragraph.'
  C_repeat_A = 'Repeat scenario A as closely as possible.'
  D_partial_overlap_end = 'Select a range overlapping the end of A.'
  E_inside_A = 'Select a range fully inside A.'
  F_contains_A = 'Select a range fully containing A.'
  G_adjacent_A = 'Select directly adjacent text, without overlap.'
  H_cross_paragraph = 'Select across a paragraph boundary.'
  I_other_xhtml_resource = 'Select text in another chapter/resource.'
}
if (-not (Get-Command $Adb -ErrorAction SilentlyContinue)) { throw 'adb was not found; pass -Adb or add Android platform-tools to PATH.' }
if (-not ((& $adb devices) -match '\sdevice$')) { throw 'No connected Android device.' }
if (-not ((& $adb shell pm path $package 2>$null) -match 'package:')) { throw 'BiblioLife is not installed.' }
New-Item -ItemType Directory -Force -Path $output | Out-Null

$allowed = 'READIUM_SELECTION_(LOCATOR_STRUCTURE|FRAGMENT|RANGE_PARSE|OTHER_LOCATIONS|OTHER_LOCATION_ENTRY|LOCATOR_TEXT|POSITION_FINGERPRINT)'
$forbidden = 'locatorJson|selectedText|textBefore|textAfter|\bnote\b|epubcfi\(|title=|\bhref='
$chosen = if ($Scenario) { $Scenario } else { $scenarios.Keys }
$manifest = @()
foreach ($name in $chosen) {
  if (-not $scenarios.Contains($name)) { throw "Unknown scenario: $name" }
  $file = Join-Path $output "$name.log"
  if ((Test-Path $file) -and -not $Overwrite) { Write-Host "$name already captured; use -Overwrite to replace."; continue }
  do {
    & $adb logcat -c
    Write-Host "[$name] $($scenarios[$name])"
    $action = Read-Host 'Create the selection, then Enter. Type r to retry, s to skip, q to abort'
  } while ($action -eq 'r')
  if ($action -eq 'q') { break }
  if ($action -eq 's') { $manifest += [ordered]@{scenario=$name;capturedAt=(Get-Date).ToUniversalTime().ToString('o');status='skipped';markerCounts=@{}}; continue }
  $raw = & $adb logcat -d
  $safe = @($raw | Where-Object { $_ -match $allowed -and $_ -notmatch $forbidden -and $_.Length -le 1000 })
  $safe | Set-Content -LiteralPath $file -Encoding utf8
  $structure = @($safe | Where-Object {$_ -match 'LOCATOR_STRUCTURE'}).Count
  $fragment = @($safe | Where-Object {$_ -match 'SELECTION_FRAGMENT'}).Count
  $parse = @($safe | Where-Object {$_ -match 'RANGE_PARSE'}).Count
  $status = if ($structure -eq 0) { 'missing' } elseif ($parse -eq 0) { 'partial' } else { 'captured' }
  Write-Host "${name}: structure=$structure fragments=$fragment rangeParse=$parse status=$status"
  $manifest += [ordered]@{scenario=$name;capturedAt=(Get-Date).ToUniversalTime().ToString('o');status=$status;markerCounts=@{total=$safe.Count;structure=$structure;fragment=$fragment;parse=$parse}}
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
