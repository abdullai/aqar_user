# Web diagnostic script for Aqar hosting / Supabase / FCM checks.
# Usage: .\scripts\diagnose-web.ps1
#        .\scripts\diagnose-web.ps1 -SiteUrl "https://eaqar-mawthuq.web.app"

param(
  [string]$SiteUrl = "https://eaqar-mawthuq.web.app"
)

$ErrorActionPreference = "Continue"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Write-Result($label, $ok, $detail) {
  $icon = if ($ok) { "[OK]" } else { "[!!]" }
  Write-Host "$icon $label - $detail"
}

Write-Host ""
Write-Host "=== Aqar Web Diagnostic ===" -ForegroundColor Cyan
Write-Host "Site: $SiteUrl"
Write-Host ""

# 1) Build output
$mainJs = Join-Path $root "build\web\main.dart.js"
$swJs = Join-Path $root "build\web\firebase-messaging-sw.js"
if (Test-Path $mainJs) {
  Write-Result "Local build/web/main.dart.js" $true "exists"
} else {
  Write-Result "Local build/web/main.dart.js" $false "MISSING - run: flutter build web --release --no-wasm-dry-run"
}
if (Test-Path $swJs) {
  Write-Result "Local firebase-messaging-sw.js" $true "exists"
} else {
  Write-Result "Local firebase-messaging-sw.js" $false "MISSING - copy from web/ folder"
}

# 2) Service worker served as JS (not index.html)
try {
  $swResp = Invoke-WebRequest -Uri "$SiteUrl/firebase-messaging-sw.js" -UseBasicParsing -TimeoutSec 20
  $contentType = $swResp.Headers["Content-Type"]
  $swOk = ($contentType -match "javascript") -and ($swResp.Content -match "firebase")
  Write-Result "Hosted firebase-messaging-sw.js" $swOk "HTTP $($swResp.StatusCode), type=$contentType"
  if (-not $swOk) {
    Write-Host "    -> SW returns HTML or wrong content (FCM disabled on web in latest build)" -ForegroundColor Yellow
  }
} catch {
  Write-Result "Hosted firebase-messaging-sw.js" $false $_.Exception.Message
}

# 3) Supabase config
try {
  $cfgResp = Invoke-WebRequest -Uri "$SiteUrl/supabase_config.json" -UseBasicParsing -TimeoutSec 20
  $cfg = $cfgResp.Content | ConvertFrom-Json
  $url = $cfg.SUPABASE_URL
  if (-not $url) { $url = $cfg.url }
  $key = $cfg.SUPABASE_ANON_KEY
  if (-not $key) { $key = $cfg.anonKey }
  $hasUrl = [bool]$url
  $hasKey = [bool]$key
  Write-Result "supabase_config.json" ($hasUrl -and $hasKey) "url=$hasUrl anonKey=$hasKey"
} catch {
  Write-Result "supabase_config.json" $false $_.Exception.Message
}

# 4) Home feed anon REST (public properties)
$cfgPath = Join-Path $root "web\supabase_config.json"
if (-not (Test-Path $cfgPath)) {
  $cfgPath = Join-Path $root "build\web\supabase_config.json"
}
if (Test-Path $cfgPath) {
  try {
    $localCfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
    $base = $localCfg.SUPABASE_URL
    if (-not $base) { $base = $localCfg.url }
    $key = $localCfg.SUPABASE_ANON_KEY
    if (-not $key) { $key = $localCfg.anonKey }
    $base = ($base -replace '/+$', '')
    $headers = @{
      apikey = $key
      Accept = "application/json"
    }
    $uri = "$base/rest/v1/properties?select=id&status=neq.deleted&limit=3"
    $props = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 25
    $count = @($props).Count
    $propsOk = $count -gt 0
    Write-Result "Supabase public properties" $propsOk "sample count=$count (0 means empty DB or RLS blocks anon)"
  } catch {
    Write-Result "Supabase public properties" $false $_.Exception.Message
  }
} else {
  Write-Result "Supabase public properties" $false "no local supabase_config.json"
}

# 5) Flutter bootstrap
try {
  $boot = Invoke-WebRequest -Uri "$SiteUrl/flutter_bootstrap.js" -UseBasicParsing -TimeoutSec 20
  Write-Result "flutter_bootstrap.js" ($boot.StatusCode -eq 200) "HTTP $($boot.StatusCode)"
} catch {
  Write-Result "flutter_bootstrap.js" $false $_.Exception.Message
}

Write-Host ""
Write-Host "=== Console checklist (after open site) ===" -ForegroundColor Cyan
Write-Host 'Filter Console: AqarWebDiag'
Write-Host ""
Write-Host 'GUEST OK:'
Write-Host '  start_router - open WebDashboardShell'
Write-Host '  dashboard.shell - ui=WebGuestDashboard'
Write-Host '  guest.dashboard - init lightweight guest UI'
Write-Host '  OK guest.feed items=N'
Write-Host ""
Write-Host 'USER OK:'
Write-Host '  dashboard.shell - ui=UserDashboard'
Write-Host '  start initial_load.home then OK initial_load.home rows=N'
Write-Host '  start initial_load.market then OK initial_load.market'
Write-Host '  initial_load - staggered path complete'
Write-Host ""
Write-Host 'PROBLEMS:'
Write-Host '  initial_load.home as GUEST = wrong path - heavy UserDashboard'
Write-Host '  FREEZE? = phase stuck / UI may be frozen'
Write-Host '  otp.request not_authenticated = session lost before OTP'
Write-Host '  rows=0 + empty UI = DB/RLS/empty data - not UI freeze'
Write-Host '  slow.frame alone = jank - not necessarily freeze'
Write-Host ""
Write-Host "=== Deploy ===" -ForegroundColor Cyan
Write-Host 'Full pipeline: .\scripts\deploy-web.ps1'
Write-Host 'Diag only:     .\scripts\diagnose-web.ps1'
Write-Host ""
