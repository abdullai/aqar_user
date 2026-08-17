# Build Flutter web, copy Apple Pay verification file, deploy Firebase Hosting.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

Write-Host 'Building Flutter web...'
flutter build web --release

Write-Host 'Copying Apple Pay domain verification file...'
& (Join-Path $PSScriptRoot 'copy_apple_pay_domain_file.ps1')

Write-Host 'Deploying Firebase Hosting (eaqar-mawthuq)...'
firebase deploy --only hosting

Write-Host 'Done. Verify:'
Write-Host 'https://eaqar-mawthuq.web.app/.well-known/apple-developer-merchantid-domain-association'
