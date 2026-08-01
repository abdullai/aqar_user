# نشر ويب سريع — بدون flutter clean. يبني مرة واحدة ثم يرفع hosting فقط.
# إذا أردت أن firebase.json predeploy يبني: علّق السطر أدناه واستخدم firebase deploy فقط.
param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

if (-not $SkipBuild) {
  Write-Host ">> flutter build web --release --no-wasm-dry-run"
  flutter build web --release --no-wasm-dry-run
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$swSrc = Join-Path (Get-Location) "web\firebase-messaging-sw.js"
$swDst = Join-Path (Get-Location) "build\web\firebase-messaging-sw.js"
if ((Test-Path $swSrc) -and -not (Test-Path $swDst)) {
  Copy-Item $swSrc $swDst -Force
  Write-Host ">> copied firebase-messaging-sw.js to build/web"
}

Write-Host ">> scripts/diagnose-web.ps1 (pre-deploy)"
& (Join-Path $PSScriptRoot "diagnose-web.ps1") -SiteUrl "https://eaqar-mawthuq.web.app"

Write-Host ">> firebase deploy --only hosting"
firebase deploy --only hosting
exit $LASTEXITCODE
