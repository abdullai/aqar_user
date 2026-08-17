# Clean build + deploy Flutter web to Firebase Hosting
# Usage:  .\scripts\clean_deploy_web.ps1
# No deploy:  .\scripts\clean_deploy_web.ps1 -SkipDeploy

param(
  [switch]$SkipDeploy,
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host ""
Write-Host "=== [1/5] Remove old build artifacts ===" -ForegroundColor Cyan

$toRemove = @(
  'build',
  '_backup_compare'
)

foreach ($rel in $toRemove) {
  $full = Join-Path $Root $rel
  if (Test-Path $full) {
    Write-Host "  remove: $rel"
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Get-ChildItem -Path $Root -Filter 'build_*_log*.txt' -File -ErrorAction SilentlyContinue |
  ForEach-Object {
    Write-Host "  remove: $($_.Name)"
    Remove-Item -LiteralPath $_.FullName -Force
  }

Get-ChildItem -Path (Join-Path $Root '.firebase') -Filter 'hosting.*.cache' -File -ErrorAction SilentlyContinue |
  ForEach-Object {
    Write-Host "  remove cache: $($_.Name)"
    Remove-Item -LiteralPath $_.FullName -Force
  }

Write-Host ""
Write-Host "=== [2/5] flutter clean ===" -ForegroundColor Cyan
flutter clean
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "=== [3/5] flutter pub get ===" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$configPath = Join-Path $Root 'web\supabase_config.json'
if (-not (Test-Path $configPath)) {
  Write-Host "  WARN: web\supabase_config.json missing (copy from .example)" -ForegroundColor Yellow
}

if ($SkipBuild) {
  Write-Host ""
  Write-Host "Clean done (SkipBuild). No build run." -ForegroundColor Green
  exit 0
}

Write-Host ""
Write-Host "=== [4/5] flutter build web --release ===" -ForegroundColor Cyan
Write-Host "  This may take 15-35 minutes..." -ForegroundColor DarkGray
flutter build web --release --no-wasm-dry-run --pwa-strategy=none --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$mainJs = Join-Path $Root 'build\web\main.dart.js'
if (-not (Test-Path $mainJs)) {
  Write-Host "  ERROR: build\web\main.dart.js not found" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "  OK: fresh build\web ready" -ForegroundColor Green

if ($SkipDeploy) {
  Write-Host ""
  Write-Host "Build done (SkipDeploy). Deploy with:" -ForegroundColor Green
  Write-Host "  firebase deploy --only hosting" -ForegroundColor White
  exit 0
}

Write-Host ""
Write-Host "=== [5/5] firebase deploy --only hosting ===" -ForegroundColor Cyan
firebase deploy --only hosting
exit $LASTEXITCODE
