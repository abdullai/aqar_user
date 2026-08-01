# تنظيف كامل + l10n + build web + تشخيص + خادم محلي على المنفذ 70
# الاستخدام (PowerShell كمسؤول إن فشل المنفذ 70):
#   cd D:\aqar_user
#   .\scripts\local-web-port70.ps1 -ServeOnly          # خادم فقط (بدون clean ولا build)
#   .\scripts\local-web-port70.ps1 -SkipClean          # build بدون حذف build السابق
#
# الرابط بعد النجاح: http://localhost:70/#/userDashboard
# إيقاف الخادم: Ctrl+C في نفس النافذة

param(
  [int]$Port = 70,
  [switch]$SkipClean,
  [switch]$ServeOnly
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Write-Step($msg) {
  Write-Host ""
  Write-Host ">> $msg" -ForegroundColor Cyan
}

function Test-PortFree([int]$p) {
  try {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
    $l.Start()
    $l.Stop()
    return $true
  } catch {
    return $false
  }
}

if ($ServeOnly) { $SkipClean = $true }

Write-Host "=== Aqar: $(if ($ServeOnly) { 'serve only' } elseif ($SkipClean) { 'build (no clean)' } else { 'clean + build' }) + local port $Port ===" -ForegroundColor Green
Write-Host "Project: $root"

if (-not (Test-PortFree $Port)) {
  Write-Host "[!!] Port $Port is in use. Close the other app or run as Admin." -ForegroundColor Yellow
  Write-Host "     Or: .\scripts\local-web-port70.ps1 -Port 8070" -ForegroundColor Yellow
  exit 1
}

if (-not $SkipClean) {
  Write-Step "flutter clean"
  flutter clean
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $ServeOnly) {
Write-Step "Remove generated l10n (keep .arb sources)"
Get-ChildItem -Path "lib\l10n" -Filter "app_localizations*.dart" -ErrorAction SilentlyContinue |
  Remove-Item -Force -ErrorAction SilentlyContinue

Write-Step "flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Step "flutter gen-l10n"
flutter gen-l10n
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Step "flutter build web --release --no-wasm-dry-run"
flutter build web --release --no-wasm-dry-run
if ($LASTEXITCODE -ne 0) {
  Write-Host "[!!] Build FAILED - fix errors above before serving." -ForegroundColor Red
  exit $LASTEXITCODE
}

$swSrc = Join-Path $root "web\firebase-messaging-sw.js"
$swDst = Join-Path $root "build\web\firebase-messaging-sw.js"
if ((Test-Path $swSrc) -and -not (Test-Path $swDst)) {
  Copy-Item $swSrc $swDst -Force
  Write-Host ">> copied firebase-messaging-sw.js"
}

$cfgSrc = Join-Path $root "web\supabase_config.json"
$cfgDst = Join-Path $root "build\web\supabase_config.json"
if ((Test-Path $cfgSrc) -and -not (Test-Path $cfgDst)) {
  Copy-Item $cfgSrc $cfgDst -Force
  Write-Host ">> copied supabase_config.json"
}

Write-Step "Quick build checks"
$mainJs = Join-Path $root "build\web\main.dart.js"
if (-not (Test-Path $mainJs)) {
  Write-Host "[!!] build\web\main.dart.js missing" -ForegroundColor Red
  exit 1
}
  Write-Host "[OK] main.dart.js size $([math]::Round((Get-Item $mainJs).Length / 1MB, 2)) MB"
} else {
  Write-Step "Serve only (skip build)"
  $mainJs = Join-Path $root "build\web\main.dart.js"
  if (-not (Test-Path $mainJs)) {
    Write-Host "[!!] build\web\main.dart.js missing - run without -ServeOnly first" -ForegroundColor Red
    exit 1
  }
  Write-Host "[OK] using existing build ($([math]::Round((Get-Item $mainJs).Length / 1MB, 2)) MB)"
}

if (-not $ServeOnly) {
Write-Step "Analyze (errors only - optional, does not block serve)"
$analyzeOk = $true
try {
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $analyzeOut = flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1
  $analyzeErrors = $analyzeOut | Select-String -Pattern "error -"
  if ($analyzeErrors) {
    $analyzeOk = $false
    $analyzeErrors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "[!!] flutter analyze reported errors (see above)" -ForegroundColor Yellow
  } elseif ($LASTEXITCODE -ne 0) {
    Write-Host "[OK] analyze finished (warnings/infos only, no error lines)" -ForegroundColor Green
  } else {
    Write-Host "[OK] no analyzer errors" -ForegroundColor Green
  }
  $ErrorActionPreference = $prevEap
} catch {
  Write-Host "[!!] analyze skipped or failed: $_" -ForegroundColor Yellow
}
}

Write-Host ""
Write-Host "=== Local URLs ===" -ForegroundColor Green
Write-Host "  Dashboard: http://localhost:$Port/#/userDashboard"
Write-Host "  Root:      http://localhost:$Port/"
Write-Host ""
Write-Host "=== After login: F12 -> Console -> filter: AqarWebDiag ===" -ForegroundColor Yellow
Write-Host "  Expect: initial_load web path complete -> deferred_tabs complete"
Write-Host ""
Write-Host "Press Ctrl+C to stop the server."
Write-Host ""

Set-Location (Join-Path $root "build\web")

# Prefer Python (simple static server)
$python = $null
foreach ($cmd in @("python", "py")) {
  if (Get-Command $cmd -ErrorAction SilentlyContinue) {
    $python = $cmd
    break
  }
}

if ($python) {
  Write-Host ">> Serving with $python on port $Port ..." -ForegroundColor Cyan
  & $python -m http.server $Port --bind 127.0.0.1
  exit $LASTEXITCODE
}

# Fallback: npx serve
if (Get-Command npx -ErrorAction SilentlyContinue) {
  Write-Host ">> Serving with npx serve on port $Port ..." -ForegroundColor Cyan
  npx --yes serve -l $Port .
  exit $LASTEXITCODE
}

Write-Host "[!!] Install Python or Node.js to serve locally, or open build\web in another server." -ForegroundColor Red
Write-Host "Manual: cd build\web; python -m http.server $Port"
exit 1
