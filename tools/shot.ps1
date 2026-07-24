<#
  shot.ps1 - screenshot a local page at an arbitrary device viewport.

  Drives Chrome (or Edge) over the DevTools Protocol so the viewport is set with
  Emulation.setDeviceMetricsOverride. That matters: Chrome's --window-size is an
  OS window and Windows clamps it to ~485px, so --screenshot alone cannot render
  a 320px or 390px phone viewport. setDeviceMetricsOverride has no such floor.

  Needs nothing installed - Windows PowerShell 5.1 plus the browser already here.

  Examples:
    tools\shot.ps1 -Url index.html -Width 390 -Out shot.png
    tools\shot.ps1 -Url index.html -Width 320 -FullPage -Script "document.getElementById('btn-start').click()"
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Url,
  [string]$Out = "shot.png",
  [int]$Width = 390,
  [int]$Height = 844,
  [double]$Scale = 2,
  # JS evaluated after load, before capture. Use it to click into a view.
  [string]$Script = "",
  # Milliseconds to settle after $Script (animations, re-render).
  [int]$SettleMs = 400,
  [switch]$FullPage,
  [int]$Port = 9333
)

$ErrorActionPreference = "Stop"

function Resolve-Target([string]$u) {
  if ($u -match "^(https?|file|data):") { return $u }
  $p = Resolve-Path -LiteralPath $u
  return "file:///" + ($p.Path -replace "\\", "/")
}

$browser = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw "No Chrome or Edge found." }

$target = Resolve-Target $Url
$profileDir = Join-Path $env:TEMP ("shot-ps-" + $Port)
$token = [Threading.CancellationToken]::None
$proc = $null
$ws = $null

try {
  $proc = Start-Process $browser -PassThru -WindowStyle Hidden -ArgumentList @(
    "--headless", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
    "--no-first-run", "--no-default-browser-check", "--disable-extensions",
    "--remote-debugging-port=$Port", "--user-data-dir=`"$profileDir`"", "about:blank"
  )

  # The debugging port is not up the instant the process is.
  $wsUrl = $null
  foreach ($attempt in 1..60) {
    Start-Sleep -Milliseconds 250
    try {
      $targets = Invoke-RestMethod "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
      $page = @($targets | Where-Object { $_.type -eq "page" }) | Select-Object -First 1
      if ($page) { $wsUrl = $page.webSocketDebuggerUrl; break }
    } catch { }
  }
  if (-not $wsUrl) { throw "DevTools endpoint never came up on port $Port." }

  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $ws.ConnectAsync([Uri]$wsUrl, $token).Wait()

  $script:msgId = 0
  function Send-Cdp([string]$method, [hashtable]$prm) {
    $script:msgId++
    $payload = @{ id = $script:msgId; method = $method }
    if ($prm) { $payload.params = $prm }
    $json = $payload | ConvertTo-Json -Depth 10 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object System.ArraySegment[byte] (, $bytes)
    $ws.SendAsync($seg, [Net.WebSockets.WebSocketMessageType]::Text, $true, $token).Wait()

    # Responses are interleaved with events; read until our id comes back.
    $buf = New-Object byte[] 131072
    $rseg = New-Object System.ArraySegment[byte] (, $buf)
    while ($true) {
      $sb = New-Object System.Text.StringBuilder
      do {
        $r = $ws.ReceiveAsync($rseg, $token).GetAwaiter().GetResult()
        [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
      } while (-not $r.EndOfMessage)
      $text = $sb.ToString()
      # Regex, not ConvertFrom-Json: a full-page PNG is megabytes of base64 and
      # 5.1's JSON parser chokes well before that.
      if ($text -match "^\{`"id`":$($script:msgId)[,}]") { return $text }
    }
  }

  function Eval-Js([string]$expr) {
    $res = Send-Cdp "Runtime.evaluate" @{ expression = $expr; returnByValue = $true }
    if ($res -match '"exceptionDetails"') { throw "JS failed: $expr" }
    return $res
  }

  [void](Send-Cdp "Page.enable" $null)
  [void](Send-Cdp "Emulation.setDeviceMetricsOverride" @{
      width = $Width; height = $Height; deviceScaleFactor = $Scale; mobile = $true
    })
  [void](Send-Cdp "Page.navigate" @{ url = $target })

  $ready = $false
  foreach ($attempt in 1..80) {
    Start-Sleep -Milliseconds 125
    if ((Eval-Js "document.readyState") -match '"value":"complete"') { $ready = $true; break }
  }
  if (-not $ready) { throw "Page never reached readyState=complete: $target" }

  if ($Script) { [void](Eval-Js $Script) }
  Start-Sleep -Milliseconds $SettleMs

  $shotArgs = @{ format = "png" }
  if ($FullPage) { $shotArgs.captureBeyondViewport = $true }
  $res = Send-Cdp "Page.captureScreenshot" $shotArgs

  $m = [regex]::Match($res, '"data":"([A-Za-z0-9+/=]+)"')
  if (-not $m.Success) { throw "No image data in captureScreenshot response." }
  $png = [Convert]::FromBase64String($m.Groups[1].Value)

  $outPath = $Out
  if (-not [IO.Path]::IsPathRooted($outPath)) { $outPath = Join-Path (Get-Location) $outPath }
  [IO.File]::WriteAllBytes($outPath, $png)

  $dims = Eval-Js "document.documentElement.clientWidth + 'x' + document.documentElement.scrollWidth"
  $d = [regex]::Match($dims, '"value":"(\d+)x(\d+)"')
  $overflow = ""
  if ($d.Success -and [int]$d.Groups[2].Value -gt [int]$d.Groups[1].Value) {
    $overflow = "  WARNING: content overflows horizontally (scrollWidth $($d.Groups[2].Value) > viewport $($d.Groups[1].Value))"
  }
  Write-Host "$outPath  ${Width}x${Height} @${Scale}x  $($png.Length) bytes$overflow"
}
finally {
  if ($ws) { try { $ws.Dispose() } catch { } }
  if ($proc) { try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { } }
}
