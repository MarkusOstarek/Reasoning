<#
  Reason Check build script — PowerShell port of build.js.

  Same contract as build.js: validates src/scenarios.json against the schema,
  runs the topic-balance audit, injects the bank into src/template.html, and
  writes:
    - index.html   (full standalone document, deployable anywhere)
    - preview.html (body-only content, for claude.ai artifact previews)

  Byte-for-byte identical output to `node build.js`. Runs on the Windows
  PowerShell 5.1 that ships with Windows — no runtime to install.

  Usage: powershell -ExecutionPolicy Bypass -File build.ps1
#>

$ErrorActionPreference = "Stop"

$ROOT = $PSScriptRoot
$FAMILIES = @("causation", "posthoc", "baserates", "anecdotes", "numbers", "echo")
$VALENCES = @("leans-left", "leans-right", "neutral")
$STATUSES = @("draft", "playtested", "validated")
$ROLES = @("flawed", "clean", "over")
$MIN_PER_FAMILY = 2 # the app draws 2 per family per session

function Fail($msg) {
  [Console]::Error.WriteLine("BUILD FAILED: " + $msg)
  exit 1
}

# UTF-8 without BOM, LF endings preserved — matches what Node writes.
$UTF8 = New-Object System.Text.UTF8Encoding($false)
function Read-Text($p) { [System.IO.File]::ReadAllText($p, $UTF8) }
function Write-Text($p, $text) { [System.IO.File]::WriteAllText($p, $text, $UTF8) }

$scenariosRaw = Read-Text (Join-Path $ROOT "src\scenarios.json")
# ConvertFrom-Json emits the top-level array as a single object, so an @()
# wrapper around the pipeline would nest it one level deep instead of flattening.
try { $scenarios = ConvertFrom-Json $scenariosRaw }
catch { Fail "src/scenarios.json is not valid JSON: $($_.Exception.Message)" }
if ($scenarios -isnot [System.Array]) { $scenarios = , $scenarios }

<# ---------- Schema validation ---------- #>
$ids = New-Object System.Collections.Generic.HashSet[string]
for ($i = 0; $i -lt $scenarios.Count; $i++) {
  $s = $scenarios[$i]
  $idLabel = $s.id
  if (-not $idLabel) { $idLabel = "no id" }
  $where = "scenario $i ($idLabel)"
  if (-not $s.id -or -not $ids.Add([string]$s.id)) { Fail "${where}: missing or duplicate id" }
  if ($FAMILIES -notcontains $s.family) { Fail "${where}: unknown family `"$($s.family)`"" }
  if ($VALENCES -notcontains $s.valence) { Fail "${where}: unknown valence `"$($s.valence)`"" }
  if ($STATUSES -notcontains $s.status) { Fail "${where}: unknown status `"$($s.status)`"" }
  if (-not $s.context -or -not $s.question) { Fail "${where}: missing context or question" }
  if (-not ($s.body -is [array]) -or $s.body.Count -lt 1) { Fail "${where}: body must be a non-empty array" }
  if (-not ($s.statements -is [array]) -or $s.statements.Count -ne 3) { Fail "${where}: needs exactly 3 statements" }
  # Not $roles — PowerShell variable names are case-insensitive, so that would
  # silently overwrite the $ROLES constant and compare the value against itself.
  $stmtRoles = @($s.statements | ForEach-Object { $_.role } | Sort-Object)
  if (($stmtRoles -join ",") -ne (($ROLES | Sort-Object) -join ",")) { Fail "${where}: statements must be one each of $($ROLES -join '/')" }
  foreach ($st in $s.statements) { if (-not $st.t) { Fail "${where}: statement missing text" } }
  if (-not $s.explain -or -not $s.explain.tempting -or -not $s.explain.clean -or -not $s.explain.rule) { Fail "${where}: explain needs tempting/clean/rule" }
  if (-not ($s.sources -is [array]) -or $s.sources.Count -lt 1) { Fail "${where}: needs at least 1 source" }
  foreach ($src in $s.sources) {
    if (-not $src.label -or -not $src.url -or $src.url -notmatch "^https?://") { Fail "${where}: each source needs a label and an http(s) url" }
  }
}

<# ---------- Coverage check ---------- #>
$perFamily = @{}
foreach ($f in $FAMILIES) { $perFamily[$f] = @($scenarios | Where-Object { $_.family -eq $f }).Count }
foreach ($f in $FAMILIES) {
  if ($perFamily[$f] -lt $MIN_PER_FAMILY) { Fail "family `"$f`" has $($perFamily[$f]) scenarios; needs at least $MIN_PER_FAMILY" }
}

<# ---------- Topic-balance audit ----------
   The flawed reading of each scenario flatters somebody's priors. The bank
   must never skew toward correcting one worldview more than the other. #>
$byValence = @{}
foreach ($v in $VALENCES) { $byValence[$v] = @($scenarios | Where-Object { $_.valence -eq $v }).Count }
$skew = [Math]::Abs($byValence["leans-left"] - $byValence["leans-right"])
if ($skew -gt 1) { Fail "balance audit: leans-left=$($byValence['leans-left']) vs leans-right=$($byValence['leans-right']) (skew $skew > 1)" }

<# ---------- Inject & write ---------- #>

# Strips insignificant whitespace outside strings. Reproduces Node's
# JSON.stringify(bank, null, 0) exactly, without round-tripping the data
# through PowerShell's JSON writer (5.1's ConvertTo-Json mangles non-ASCII).
function Compress-Json([string]$text) {
  $sb = New-Object System.Text.StringBuilder
  $inString = $false
  $escaped = $false
  foreach ($ch in $text.ToCharArray()) {
    if ($inString) {
      [void]$sb.Append($ch)
      if ($escaped) { $escaped = $false }
      elseif ($ch -eq '\') { $escaped = $true }
      elseif ($ch -eq '"') { $inString = $false }
    }
    elseif ($ch -eq '"') { $inString = $true; [void]$sb.Append($ch) }
    elseif ($ch -eq ' ' -or $ch -eq "`t" -or $ch -eq "`n" -or $ch -eq "`r") { }
    else { [void]$sb.Append($ch) }
  }
  $sb.ToString()
}

$bank = Compress-Json $scenariosRaw
# The bank is injected into an inline <script>; this sequence would close it early.
if ($bank -match "(?i)</script") { Fail "a scenario contains the literal text '</script', which would break the inline script tag" }

$template = Read-Text (Join-Path $ROOT "src\template.html")
$slot = $template.IndexOf("__SCENARIOS__")
if ($slot -lt 0) { Fail "template.html is missing the __SCENARIOS__ placeholder" }
# Index splice, not -replace: the bank is data and must never be read as a regex
# pattern or as a replacement string with $-substitutions.
$body = $template.Substring(0, $slot) + $bank + $template.Substring($slot + "__SCENARIOS__".Length)

# Webfonts only in the deployed page; preview.html (artifact) has a strict CSP
# and falls back to the designed system stacks.
$fonts =
  '<link rel="preconnect" href="https://fonts.googleapis.com">' + "`n" +
  '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' + "`n" +
  '<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,500..800;1,9..144,500..800&family=Libre+Franklin:wght@400;600;700;800&display=swap" rel="stylesheet">' + "`n"

$SITE_URL = "https://markusostarek.github.io/Reasoning/"

# Hoist the template's <title> into <head> for the deployed page.
$titleMatch = [regex]::Match($body, "^<title>.*?</title>\s*")
if ($titleMatch.Success) {
  $title = $titleMatch.Value.Trim()
  $pageBody = $body.Substring($titleMatch.Length)
} else {
  $title = "<title>Reason Check</title>"
  $pageBody = $body
}

$meta =
  $title + "`n" +
  '<meta name="description" content="Twelve everyday scenarios — a chart at a family dinner, a viral post, a pile of reviews. Rate what the evidence supports and get a profile of your reasoning blind spots. Free, private, ten minutes.">' + "`n" +
  '<link rel="canonical" href="' + $SITE_URL + '">' + "`n" +
  '<meta property="og:title" content="Reason Check — what would you conclude?">' + "`n" +
  '<meta property="og:description" content="Twelve everyday scenarios. Rate what the evidence supports, find your reasoning blind spots. Plus a scenario of the day.">' + "`n" +
  '<meta property="og:url" content="' + $SITE_URL + '">' + "`n" +
  '<meta property="og:type" content="website">' + "`n" +
  '<meta property="og:image" content="' + $SITE_URL + 'og.png">' + "`n" +
  '<meta property="og:image:width" content="1200">' + "`n" +
  '<meta property="og:image:height" content="630">' + "`n" +
  '<meta name="twitter:card" content="summary_large_image">' + "`n" +
  '<meta name="theme-color" content="#1b2440">' + "`n" +
  '<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🧭</text></svg>">' + "`n"

$page =
  '<!doctype html>' + "`n" + '<html lang="en">' + "`n" + '<head>' + "`n" + '<meta charset="utf-8">' + "`n" +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' + "`n" +
  $meta + $fonts +
  "</head>`n<body>`n" + $pageBody + "`n</body>`n</html>`n"

Write-Text (Join-Path $ROOT "index.html") $page
Write-Text (Join-Path $ROOT "preview.html") $body

Write-Host "OK: $($scenarios.Count) scenarios ($(($FAMILIES | ForEach-Object { $_ + ':' + $perFamily[$_] }) -join ', '))"
Write-Host "Balance: leans-left=$($byValence['leans-left']), leans-right=$($byValence['leans-right']), neutral=$($byValence['neutral'])"
Write-Host "Wrote index.html and preview.html"
