$ErrorActionPreference = 'Stop'
$output = Join-Path $PSScriptRoot '..\build\diagnostics\selection_ranges'
$names = 'A_short_single_line','B_multiline_same_paragraph','C_repeat_A','D_partial_overlap_end','E_inside_A','F_contains_A','G_adjacent_A','H_cross_paragraph','I_other_xhtml_resource'
$lines = @('# Sanitized Readium selection-range analysis','')
foreach ($name in $names) {
  $file = Join-Path $output "$name.log"
  if (-not (Test-Path $file)) { $lines += "- ${name}: missing"; continue }
  $entries = Get-Content -LiteralPath $file
  $structure = $entries | Where-Object { $_ -match 'LOCATOR_STRUCTURE' } | Select-Object -First 1
  $fragments = @($entries | Where-Object { $_ -match 'SELECTION_FRAGMENT' })
  $parse = $entries | Where-Object { $_ -match 'RANGE_PARSE' } | Select-Object -First 1
  $lines += "- ${name}: structure=$([bool]$structure), fragments=$($fragments.Count), parse=$([bool]$parse)"
}
$lines += ''; $lines += 'Compare A/C by fragment hashes; compare A/D/E/F/G/H/I only when both scenarios are captured. Raw locator values and publication content are intentionally excluded.'
$lines | Set-Content -LiteralPath (Join-Path $output 'analysis.md') -Encoding utf8
