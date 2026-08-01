<#
.SYNOPSIS
  Decompile a finished Minecraft mod .jar into a source project folder.

.DESCRIPTION
  Unpacks the jar, decompiles classes with Vineflower, and lays out:
    src/main/java/...
    src/main/resources/... (assets, data, pack.mcmeta, etc.)
    DECOMPILE_REPORT.md
    stub gradle.properties (so Convert-112ToNeoForge262 can accept the folder)

  This is NOT decryption - jars are not encrypted. It is a decompiler + layout tool.
  Output is a starting point only; expect manual cleanup.
  Optimized for Forge 1.12.2 jars (mcmod.info metadata).

.EXAMPLE
  .\Convert-JarToProject112.ps1 -JarPath "D:\mods\mymod-1.12.2.jar" -OutputPath "D:\mods\mymod-decompiled"

.EXAMPLE
  .\Convert-JarToProject112.ps1 -JarPath ".\mymod.jar" -OutputPath ".\mymod-src" -ContinueToNeoForge262
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$JarPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$VineflowerVersion = '1.12.0',
    [string]$JavaExe = '',
    [switch]$ContinueToNeoForge262,
    [switch]$CompileAfterConvert,
    [string]$NeoVersion = '26.2.0.32-beta',
    [string]$MinecraftVersion = '26.2',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot

function Write-Step([string]$m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m) { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn2([string]$m) { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Info([string]$m) { Write-Host "    $m" }

function Resolve-Java {
    param([string]$Preferred)
    if ($Preferred -and (Test-Path -LiteralPath $Preferred)) { return (Resolve-Path $Preferred).Path }
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @(
        "$env:JAVA_HOME\bin\java.exe",
        "${env:ProgramFiles}\Java\*\bin\java.exe",
        "${env:ProgramFiles}\Eclipse Adoptium\*\bin\java.exe",
        "${env:ProgramFiles}\Microsoft\jdk-*\bin\java.exe"
    )) {
        $hit = Get-Item $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw "Java not found. Install a JDK (17+) and ensure 'java' is on PATH, or pass -JavaExe."
}

function Get-VineflowerJar {
    param([string]$Version, [string]$CacheDir)
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $name = "vineflower-$Version.jar"
    $dest = Join-Path $CacheDir $name
    if (Test-Path -LiteralPath $dest) { return $dest }
    $url = "https://repo1.maven.org/maven2/org/vineflower/vineflower/$Version/vineflower-$Version.jar"
    Write-Info "Downloading Vineflower $Version ..."
    Write-Info $url
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    } catch {
        throw "Failed to download Vineflower from Maven Central: $($_.Exception.Message)"
    }
    if (-not (Test-Path $dest) -or ((Get-Item $dest).Length -lt 10000)) {
        throw "Vineflower download looks invalid: $dest"
    }
    return $dest
}

function Get-ModHintsFromJarExtract {
    param([string]$ExtractDir)
    $hints = [ordered]@{
        mod_id      = 'unknownmod'
        mod_name    = 'Unknown Mod'
        mod_version = '1.0.0'
        loader      = 'unknown'
        mc_hint     = ''
        has_mixins  = $false
        notes       = New-Object System.Collections.Generic.List[string]
    }

    $modsToml = Get-ChildItem -Path $ExtractDir -Recurse -Filter 'mods.toml' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'META-INF' } | Select-Object -First 1
    $neoforgeToml = Get-ChildItem -Path $ExtractDir -Recurse -Filter 'neoforge.mods.toml' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $fabric = Join-Path $ExtractDir 'fabric.mod.json'
    $mcmod = Join-Path $ExtractDir 'mcmod.info'
    $quilt = Join-Path $ExtractDir 'quilt.mod.json'

    if ($neoforgeToml) {
        $hints.loader = 'neoforge'
        $text = Get-Content $neoforgeToml.FullName -Raw -ErrorAction SilentlyContinue
        if ($text -match 'modId\s*=\s*"([^"]+)"') { $hints.mod_id = $matches[1] }
        if ($text -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $hints.mod_version = $matches[1] }
        if ($text -match 'displayName\s*=\s*"([^"]+)"') { $hints.mod_name = $matches[1] }
        if ($text -match 'minecraftVersion\s*=\s*"([^"]+)"') { $hints.mc_hint = $matches[1] }
    }
    elseif ($modsToml) {
        $hints.loader = 'forge/neoforge'
        $text = Get-Content $modsToml.FullName -Raw -ErrorAction SilentlyContinue
        if ($text -match 'modId\s*=\s*"([^"]+)"') { $hints.mod_id = $matches[1] }
        if ($text -match '(?m)^\s*version\s*=\s*"([^"]+)"') { $hints.mod_version = $matches[1] }
        if ($text -match 'displayName\s*=\s*"([^"]+)"') { $hints.mod_name = $matches[1] }
    }
    elseif (Test-Path $fabric) {
        $hints.loader = 'fabric'
        try {
            $j = Get-Content $fabric -Raw | ConvertFrom-Json
            if ($j.id) { $hints.mod_id = [string]$j.id }
            if ($j.name) { $hints.mod_name = [string]$j.name }
            if ($j.version) { $hints.mod_version = [string]$j.version }
            if ($j.depends.minecraft) { $hints.mc_hint = [string]$j.depends.minecraft }
        } catch { $hints.notes.Add('fabric.mod.json parse failed') }
    }
    elseif (Test-Path $quilt) {
        $hints.loader = 'quilt'
        $hints.notes.Add('Quilt mod detected - Legacy Converter targets Forge/NeoForge sources.')
    }
    elseif (Test-Path $mcmod) {
        $hints.loader = 'forge-1.12'
        $hints.notes.Add('mcmod.info found (Forge 1.12.x / legacy).')
        try {
            $raw = Get-Content -LiteralPath $mcmod -Raw -ErrorAction SilentlyContinue
            # mcmod.info is usually a JSON array
            $j = $raw | ConvertFrom-Json
            $entry = if ($j -is [System.Array]) { $j[0] } else { $j }
            if ($entry.modid) { $hints.mod_id = [string]$entry.modid }
            if ($entry.name) { $hints.mod_name = [string]$entry.name }
            if ($entry.version) { $hints.mod_version = [string]$entry.version }
            if ($entry.mcversion) { $hints.mc_hint = [string]$entry.mcversion }
            if ($entry.authorList) {
                $hints.notes.Add(('authors: ' + (($entry.authorList | ForEach-Object { "$_" }) -join ', ')))
            }
        } catch {
            $hints.notes.Add('mcmod.info parse failed - falling back to package heuristics.')
            # Regex fallback
            if ($raw -match '"modid"\s*:\s*"([^"]+)"') { $hints.mod_id = $Matches[1] }
            if ($raw -match '"name"\s*:\s*"([^"]+)"') { $hints.mod_name = $Matches[1] }
            if ($raw -match '"version"\s*:\s*"([^"]+)"') { $hints.mod_version = $Matches[1] }
            if ($raw -match '"mcversion"\s*:\s*"([^"]+)"') { $hints.mc_hint = $Matches[1] }
        }
    }

    if (Get-ChildItem -Path $ExtractDir -Recurse -Filter '*mixins*.json' -ErrorAction SilentlyContinue) {
        $hints.has_mixins = $true
        $hints.notes.Add('Mixin configs present - decompiled mixins often need heavy manual repair.')
    }

    # Prefer nested assets/<modid> as mod id if still unknown
    if ($hints.mod_id -eq 'unknownmod' -or $hints.mod_id -eq 'net') {
        $assets = Join-Path $ExtractDir 'assets'
        if (Test-Path $assets) {
            $modAsset = Get-ChildItem $assets -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin @('minecraft') } |
                Select-Object -First 1
            if ($modAsset) { $hints.mod_id = $modAsset.Name.ToLowerInvariant() }
        }
    }

    # Prefer package root as mod id if still unknown (avoid single-segment "net")
    if ($hints.mod_id -eq 'unknownmod' -or $hints.mod_id -eq 'net') {
        $pkg = Get-ChildItem -Path $ExtractDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('META-INF', 'assets', 'data', 'pack.mcmeta', 'net', 'com') } |
            Select-Object -First 1
        if ($pkg) { $hints.mod_id = $pkg.Name.ToLowerInvariant() }
    }

    return $hints
}

function Copy-JarResources {
    param([string]$ExtractDir, [string]$ResourcesDir)
    New-Item -ItemType Directory -Force -Path $ResourcesDir | Out-Null
    $copyNames = @('assets', 'data', 'META-INF')
    foreach ($n in $copyNames) {
        $src = Join-Path $ExtractDir $n
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $ResourcesDir $n) -Recurse -Force
        }
    }
    foreach ($f in @('pack.mcmeta', 'fabric.mod.json', 'quilt.mod.json', 'mcmod.info')) {
        $src = Join-Path $ExtractDir $f
        if (Test-Path $src) { Copy-Item $src $ResourcesDir -Force }
    }
    # Root-level json configs sometimes used by mods
    Get-ChildItem $ExtractDir -File -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match 'mixins|refmap|accesswidener') {
            Copy-Item $_.FullName $ResourcesDir -Force
        }
    }
}

# -------------------- main --------------------
$JarPath = (Resolve-Path -LiteralPath $JarPath).Path
if (-not ($JarPath.ToLowerInvariant().EndsWith('.jar'))) {
    Write-Warn2 "Input does not end with .jar - continuing anyway."
}
if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path (Get-Location) $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

Write-Host ''
Write-Host 'RB 1.12 JAR Decompiler - finished .jar -> source project' -ForegroundColor White
Write-Host "  Jar    : $JarPath"
Write-Host "  Output : $OutputPath"
Write-Host "  Engine : Vineflower $VineflowerVersion"

if ($DryRun) {
    Write-Host '  DryRun : yes' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Would: extract jar, decompile classes, write src/main/java + resources, DECOMPILE_REPORT.md' -ForegroundColor Cyan
    if ($ContinueToNeoForge262) { Write-Host 'Would then run Convert-112ToNeoForge262.ps1 on the decompiled project' -ForegroundColor Cyan }
    return
}

if (Test-Path -LiteralPath $OutputPath) {
    $items = @(Get-ChildItem -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue)
    if ($items.Count -gt 0) { throw "Output folder not empty: $OutputPath" }
}
else {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$java = Resolve-Java -Preferred $JavaExe
Write-Ok "Java: $java"

$cacheDir = Join-Path $ToolRoot 'lib\decompiler-cache'
$vine = Get-VineflowerJar -Version $VineflowerVersion -CacheDir $cacheDir
Write-Ok "Vineflower: $vine"

$work = Join-Path ([IO.Path]::GetTempPath()) ("rb-jar-decompile-" + [guid]::NewGuid().ToString('N'))
$extractDir = Join-Path $work 'extract'
$decompileDir = Join-Path $work 'decompiled'
New-Item -ItemType Directory -Force -Path $extractDir, $decompileDir | Out-Null

try {
    Write-Step 'Extracting jar'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($JarPath, $extractDir)
    Write-Ok "Extracted to temp work dir"

    $hints = Get-ModHintsFromJarExtract -ExtractDir $extractDir
    Write-Info "Detected loader=$($hints.loader) mod_id=$($hints.mod_id) version=$($hints.mod_version)"

    Write-Step 'Decompiling classes (Vineflower)'
    # Vineflower: java -jar vineflower.jar <source> <destination>
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $java
    $psi.Arguments = "-jar `"$vine`" -dgs=1 `"$JarPath`" `"$decompileDir`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($stdout) { $stdout -split "`n" | Select-Object -Last 20 | ForEach-Object { if ($_) { Write-Info $_ } } }
    if ($stderr) { $stderr -split "`n" | Select-Object -Last 15 | ForEach-Object { if ($_) { Write-Warn2 $_ } } }
    if ($proc.ExitCode -ne 0) {
        throw "Vineflower exited with code $($proc.ExitCode)"
    }
    Write-Ok 'Decompile finished'

    Write-Step 'Laying out Maven/Gradle source tree'
    $javaOut = Join-Path $OutputPath 'src\main\java'
    $resOut = Join-Path $OutputPath 'src\main\resources'
    New-Item -ItemType Directory -Force -Path $javaOut, $resOut | Out-Null

    # Vineflower may emit .java under decompileDir mirroring packages, or nested jar folder
    $javaFiles = @(Get-ChildItem $decompileDir -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue)
    if ($javaFiles.Count -eq 0) {
        # Sometimes outputs into a subfolder named after the jar
        $alt = Get-ChildItem $decompileDir -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($alt) {
            $javaFiles = @(Get-ChildItem $alt.FullName -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue)
            $decompileRoot = $alt.FullName
        } else {
            $decompileRoot = $decompileDir
        }
    } else {
        $decompileRoot = $decompileDir
    }

    if ($javaFiles.Count -eq 0) {
        throw "No .java files produced by decompiler. The jar may be empty or obfuscated beyond recovery."
    }

    # Copy entire decompile tree package structure into src/main/java
    # Prefer copying all non-resource paths
    foreach ($jf in $javaFiles) {
        $rel = $jf.FullName.Substring($decompileRoot.Length).TrimStart('\', '/')
        $dest = Join-Path $javaOut $rel
        $destDir = Split-Path $dest -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        Copy-Item $jf.FullName $dest -Force
    }
    Write-Ok "Java sources: $($javaFiles.Count) files"

    Copy-JarResources -ExtractDir $extractDir -ResourcesDir $resOut
    Write-Ok 'Resources copied (assets/data/META-INF when present)'

    # Stub project markers for converter + IDEs
    $jarName = [IO.Path]::GetFileName($JarPath)
    $propsLines = @(
        '# Generated by Convert-JarToProject.ps1 (decompiled jar - not original source)'
        "mod_id=$($hints.mod_id)"
        "mod_name=$($hints.mod_name)"
        "mod_version=$($hints.mod_version)"
        "mod_group_id=com.example.$($hints.mod_id)"
        'mod_authors=Unknown'
        "mod_description=Decompiled from $jarName. Requires manual cleanup."
        "minecraft_version=$MinecraftVersion"
        "neo_version=$NeoVersion"
        'org.gradle.jvmargs=-Xmx2G'
    )
    Set-Content -Path (Join-Path $OutputPath 'gradle.properties') -Value ($propsLines -join [Environment]::NewLine) -Encoding UTF8

    $readmeLines = @(
        "# Decompiled project: $($hints.mod_name)"
        ""
        "Source jar: $JarPath"
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        ""
        "This folder was produced by Convert-JarToProject.ps1 (Vineflower)."
        "It is NOT original source code. Use Convert-112ToNeoForge262.ps1 for NeoForge 26.2 scaffolding."
        ""
        "## Next step"
        ""
        "Convert-112ToNeoForge262.ps1 -Path `"$OutputPath`" -OutputPath `"<empty-26.2-folder>`" -Compile"
    )
    Set-Content -Path (Join-Path $OutputPath 'README-DECOMPILED.md') -Value ($readmeLines -join [Environment]::NewLine) -Encoding UTF8

    $noteLines = @($hints.notes | ForEach-Object { "- $_" })
    if ($noteLines.Count -eq 0) { $noteLines = @('- (none)') }
    $reportLines = @(
        "# Decompile report"
        ""
        "- Jar: $JarPath"
        "- Output: $OutputPath"
        "- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        "- Vineflower: $VineflowerVersion"
        "- Java: $java"
        ""
        "## Detected metadata"
        ""
        "| Field | Value |"
        "|-------|-------|"
        "| Loader | $($hints.loader) |"
        "| mod_id | $($hints.mod_id) |"
        "| Name | $($hints.mod_name) |"
        "| Version | $($hints.mod_version) |"
        "| MC hint | $($hints.mc_hint) |"
        "| Mixins | $($hints.has_mixins) |"
        "| Java files | $($javaFiles.Count) |"
        ""
        "## Notes"
        ""
    ) + $noteLines + @(
        ""
        "## Pipeline"
        ""
        "1. Done: jar extract + decompile + src layout"
        "2. Optional: run Convert-112ToNeoForge262.ps1 on this folder to scaffold NeoForge 26.2"
        "3. Manual: fix decompile artifacts, deps, mixins, datapacks, GeckoLib paths, etc."
        ""
        "## Limits"
        ""
        "- Decompiled code is imperfect (generics, lambdas, switch, records)."
        "- Obfuscated jars may be unreadable."
        "- Fabric/Quilt jars are extracted but this converter targets Forge 1.12 -> NeoForge APIs."
        "- Original jar is never modified."
    )
    Set-Content -Path (Join-Path $OutputPath 'DECOMPILE_REPORT.md') -Value ($reportLines -join [Environment]::NewLine) -Encoding UTF8
    Write-Ok "Wrote DECOMPILE_REPORT.md"

    Write-Host ''
    Write-Host "Decompile complete: $OutputPath" -ForegroundColor Green
    Write-Host 'Original jar unchanged.' -ForegroundColor Green

    if ($ContinueToNeoForge262) {
        $converter = Join-Path $ToolRoot 'Convert-112ToNeoForge262.ps1'
        if (-not (Test-Path $converter)) { throw "Missing converter: $converter" }
        $baseOut = $OutputPath.TrimEnd('\', '/')
        $neoOut = $baseOut + '-26.2'
        if (Test-Path -LiteralPath $neoOut) {
            $i = 2
            while (Test-Path -LiteralPath ($baseOut + '-26.2-' + $i)) { $i++ }
            $neoOut = $baseOut + '-26.2-' + $i
        }
        Write-Step "Continuing to NeoForge 26.2 scaffold -> $neoOut"
        $cargs = @{
            Path             = $OutputPath
            OutputPath       = $neoOut
            MinecraftVersion = $MinecraftVersion
            NeoVersion       = $NeoVersion
        }
        if ($CompileAfterConvert) { & $converter @cargs -Compile }
        else { & $converter @cargs }
        Write-Ok "NeoForge scaffold: $neoOut"
    }
}
finally {
    if (Test-Path $work) {
        try { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}
