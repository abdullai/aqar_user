# يطابق firebase.json hosting.predeploy — يمنع خطأ:
# flutter_service_worker.js: Cache.put + Partial response (206) is unsupported
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
flutter build web --release --pwa-strategy=none @args
