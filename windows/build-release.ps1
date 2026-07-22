[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputRoot = Join-Path $projectRoot 'dist'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (-not (Test-Path -LiteralPath $compiler)) {
    throw '.NET Framework C# compiler was not found.'
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

& $compiler @(
    '/nologo',
    '/target:winexe',
    '/platform:anycpu',
    '/optimize+',
    '/debug:pdbonly',
    ('/out:' + (Join-Path $outputRoot 'CodexQuotaWidget.exe')),
    ('/win32manifest:' + (Join-Path $projectRoot 'app.manifest')),
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll',
    '/reference:System.Web.Extensions.dll',
    (Join-Path $projectRoot 'CodexQuotaWidget.cs')
)

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

Copy-Item -LiteralPath (Join-Path $projectRoot 'install.ps1') -Destination $outputRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'uninstall.ps1') -Destination $outputRoot -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $outputRoot -Force

Write-Host "Build completed: $(Join-Path $outputRoot 'CodexQuotaWidget.exe')"
