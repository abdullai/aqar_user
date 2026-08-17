# يزيد الإصدار في pubspec.yaml ثم يمكنكم تشغيل flutter build ...
# الاستخدام من جذر المشروع:
#   .\scripts\bump_version.ps1
#   .\scripts\bump_version.ps1 -Patch
#   .\scripts\bump_version.ps1 -DryRun

param(
    [switch]$Patch,
    [switch]$Minor,
    [switch]$Major,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$args = @("run", "tool/bump_version.dart")
if ($Patch) { $args += "--patch" }
if ($Minor) { $args += "--minor" }
if ($Major) { $args += "--major" }
if ($DryRun) { $args += "--dry-run" }

& dart @args
exit $LASTEXITCODE
