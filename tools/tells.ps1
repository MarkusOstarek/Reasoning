<#
  tells.ps1 - audit the scenario bank for surface tells.

  A player should only be able to identify the sound reading by reasoning about
  it. If the three statements differ systematically in length, structure or
  vocabulary, the game can be won by pattern-matching instead - which teaches
  the wrong skill and inflates scores.

  This measures how predictable a statement's role is from surface features
  alone. Report-only by default; -Strict exits nonzero when thresholds are
  breached, so it can gate the build once the bank is rewritten.

  Usage: tools\tells.ps1 [-Strict]
#>
[CmdletBinding()]
param(
  [switch]$Strict,
  # Share of scenarios where the longest statement may be the sound one.
  [double]$MaxLongestIsClean = 0.5,
  # Max spread within a trio: longest word count / shortest word count.
  [double]$MaxTrioSpread = 1.6,
  # Max gap in absolutist-marker rate between the highest and lowest role.
  [double]$MaxMarkerGap = 0.3
)

$ErrorActionPreference = "Stop"

$ROLES = @("flawed", "clean", "over")
$ABSOLUTIST = "\b(never|always|only|nothing|no one|nobody|anything|at all|worthless|meaningless|useless|pointless|zero|none|every|everyone|everything|all)\b"

$enc = New-Object System.Text.UTF8Encoding($false)
$jsonPath = Join-Path (Split-Path $PSScriptRoot -Parent) "src\scenarios.json"
$scenarios = ConvertFrom-Json ([IO.File]::ReadAllText($jsonPath, $enc))

function Get-WordCount([string]$t) { ($t -split '\s+' | Where-Object { $_ }).Count }

$rows = @()
foreach ($sc in $scenarios) {
  foreach ($st in $sc.statements) {
    $rows += [pscustomobject]@{
      id       = $sc.id
      role     = $st.role
      words    = Get-WordCount $st.t
      sentences= @([regex]::Matches($st.t, '[.!?](\s|$)')).Count
      absolute = [bool]($st.t -imatch $ABSOLUTIST)
      digits   = [bool]($st.t -imatch '\d')
      t        = $st.t
    }
  }
}

$n = @($scenarios).Count
$failures = @()

"SCENARIO BANK - TELL AUDIT   ($n scenarios, $($rows.Count) statements)"
""
"Length by role"
foreach ($r in $ROLES) {
  $g = @($rows | Where-Object { $_.role -eq $r })
  $m = $g.words | Measure-Object -Average -Minimum -Maximum
  "  {0,-7} avg {1,5:N1}w   range {2}-{3}w   multi-sentence {4}/{5}" -f `
    $r, $m.Average, $m.Minimum, $m.Maximum, @($g | Where-Object { $_.sentences -gt 1 }).Count, $g.Count
}
""

# The headline number: can you win by counting words?
$longestClean = 0
$spreadOffenders = @()
foreach ($sc in $scenarios) {
  $trio = @($sc.statements | ForEach-Object { [pscustomobject]@{ role = $_.role; w = Get-WordCount $_.t } })
  $ranked = @($trio | Sort-Object w -Descending)
  if ($ranked[0].role -eq "clean") { $longestClean++ }
  $spread = $ranked[0].w / [Math]::Max(1, $ranked[-1].w)
  if ($spread -gt $MaxTrioSpread) {
    $spreadOffenders += [pscustomobject]@{ id = $sc.id; spread = $spread; detail = (($ranked | ForEach-Object { "$($_.role)=$($_.w)w" }) -join " ") }
  }
}
$rateLongest = $longestClean / $n
$shortestOver = @($scenarios | Where-Object {
    (@($_.statements | Sort-Object { Get-WordCount $_.t })[0]).role -eq "over"
  }).Count
$rateShortest = $shortestOver / $n
"Heuristics a player could learn"
"  'pick the longest'      identifies the sound reading in {0}/{1} ({2:P0})" -f $longestClean, $n, $rateLongest
"  'shortest overshoots'   identifies the overshoot in    {0}/{1} ({2:P0})" -f $shortestOver, $n, $rateShortest
if ($rateLongest -gt $MaxLongestIsClean) {
  $failures += "'pick the longest' wins {0:P0} of the time (max {1:P0})" -f $rateLongest, $MaxLongestIsClean
}
if ($rateShortest -gt $MaxLongestIsClean) {
  $failures += "'shortest is the overshoot' wins {0:P0} of the time (max {1:P0})" -f $rateShortest, $MaxLongestIsClean
}

$sentRates = @{}
foreach ($r in $ROLES) {
  $g = @($rows | Where-Object { $_.role -eq $r })
  $sentRates[$r] = @($g | Where-Object { $_.sentences -gt 1 }).Count / $g.Count
}
$sentGap = ($sentRates.Values | Measure-Object -Maximum).Maximum - ($sentRates.Values | Measure-Object -Minimum).Minimum
"  sentence structure      " + (($ROLES | ForEach-Object { "{0}={1:P0}" -f $_, $sentRates[$_] }) -join "  ") + ("   gap {0:P0}" -f $sentGap)
if ($sentGap -gt $MaxMarkerGap) {
  $failures += "multi-sentence rate varies {0:P0} across roles (max {1:P0}) - sentence count predicts the role" -f $sentGap, $MaxMarkerGap
}

$markerRates = @{}
foreach ($r in $ROLES) {
  $g = @($rows | Where-Object { $_.role -eq $r })
  $markerRates[$r] = @($g | Where-Object { $_.absolute }).Count / $g.Count
}
$gap = ($markerRates.Values | Measure-Object -Maximum).Maximum - ($markerRates.Values | Measure-Object -Minimum).Minimum
"  absolutist vocabulary   " + (($ROLES | ForEach-Object { "{0}={1:P0}" -f $_, $markerRates[$_] }) -join "  ") + ("   gap {0:P0}" -f $gap)
if ($gap -gt $MaxMarkerGap) {
  $failures += "absolutist-marker rate varies {0:P0} across roles (max {1:P0}) - the marker predicts the role" -f $gap, $MaxMarkerGap
}
""

if ($spreadOffenders.Count) {
  "Trios too uneven in length (longest/shortest > $MaxTrioSpread)"
  foreach ($o in @($spreadOffenders | Sort-Object spread -Descending | Select-Object -First 12)) {
    "  {0,-20} {1,4:N1}x   {2}" -f $o.id, $o.spread, $o.detail
  }
  if ($spreadOffenders.Count -gt 12) { "  ... and $($spreadOffenders.Count - 12) more" }
  $failures += "$($spreadOffenders.Count)/$n trios exceed the length spread limit"
  ""
}

if ($failures.Count -eq 0) {
  "PASS - no surface feature reliably predicts a statement's role."
  exit 0
}

"FINDINGS"
foreach ($f in $failures) { "  - $f" }
""
if ($Strict) { [Console]::Error.WriteLine("TELL AUDIT FAILED: $($failures.Count) finding(s)"); exit 1 }
"(report-only; pass -Strict to make these fail)"
exit 0
