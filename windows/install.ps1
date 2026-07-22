[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sameDirectoryExe = Join-Path $sourceRoot 'CodexQuotaWidget.exe'
$distExe = Join-Path (Join-Path $sourceRoot 'dist') 'CodexQuotaWidget.exe'
$sourceExe = if (Test-Path -LiteralPath $sameDirectoryExe) { $sameDirectoryExe } elseif (Test-Path -LiteralPath $distExe) { $distExe } else { $null }
$installRoot = Join-Path $env:LOCALAPPDATA 'CodexQuotaWidget'
$installExe = Join-Path $installRoot 'CodexQuotaWidget.exe'
$startupRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$shortcutPath = Join-Path $startupRoot 'Codex Quota Widget.lnk'
$legacyShortcutPath = Join-Path $startupRoot 'Codex 额度小组件.lnk'
$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'CodexQuotaWidget'

if (-not $sourceExe) {
    throw "Installer is incomplete. CodexQuotaWidget.exe was not found in '$sourceRoot' or its dist folder."
}

Get-Process -Name 'CodexQuotaWidget' -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceExe -Destination $installExe -Force

# Register a per-user startup entry. It starts after Windows sign-in and is
# visible in Task Manager / Settings under Startup apps.
New-Item -Path $runKeyPath -Force | Out-Null
New-ItemProperty -Path $runKeyPath -Name $runValueName -PropertyType String -Value ('"{0}"' -f $installExe) -Force | Out-Null

# Remove shortcut-based entries left by earlier builds to avoid duplicate starts.
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
}
if (Test-Path -LiteralPath $legacyShortcutPath) {
    Remove-Item -LiteralPath $legacyShortcutPath -Force
}

Start-Process -FilePath $installExe
Write-Host 'Codex Quota Widget was installed and started.'
Write-Host "Install location: $installRoot"
Write-Host 'Windows startup registration was enabled for the current user.'
