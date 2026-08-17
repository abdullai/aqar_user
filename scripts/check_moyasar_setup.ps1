# Moyasar setup check (read-only)
# Usage: powershell -File scripts/check_moyasar_setup.ps1

$ErrorActionPreference = "Continue"
$hostUrl = "https://eaqar-mawthuq.web.app"

Write-Host "=== 1) Deployed supabase_config.json ===" -ForegroundColor Cyan
$localCfgPath = Join-Path (Split-Path $PSScriptRoot -Parent) "web\supabase_config.json"
try {
  $cfg = Invoke-RestMethod -Uri "$hostUrl/supabase_config.json" -TimeoutSec 45
  $source = "remote"
} catch {
  Write-Host "  Remote read timed out or failed — checking local web\supabase_config.json" -ForegroundColor Yellow
  if (Test-Path $localCfgPath) {
    $cfg = Get-Content $localCfgPath -Raw | ConvertFrom-Json
    $source = "local (rebuild+deploy if remote differs)"
  } else {
    throw $_
  }
}
try {
  $pk = "$($cfg.MOYASAR_PUBLISHABLE_KEY)"
  $cb = "$($cfg.MOYASAR_CALLBACK_URL)"
  if ($pk.StartsWith("pk_test_")) {
    Write-Host "  publishable: TEST mode ($($pk.Substring(0,10))...) [$source]" -ForegroundColor Green
  } elseif ($pk.StartsWith("pk_live_")) {
    Write-Host "  publishable: LIVE mode ($($pk.Substring(0,10))...) - needs Moyasar activation or HTTP 405 [$source]" -ForegroundColor Yellow
  } else {
    Write-Host "  publishable: NOT SET [$source]" -ForegroundColor Red
  }
  Write-Host "  callback: $cb"
} catch {
  Write-Host "  FAILED to read supabase_config.json: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== 2) 3DS callback page ===" -ForegroundColor Cyan
try {
  $r = Invoke-WebRequest -Uri "$hostUrl/moyasar-3ds-return" -UseBasicParsing -TimeoutSec 15
  if ($r.Content -match "moyasar-3ds-return") {
    Write-Host "  OK: dedicated 3DS page found" -ForegroundColor Green
  } elseif ($r.Content -match "aqar_user|flutter") {
    Write-Host "  FAIL: SPA index.html returned - redeploy after adding web/moyasar-3ds-return.html" -ForegroundColor Red
  } else {
    Write-Host "  Check manually: HTTP $($r.StatusCode)"
  }
} catch {
  Write-Host "  FAILED: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== 3) Supabase secrets (requires supabase CLI) ===" -ForegroundColor Cyan
if (Get-Command supabase -ErrorAction SilentlyContinue) {
  supabase secrets list 2>&1 | Select-String "MOYASAR"
  Write-Host "  Required: MOYASAR_SECRET_KEY, MOYASAR_WEBHOOK_SECRET, MOYASAR_CALLBACK_URL"
  Write-Host "  Match: sk_test_ with pk_test_ | sk_live_ with pk_live_"
} else {
  Write-Host "  supabase CLI not installed - check Dashboard > Edge Functions > Secrets"
}

Write-Host ""
Write-Host "=== 4) Webhook URL (paste in Moyasar dashboard) ===" -ForegroundColor Cyan
Write-Host "  https://czfvqhepsqkgsrfnknwm.supabase.co/functions/v1/moyasar-webhook"

Write-Host ""
Write-Host "=== 5) HTTP 405 cause ===" -ForegroundColor Cyan
Write-Host "  pk_live_ + inactive Moyasar account = Method Not Allowed"
Write-Host "  Test fix: pk_test_ in supabase_config.json + sk_test_ in Supabase Secrets"
Write-Host "  Live fix: activate Moyasar live account with sales team"
