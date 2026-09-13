# نشر ويب سريع — بدون flutter clean. يبني مرة واحدة ثم يرفع hosting فقط.
# إذا أردت أن firebase.json predeploy يبني: علّق السطر أدناه واستخدم firebase deploy فقط.
param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

function Resolve-NodeExe {
  $hints = @(
    (Join-Path ${env:ProgramFiles} "nodejs\node.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "nodejs\node.exe"),
    (Join-Path $env:APPDATA "npm\node.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\cursor\resources\app\resources\helpers\node.exe")
  )
  foreach ($p in $hints) {
    if ($p -and (Test-Path $p)) { return $p }
  }
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) { return $cmd.Source }
  return $null
}

function Resolve-FirebaseCli {
  $npmBin = Join-Path $env:APPDATA "npm"
  $firebaseJs = Join-Path $npmBin "node_modules\firebase-tools\lib\bin\firebase.js"
  $nodeExe = Resolve-NodeExe
  if ($nodeExe) {
    $env:PATH = "$(Split-Path $nodeExe -Parent);$npmBin;$env:PATH"
  } elseif (Test-Path $npmBin) {
    $env:PATH = "$npmBin;$env:PATH"
  }

  if ((Test-Path $firebaseJs) -and $nodeExe) {
    return @{ File = $nodeExe; Prefix = @($firebaseJs) }
  }

  throw @"
Node.js أو Firebase CLI غير موجودين في PATH.
ثبّت Node.js من https://nodejs.org ثم نفّذ:
  npm install -g firebase-tools
"@
}

if (-not $SkipBuild) {
  Write-Host ">> flutter gen-l10n"
  flutter gen-l10n
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
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

$fb = Resolve-FirebaseCli
Write-Host ">> firebase deploy --only hosting"
$deployArgs = $fb.Prefix + @("deploy", "--only", "hosting")
& $fb.File @deployArgs
exit $LASTEXITCODE
