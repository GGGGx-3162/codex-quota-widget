[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'CodexQuotaWidget'
$startupRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$shortcutPath = Join-Path $startupRoot 'Codex Quota Widget.lnk'
$legacyShortcutPath = Join-Path $startupRoot 'Codex 额度小组件.lnk'
$runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValueName = 'CodexQuotaWidget'

Get-Process -Name 'CodexQuotaWidget' -ErrorAction SilentlyContinue | Stop-Process -Force
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
}
if (Test-Path -LiteralPath $legacyShortcutPath) {
    Remove-Item -LiteralPath $legacyShortcutPath -Force
}
if (Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $runKeyPath -Name $runValueName -Force
}
if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

Write-Host 'Codex Quota Widget was uninstalled.'
