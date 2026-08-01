<#
.SYNOPSIS
  Build portable package + Windows installer for RB 1.12 to 26.2 Java Converter.
#>
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Dist = Join-Path $RepoRoot 'dist'
$PortableRoot = Join-Path $Dist 'portable\RB-112-to-262-Java-Converter'
$GuiProj = Join-Path $RepoRoot 'src\RB.JavaConverter112\RB.JavaConverter112.csproj'
$SetupProj = Join-Path $RepoRoot 'src\RB.JavaConverter112.Setup\RB.JavaConverter112.Setup.csproj'

Write-Host "==> Cleaning dist" -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Path $PortableRoot -Force | Out-Null

Write-Host "==> Publishing GUI (self-contained $Runtime)" -ForegroundColor Cyan
$guiOut = Join-Path $Dist 'publish-gui'
dotnet publish $GuiProj `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $guiOut

if ($LASTEXITCODE -ne 0) { throw "GUI publish failed" }

$guiExe = Join-Path $guiOut 'RB-112-to-262-Java-Converter.exe'
if (-not (Test-Path $guiExe)) { throw "Missing $guiExe" }
Copy-Item $guiExe $PortableRoot -Force

$toolsFinal = Join-Path $PortableRoot 'tools'
New-Item -ItemType Directory -Path $toolsFinal -Force | Out-Null
foreach ($s in @(
    'Convert-JarToProject112.ps1',
    'Convert-OldJar112ToNeoForge262.ps1',
    'Convert-112ToNeoForge262.ps1',
    'README.md',
    'LICENSE',
    'CHANGELOG.md'
)) {
    $src = Join-Path $RepoRoot $s
    if (Test-Path $src) { Copy-Item $src $toolsFinal -Force; Write-Host "    tools/$s" }
}
if (Test-Path (Join-Path $RepoRoot 'docs')) {
    Copy-Item (Join-Path $RepoRoot 'docs') (Join-Path $toolsFinal 'docs') -Recurse -Force
}

@'
@echo off
cd /d "%~dp0"
start "" "%~dp0RB-112-to-262-Java-Converter.exe"
'@ | Set-Content (Join-Path $PortableRoot 'Start-Converter.bat') -Encoding ASCII

Copy-Item (Join-Path $RepoRoot 'README.md') (Join-Path $PortableRoot 'README.md') -Force
if (Test-Path (Join-Path $RepoRoot 'LICENSE')) {
    Copy-Item (Join-Path $RepoRoot 'LICENSE') (Join-Path $PortableRoot 'LICENSE.txt') -Force
}
if (Test-Path (Join-Path $RepoRoot 'assets\app.ico')) {
    Copy-Item (Join-Path $RepoRoot 'assets\app.ico') (Join-Path $PortableRoot 'app.ico') -Force
}

Write-Host "==> Creating portable ZIP" -ForegroundColor Cyan
$portableZip = Join-Path $Dist 'RB-112-to-262-Java-Converter-Portable.zip'
if (Test-Path $portableZip) { Remove-Item $portableZip -Force }
Compress-Archive -Path (Join-Path $Dist 'portable\RB-112-to-262-Java-Converter') -DestinationPath $portableZip -Force

$payloadZip = Join-Path $Dist 'portable-payload.zip'
Copy-Item $portableZip $payloadZip -Force

Write-Host "==> Publishing Setup installer (self-contained $Runtime, payload embedded)" -ForegroundColor Cyan
$setupOut = Join-Path $Dist 'publish-setup'
if (-not (Test-Path $payloadZip)) { throw "portable-payload.zip missing before setup publish" }

dotnet publish $SetupProj `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:DebugType=None `
    -p:DebugSymbols=false `
    -o $setupOut

if ($LASTEXITCODE -ne 0) { throw "Setup publish failed" }

$setupExe = Join-Path $setupOut 'RB-112-to-262-Java-Converter-Setup.exe'
if (-not (Test-Path -LiteralPath $setupExe)) {
    throw "Setup publish succeeded but EXE not found: $setupExe"
}

Copy-Item $setupExe $Dist -Force

Write-Host ""
Write-Host "Build complete:" -ForegroundColor Green
Write-Host "  Portable folder : $PortableRoot"
Write-Host "  Portable ZIP    : $portableZip"
Write-Host "  Setup EXE       : $(Join-Path $Dist 'RB-112-to-262-Java-Converter-Setup.exe')"
Write-Host ""
Get-ChildItem $Dist -File | Format-Table Name, @{N='MB';E={[math]::Round($_.Length/1MB,2)}}, LastWriteTime
