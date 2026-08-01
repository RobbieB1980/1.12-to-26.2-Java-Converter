<#
.SYNOPSIS
  Full pipeline: Forge 1.12.2 finished .jar -> decompile -> NeoForge 26.2 scaffold.

.DESCRIPTION
  1) Convert-JarToProject112.ps1  (Vineflower decompile + src layout + mcmod.info)
  2) Convert-112ToNeoForge262.ps1 (Gradle 26.2 + 1.12 mechanical rewrites)

.EXAMPLE
  .\Convert-OldJar112ToNeoForge262.ps1 -JarPath "D:\mods\old-1.12.2.jar" -OutputPath "D:\mods\old-26.2"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$JarPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$DecompilePath = '',
    [string]$MinecraftVersion = '26.2',
    [string]$NeoVersion = '26.2.0.32-beta',
    [switch]$Compile,
    [switch]$KeepDecompile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot
$jarScript = Join-Path $ToolRoot 'Convert-JarToProject112.ps1'
$convScript = Join-Path $ToolRoot 'Convert-112ToNeoForge262.ps1'
if (-not (Test-Path $jarScript)) { throw "Missing $jarScript" }
if (-not (Test-Path $convScript)) { throw "Missing $convScript" }

$JarPath = (Resolve-Path -LiteralPath $JarPath).Path
if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location) $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

if (-not $DecompilePath) {
    $base = [IO.Path]::GetFileNameWithoutExtension($JarPath)
    $parent = Split-Path $OutputPath -Parent
    if (-not $parent) { $parent = Get-Location }
    $DecompilePath = Join-Path $parent ($base + '-decompiled')
}
if (-not [IO.Path]::IsPathRooted($DecompilePath)) {
    $DecompilePath = Join-Path (Get-Location) $DecompilePath
}
$DecompilePath = [IO.Path]::GetFullPath($DecompilePath)

Write-Host ''
Write-Host 'RB 1.12 JAR -> NeoForge 26.2 (full pipeline)' -ForegroundColor White
Write-Host "  Jar       : $JarPath"
Write-Host "  Decompile : $DecompilePath"
Write-Host "  Final 26.2: $OutputPath"

if ($DryRun) {
    Write-Host 'Dry run: would decompile then convert.' -ForegroundColor Yellow
    & $jarScript -JarPath $JarPath -OutputPath $DecompilePath -DryRun
    return
}

& $jarScript -JarPath $JarPath -OutputPath $DecompilePath -MinecraftVersion $MinecraftVersion -NeoVersion $NeoVersion

$convArgLine = "-NoProfile -ExecutionPolicy Bypass -File `"$convScript`" -Path `"$DecompilePath`" -OutputPath `"$OutputPath`" -MinecraftVersion `"$MinecraftVersion`" -NeoVersion `"$NeoVersion`""
if ($Compile) { $convArgLine += ' -Compile' }

$convProc = Start-Process -FilePath 'powershell.exe' -ArgumentList $convArgLine -WorkingDirectory $ToolRoot -Wait -PassThru -NoNewWindow
$convCode = $convProc.ExitCode
if ($null -eq $convCode) { $convCode = 0 }

$scaffoldOk = (Test-Path (Join-Path $OutputPath 'MIGRATION_112_REPORT.md')) -or
              (Test-Path (Join-Path $OutputPath 'build.gradle'))
if (-not $scaffoldOk -and $convCode -ne 0) {
    throw "NeoForge 26.2 convert failed (exit $convCode) and no scaffold was written under $OutputPath"
}
if ($convCode -ne 0 -and $scaffoldOk) {
    Write-Host "Converter process exit $convCode but scaffold is present - treating as success." -ForegroundColor Yellow
}

Write-Host "==> Intermediate decompile kept at: $DecompilePath" -ForegroundColor Cyan
Write-Host ''
Write-Host "Pipeline complete." -ForegroundColor Green
Write-Host "  Decompiled project : $DecompilePath"
Write-Host "  NeoForge 26.2      : $OutputPath"
Write-Host ''
Write-Host 'Next: open the 26.2 project and run gradlew compileJava. Expect many remaining 1.12 errors.' -ForegroundColor Cyan
Write-Host 'Do NOT drop the original 1.12.2 jar into a 26.2 mods folder.' -ForegroundColor Yellow
exit 0
