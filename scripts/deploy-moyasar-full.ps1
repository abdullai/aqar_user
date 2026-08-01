# نشر كامل: Flutter Web + Firebase Hosting + دوال ميسّر على Supabase
# الاستخدام:
#   powershell -ExecutionPolicy Bypass -File d:\aqar_user\scripts\deploy-moyasar-full.ps1
#
# قبل التشغيل (مرة واحدة):
#   1) supabase login
#   2) firebase login
#   3) في Supabase Edge Secrets: MOYASAR_SECRET_KEY = sk_test_... (كامل من لوحة ميسّر)

param(
    [switch]$SkipBuild,
    [switch]$SkipFunctions,
    [switch]$SkipHosting
)

$ErrorActionPreference = "Stop"
$ProjectRoot = "d:\aqar_user"
$SupabaseProjectRef = "czfvqhepsqkgsrfnknwm"
$Functions = @(
    "moyasar-payment-health",
    "moyasar-webhook",
    "moyasar-charge-saved-card"
)

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "========== $Message ==========" -ForegroundColor Cyan
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "الأمر '$Name' غير موجود في PATH. ثبّته ثم أعد المحاولة."
    }
}

function Invoke-External([string]$Label, [string]$FilePath, [string[]]$Arguments) {
    Write-Step $Label
    Write-Host "$FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "فشل: $Label (رمز الخروج $LASTEXITCODE)"
    }
}

Set-Location $ProjectRoot
Write-Host "المجلد: $ProjectRoot" -ForegroundColor Green

Assert-Command "flutter"
Assert-Command "firebase"
if (-not $SkipFunctions) {
    Assert-Command "supabase"
}

$configPath = Join-Path $ProjectRoot "web\supabase_config.json"
if (-not (Test-Path $configPath)) {
    throw "ملف web\supabase_config.json غير موجود."
}
$cfgRaw = Get-Content $configPath -Raw | ConvertFrom-Json
$pk = "$($cfgRaw.MOYASAR_PUBLISHABLE_KEY)".Trim()
if (-not $pk.StartsWith("pk_test_")) {
    Write-Host "تحذير: MOYASAR_PUBLISHABLE_KEY ليس pk_test_ — الدفع التجريبي قد يفشل." -ForegroundColor Yellow
} else {
    Write-Host "OK: pk_test_ مضبوط في supabase_config.json" -ForegroundColor Green
}

$callbackPath = Join-Path $ProjectRoot "web\moyasar-3ds-return.html"
if (-not (Test-Path $callbackPath)) {
    throw "ملف web\moyasar-3ds-return.html مفقود."
}

if (-not $SkipBuild) {
    Invoke-External "Flutter build (web release)" "flutter" @(
        "build", "web", "--release", "--no-wasm-dry-run"
    )
} else {
    Write-Host "تخطي البناء (-SkipBuild)" -ForegroundColor Yellow
}

if (-not $SkipHosting) {
    Invoke-External "Firebase Hosting" "firebase" @(
        "deploy", "--only", "hosting"
    )
} else {
    Write-Host "تخطي Firebase (-SkipHosting)" -ForegroundColor Yellow
}

if (-not $SkipFunctions) {
    foreach ($fn in $Functions) {
        Invoke-External "Supabase function: $fn" "supabase" @(
            "functions", "deploy", $fn,
            "--project-ref", $SupabaseProjectRef
        )
    }
} else {
    Write-Host "تخطي دوال Supabase (-SkipFunctions)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "اكتمل النشر بنجاح." -ForegroundColor Green
Write-Host "تحقق: https://eaqar-mawthuq.web.app/supabase_config.json" -ForegroundColor Green
Write-Host "تحقق: https://eaqar-mawthuq.web.app/moyasar-3ds-return" -ForegroundColor Green
Write-Host "فحص: powershell -File d:\aqar_user\scripts\check_moyasar_setup.ps1" -ForegroundColor Green
