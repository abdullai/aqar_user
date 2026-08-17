# Copies Moyasar/Apple Pay domain verification file into build/web before firebase deploy.
$src = Join-Path $PSScriptRoot '..\web\well-known\apple-developer-merchantid-domain-association'
$destDir = Join-Path $PSScriptRoot '..\build\web\well-known'
$dest = Join-Path $destDir 'apple-developer-merchantid-domain-association'

if (-not (Test-Path $src)) {
  Write-Error "Missing source file: $src"
  exit 1
}

New-Item -ItemType Directory -Force -Path $destDir | Out-Null
Copy-Item -Force $src $dest
Write-Host "Copied Apple Pay verification file to $dest"
