# Run as Administrator. Adds C++ desktop tools to Visual Studio Community 2022
# (the instance Flutter doctor checks). Then: flutter doctor   flutter run -d windows
$ErrorActionPreference = 'Stop'
$installer = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vs_installer.exe'
$community = 'C:\Program Files\Microsoft Visual Studio\2022\Community'
if (-not (Test-Path $installer)) {
  throw "Visual Studio Installer not found: $installer"
}
if (-not (Test-Path $community)) {
  throw "Visual Studio Community 2022 not found: $community"
}
Start-Process -FilePath $installer -ArgumentList @(
  'modify',
  '--installPath', $community,
  '--add', 'Microsoft.VisualStudio.Workload.NativeDesktop',
  '--includeRecommended',
  '--passive',
  '--norestart'
) -Wait -Verb RunAs
Write-Host 'Done. Close this window, then run:  flutter doctor'
