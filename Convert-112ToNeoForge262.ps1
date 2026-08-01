<#
.SYNOPSIS
  Experimental converter: Forge 1.12.2 workspace -> NeoForge 26.2 scaffold.

.DESCRIPTION
  Copies the project, writes ModDevGradle 26.2 files, applies mechanical 1.12
  package renames and stubs. This is NOT a full automatic port.

.EXAMPLE
  .\Convert-112ToNeoForge262.ps1 -Path "D:\mods\hospital-decompiled" -OutputPath "D:\mods\hospital-26.2"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$MinecraftVersion = '26.2',
    [string]$NeoVersion = '26.2.0.32-beta',
    [string]$ModDevGradleVersion = '2.0.141',
    [switch]$Compile,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot

function Write-Step([string]$m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok([string]$m) { Write-Host "    $m" -ForegroundColor Green }
function Write-Warn2([string]$m) { Write-Host "    WARN: $m" -ForegroundColor Yellow }
function Write-Info([string]$m) { Write-Host "    $m" }

function Copy-ProjectTree {
    param([string]$Source, [string]$Dest)
    $exclude = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('build', 'run', 'run-data', '.gradle', '.git', 'bin', 'out', '.idea'),
        [StringComparer]::OrdinalIgnoreCase
    )
    if (Test-Path -LiteralPath $Dest) {
        $items = @(Get-ChildItem -LiteralPath $Dest -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) { throw "Output folder not empty: $Dest" }
    }
    else {
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }
    $count = 0
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($Source)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        $rel = if ($cur.Length -le $Source.Length) { '' } else { $cur.Substring($Source.Length).TrimStart('\', '/') }
        $destDir = if ($rel) { Join-Path $Dest $rel } else { $Dest }
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        foreach ($item in Get-ChildItem -LiteralPath $cur -Force -ErrorAction SilentlyContinue) {
            if ($item.PSIsContainer) {
                if ($exclude.Contains($item.Name)) { continue }
                $stack.Push($item.FullName)
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $destDir $item.Name) -Force
                $count++
            }
        }
    }
    return $count
}

function Get-ModMeta112 {
    param([string]$Root)
    $meta = @{
        mod_id      = 'examplemod'
        mod_name    = 'Example Mod'
        mod_version = '1.0.0'
        mod_group   = 'com.example'
        mod_authors = 'Unknown'
        mod_license = 'All Rights Reserved'
        mod_desc    = 'Converted from Forge 1.12.2'
        mc_hint     = '1.12.2'
    }

    $mcmod = Get-ChildItem (Join-Path $Root 'src') -Recurse -Filter 'mcmod.info' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($mcmod) {
        try {
            $raw = Get-Content -LiteralPath $mcmod.FullName -Raw
            $j = $raw | ConvertFrom-Json
            $entry = if ($j -is [System.Array]) { $j[0] } else { $j }
            if ($entry.modid) { $meta.mod_id = [string]$entry.modid }
            if ($entry.name) { $meta.mod_name = [string]$entry.name }
            if ($entry.version) { $meta.mod_version = [string]$entry.version }
            if ($entry.mcversion) { $meta.mc_hint = [string]$entry.mcversion }
            if ($entry.description) { $meta.mod_desc = ([string]$entry.description) -replace '[\r\n]+', ' ' }
            if ($entry.authorList) {
                $meta.mod_authors = (($entry.authorList | ForEach-Object { "$_" }) -join ', ')
            }
        } catch {
            if ($raw -match '"modid"\s*:\s*"([^"]+)"') { $meta.mod_id = $Matches[1] }
            if ($raw -match '"name"\s*:\s*"([^"]+)"') { $meta.mod_name = $Matches[1] }
        }
    }

    # Prefer assets/<modid>
    if ($meta.mod_id -eq 'examplemod' -or $meta.mod_id -eq 'net') {
        $assets = Join-Path $Root 'src\main\resources\assets'
        if (Test-Path $assets) {
            $a = Get-ChildItem $assets -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'minecraft' } | Select-Object -First 1
            if ($a) { $meta.mod_id = $a.Name.ToLowerInvariant() }
        }
    }

    $java = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -ErrorAction SilentlyContinue |
        Select-String -Pattern '@Mod\(' -List | Select-Object -First 1
    if ($java) {
        $pkg = Select-String -Path $java.Path -Pattern '^package\s+([\w\.]+);' | Select-Object -First 1
        if ($pkg) { $meta.mod_group = $pkg.Matches[0].Groups[1].Value }
    }

    $meta.mod_id = ($meta.mod_id -replace '[^a-z0-9_]', '').ToLowerInvariant()
    if ($meta.mod_id.Length -lt 2) { $meta.mod_id = 'hospitalmod' }
    return $meta
}

function Write-GradleScaffold112 {
    param([string]$Root, [hashtable]$Meta)

    $props = @"
# Generated by Convert-112ToNeoForge262 (experimental 1.12.2 -> 26.2)
org.gradle.jvmargs=-Xmx4G
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.configuration-cache=false

minecraft_version=$MinecraftVersion
minecraft_version_range=[$MinecraftVersion]
neo_version=$NeoVersion

mod_id=$($Meta.mod_id)
mod_name=$($Meta.mod_name)
mod_license=$($Meta.mod_license)
mod_version=$($Meta.mod_version)+from112-mc$MinecraftVersion-neoforge
mod_group_id=$($Meta.mod_group)
mod_authors=$($Meta.mod_authors)
mod_description=$($Meta.mod_desc)
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'gradle.properties'), $props.Trim() + "`r`n")

    $settings = @"
pluginManagement {
    repositories {
        gradlePluginPortal()
        maven { url = 'https://maven.neoforged.net/releases' }
        mavenCentral()
    }
}
plugins {
    id 'org.gradle.toolchains.foojay-resolver-convention' version '1.0.0'
}
rootProject.name = '$($Meta.mod_id)-from112-neoforge-$MinecraftVersion'
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'settings.gradle'), $settings.Trim() + "`r`n")

    $build = @"
plugins {
    id 'java-library'
    id 'maven-publish'
    id 'net.neoforged.moddev' version '$ModDevGradleVersion'
    id 'idea'
}

tasks.named('wrapper', Wrapper).configure {
    distributionType = Wrapper.DistributionType.BIN
}

version = mod_version
group = mod_group_id

base {
    archivesName = mod_id
}

java.toolchain.languageVersion = JavaLanguageVersion.of(25)

sourceSets.main.resources {
    srcDir('src/generated/resources')
}

neoForge {
    version = project.neo_version

    runs {
        client {
            client()
            systemProperty 'neoforge.enabledGameTestNamespaces', project.mod_id
        }
        server {
            server()
            programArgument '--nogui'
        }
        configureEach {
            systemProperty 'forge.logging.markers', 'REGISTRIES'
            logLevel = org.slf4j.event.Level.DEBUG
        }
    }

    mods {
        "`${mod_id}" {
            sourceSet(sourceSets.main)
        }
    }
}

repositories {
    mavenCentral()
    maven { url = 'https://maven.neoforged.net/releases' }
}

dependencies {
    // Add libraries manually as you port (1.12 jars are not drop-in compatible)
}

var generateModMetadata = tasks.register('generateModMetadata', ProcessResources) {
    var replaceProperties = [
            minecraft_version      : minecraft_version,
            minecraft_version_range: minecraft_version_range,
            neo_version            : neo_version,
            mod_id                 : mod_id,
            mod_name               : mod_name,
            mod_license            : mod_license,
            mod_version            : mod_version,
            mod_authors            : mod_authors,
            mod_description        : mod_description
    ]
    inputs.properties replaceProperties
    expand replaceProperties
    from 'src/main/templates'
    into 'build/generated/sources/modMetadata'
}

sourceSets.main.resources.srcDir generateModMetadata
neoForge.ideSyncTask generateModMetadata

tasks.withType(JavaCompile).configureEach {
    options.encoding = 'UTF-8'
    options.release = 25
}

idea {
    module {
        downloadSources = true
        downloadJavadoc = true
    }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $Root 'build.gradle'), $build.Trim() + "`r`n")

    $tmplDir = Join-Path $Root 'src\main\templates\META-INF'
    New-Item -ItemType Directory -Force -Path $tmplDir | Out-Null
    $toml = @"
modLoader="javafml"
loaderVersion="[4,)"
license="`${mod_license}"

[[mods]]
modId="`${mod_id}"
version="`${mod_version}"
displayName="`${mod_name}"
authors="`${mod_authors}"
description='''`${mod_description}'''

[[dependencies.`${mod_id}]]
modId="neoforge"
type="required"
versionRange="[26.2,)"
ordering="NONE"
side="BOTH"

[[dependencies.`${mod_id}]]
modId="minecraft"
type="required"
versionRange="[26.2]"
ordering="NONE"
side="BOTH"
"@
    [System.IO.File]::WriteAllText((Join-Path $tmplDir 'neoforge.mods.toml'), $toml.Trim() + "`r`n")

    # Remove legacy mod metadata that pins old MC versions
    $resMeta = Join-Path $Root 'src\main\resources\META-INF'
    foreach ($n in @('mods.toml', 'neoforge.mods.toml', 'MANIFEST.MF')) {
        $p = Join-Path $resMeta $n
        if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
    }
    $mcmod = Join-Path $Root 'src\main\resources\mcmod.info'
    if (Test-Path $mcmod) {
        # keep as reference but rename so loader ignores it
        Move-Item $mcmod (Join-Path $Root 'src\main\resources\mcmod.info.112-reference') -Force -ErrorAction SilentlyContinue
    }

    $pack = Join-Path $Root 'src\main\resources\pack.mcmeta'
    $packJson = @"
{
  "pack": {
    "description": "$($Meta.mod_name) resources",
    "pack_format": 107
  }
}
"@
    [System.IO.File]::WriteAllText($pack, $packJson.Trim() + "`r`n")
}

function Invoke-112MechanicalRewrites {
    param([string]$Root)
    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    $touched = 0
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- Classic 1.12 package -> modern Minecraft packages ---
        $t = $t -replace 'import\s+net\.minecraft\.item\.', 'import net.minecraft.world.item.'
        $t = $t -replace 'import\s+net\.minecraft\.block\.material\.', 'import net.minecraft.world.level.material.'
        $t = $t -replace 'import\s+net\.minecraft\.block\.state\.', 'import net.minecraft.world.level.block.state.'
        $t = $t -replace 'import\s+net\.minecraft\.block\.', 'import net.minecraft.world.level.block.'
        $t = $t -replace 'import\s+net\.minecraft\.entity\.player\.', 'import net.minecraft.world.entity.player.'
        $t = $t -replace 'import\s+net\.minecraft\.entity\.', 'import net.minecraft.world.entity.'
        $t = $t -replace 'import\s+net\.minecraft\.util\.math\.', 'import net.minecraft.core.'
        $t = $t -replace 'import\s+net\.minecraft\.util\.ResourceLocation\b', 'import net.minecraft.resources.Identifier'
        $t = $t -replace 'import\s+net\.minecraft\.util\.SoundEvent\b', 'import net.minecraft.sounds.SoundEvent'
        $t = $t -replace 'import\s+net\.minecraft\.util\.SoundCategory\b', 'import net.minecraft.sounds.SoundSource'
        $t = $t -replace 'import\s+net\.minecraft\.world\.World\b', 'import net.minecraft.world.level.Level'
        $t = $t -replace 'import\s+net\.minecraft\.world\.WorldServer\b', 'import net.minecraft.server.level.ServerLevel'
        $t = $t -replace 'import\s+net\.minecraft\.world\.biome\.', 'import net.minecraft.world.level.biome.'
        $t = $t -replace 'import\s+net\.minecraft\.creativetab\.', 'import net.minecraft.world.item.'
        $t = $t -replace 'import\s+net\.minecraft\.nbt\.', 'import net.minecraft.nbt.'
        $t = $t -replace 'import\s+net\.minecraft\.potion\.', 'import net.minecraft.world.effect.'
        $t = $t -replace 'import\s+net\.minecraft\.inventory\.', 'import net.minecraft.world.inventory.'
        $t = $t -replace 'import\s+net\.minecraft\.tileentity\.', 'import net.minecraft.world.level.block.entity.'

        # FQN renames (after imports)
        $t = $t -replace '\bnet\.minecraft\.item\.', 'net.minecraft.world.item.'
        $t = $t -replace '\bnet\.minecraft\.block\.state\.', 'net.minecraft.world.level.block.state.'
        $t = $t -replace '\bnet\.minecraft\.block\.material\.', 'net.minecraft.world.level.material.'
        $t = $t -replace '\bnet\.minecraft\.block\.', 'net.minecraft.world.level.block.'
        $t = $t -replace '\bnet\.minecraft\.entity\.player\.', 'net.minecraft.world.entity.player.'
        $t = $t -replace '\bnet\.minecraft\.entity\.', 'net.minecraft.world.entity.'
        $t = $t -replace '\bnet\.minecraft\.util\.math\.', 'net.minecraft.core.'
        $t = $t -replace '\bnet\.minecraft\.util\.ResourceLocation\b', 'net.minecraft.resources.Identifier'
        $t = $t -replace '\bResourceLocation\b', 'Identifier'
        $t = $t -replace '\bnet\.minecraft\.world\.World\b', 'net.minecraft.world.level.Level'
        $t = $t -replace '(?<![\w.])\bWorld\b(?!\s*\.)', 'Level'
        $t = $t -replace '\bEntityPlayer\b', 'Player'
        $t = $t -replace '\bEntityPlayerMP\b', 'ServerPlayer'
        $t = $t -replace '\bTileEntity\b', 'BlockEntity'
        $t = $t -replace '\bIBlockState\b', 'BlockState'
        $t = $t -replace '\bItemStack\b', 'ItemStack'  # same name modern

        # Forge -> NeoForge packages (NEVER map fml.common.event - those types do not exist)
        $t = $t -replace 'net\.minecraftforge\.fml\.common\.Mod\b', 'net.neoforged.fml.common.Mod'
        $t = $t -replace 'net\.minecraftforge\.fml\.relauncher\.', 'net.neoforged.api.distmarker.'
        $t = $t -replace 'net\.minecraftforge\.fml\.common\.network\.', 'net.neoforged.neoforge.network.'
        $t = $t -replace 'net\.minecraftforge\.common\.', 'net.neoforged.neoforge.common.'
        $t = $t -replace 'net\.minecraftforge\.client\.', 'net.neoforged.neoforge.client.'
        $t = $t -replace 'net\.minecraftforge\.event\.', 'net.neoforged.neoforge.event.'
        $t = $t -replace 'net\.minecraftforge\.registries\.', 'net.neoforged.neoforge.registries.'
        $t = $t -replace 'net\.minecraftforge\.items\.', 'net.neoforged.neoforge.items.'
        # Leave net.minecraftforge.fml.common.event.* alone but mark it
        if ($t -match 'net\.minecraftforge\.fml\.common\.event\.|net\.neoforged\.fml\.common\.event\.') {
            # Undo accidental neoforged fml.common.event renames from broad replaces
            $t = $t -replace 'net\.neoforged\.fml\.common\.event\.', 'net.minecraftforge.fml.common.event.'
            if ($t -notmatch 'TODO_112_LIFECYCLE') {
                $nl = [Environment]::NewLine
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_LIFECYCLE: FML pre/init/post events do not exist on NeoForge 26.2 - rewrite to mod constructor + IEventBus.' + $nl)
            }
        }

        # Side / SideOnly
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.relauncher\.Side\b', 'import net.neoforged.api.distmarker.Dist'
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.relauncher\.SideOnly\b', 'import net.neoforged.api.distmarker.OnlyIn'
        $t = $t -replace '@SideOnly\s*\(\s*Side\.CLIENT\s*\)', '@OnlyIn(Dist.CLIENT)'
        $t = $t -replace '@SideOnly\s*\(\s*Side\.SERVER\s*\)', '@OnlyIn(Dist.DEDICATED_SERVER)'
        $t = $t -replace '\bSide\.CLIENT\b', 'Dist.CLIENT'
        $t = $t -replace '\bSide\.SERVER\b', 'Dist.DEDICATED_SERVER'

        # Dead 1.12 API flags
        $nl = [Environment]::NewLine
        $t = $t -replace '\bIFuelHandler\b', '/* TODO_112_REMOVED IFuelHandler */ Object'
        $t = $t -replace '\bIWorldGenerator\b', '/* TODO_112_REMOVED IWorldGenerator */ Object'
        $t = $t -replace '\bGameRegistry\.', '/* TODO_112_GameRegistry */ GameRegistry.'
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.common\.registry\.GameRegistry\s*;',
            ('// TODO_112: GameRegistry removed - use DeferredRegister' + $nl + '// import GameRegistry;')
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.common\.IFuelHandler\s*;',
            ('// TODO_112: IFuelHandler removed' + $nl + '// import IFuelHandler;')
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.common\.IWorldGenerator\s*;',
            ('// TODO_112: IWorldGenerator removed' + $nl + '// import IWorldGenerator;')

        # Model / client 1.12 leftovers
        $t = $t -replace 'import\s+net\.minecraftforge\.client\.model\.obj\.OBJLoader\s*;',
            ('// TODO_112_CLIENT: OBJLoader API changed - port models manually' + $nl + '// import OBJLoader;')
        $t = $t -replace 'OBJLoader\.INSTANCE', '/* TODO_112_CLIENT OBJLoader.INSTANCE */ null'

        # Proxy pattern notes
        if ($t -match 'IProxy|CommonProxy|ClientProxy|ServerProxy|preInit\s*\(\s*FML' ) {
            if ($t -notmatch 'TODO_112_PROXY') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_PROXY: Client/Common proxy pattern is obsolete - use event bus only.' + $nl)
            }
        }

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Install-WrapperIfPossible {
    param([string]$Root)
    $candidates = @(
        'F:\GrokBuild Working Folder\Buildpaste\_LegacyJavaConverter',
        (Join-Path $ToolRoot '..')
    )
    foreach ($c in $candidates) {
        # Prefer any nearby project with gradle wrapper
    }
    $refs = Get-ChildItem 'F:\GrokBuild Working Folder' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '26\.2|MOA|Hospital' } |
        Select-Object -First 20
    foreach ($r in $refs) {
        $g = Join-Path $r.FullName 'gradlew.bat'
        $gw = Join-Path $r.FullName 'gradle\wrapper'
        if ((Test-Path $g) -and (Test-Path $gw)) {
            Copy-Item $g $Root -Force
            if (Test-Path (Join-Path $r.FullName 'gradlew')) {
                Copy-Item (Join-Path $r.FullName 'gradlew') $Root -Force
            }
            $destW = Join-Path $Root 'gradle\wrapper'
            New-Item -ItemType Directory -Force -Path $destW | Out-Null
            Copy-Item (Join-Path $gw '*') $destW -Force
            Write-Ok "Gradle wrapper copied from $($r.FullName)"
            return
        }
    }
    Write-Warn2 'No local Gradle wrapper found to copy. Run gradle wrapper manually or copy from an MDK.'
}

# -------------------- main --------------------
if (-not [IO.Path]::IsPathRooted($Path)) { $Path = Join-Path (Get-Location) $Path }
$Source = [IO.Path]::GetFullPath($Path)
if (-not (Test-Path (Join-Path $Source 'src'))) { throw "No src/ under $Source" }
if (-not [IO.Path]::IsPathRooted($OutputPath)) { $OutputPath = Join-Path (Get-Location) $OutputPath }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

Write-Host ''
Write-Host 'RB 1.12 -> NeoForge 26.2 Converter (EXPERIMENTAL)' -ForegroundColor White
Write-Host "  Source : $Source"
Write-Host "  Output : $OutputPath"
Write-Host "  Target : Minecraft $MinecraftVersion / NeoForge $NeoVersion"

if ($DryRun) {
    Write-Host '  DryRun : yes' -ForegroundColor Yellow
    Write-Host 'Would copy project, write 26.2 scaffold, apply 1.12 mechanical rewrites.' -ForegroundColor Cyan
    return
}

Write-Step 'Copying project (original preserved)'
$n = Copy-ProjectTree -Source $Source -Dest $OutputPath
Write-Ok "Copied $n files"

$meta = Get-ModMeta112 -Root $Source
Write-Info "mod_id=$($meta.mod_id) name=$($meta.mod_name) mc_hint=$($meta.mc_hint) group=$($meta.mod_group)"

Write-Step 'Writing NeoForge 26.2 Gradle scaffold'
Write-GradleScaffold112 -Root $OutputPath -Meta $meta
Write-Ok 'build.gradle / settings.gradle / gradle.properties / templates/neoforge.mods.toml'

Write-Step '1.12 mechanical rewrites (packages, Identifier, lifecycle notes)'
$j = Invoke-112MechanicalRewrites -Root $OutputPath
Write-Ok "Touched $j Java file(s)"

Write-Step 'Gradle wrapper'
Install-WrapperIfPossible -Root $OutputPath

$reportPath = Join-Path $OutputPath 'MIGRATION_112_REPORT.md'
$gen = Get-Date -Format 'yyyy-MM-dd HH:mm'
$report = @"
# Migration report (Forge 1.12.2 to NeoForge 26.2): $($meta.mod_id)

- Source: $Source
- Output: $OutputPath
- Target: Minecraft $MinecraftVersion / NeoForge $NeoVersion
- Detected MC hint: $($meta.mc_hint)
- Generated: $gen

## Automated

1. Project copy (original unchanged)
2. ModDevGradle 26.2 scaffold (Java 25)
3. Metadata from mcmod.info / assets when available
4. Mechanical package renames (1.12 to modern world/core packages)
5. ResourceLocation to Identifier
6. World / EntityPlayer type renames (mechanical)
7. Forge to NeoForge package renames except fml.common.event (left flagged)
8. SideOnly to OnlyIn/Dist notes
9. Flags for removed APIs: GameRegistry, IFuelHandler, IWorldGenerator, OBJLoader
10. Legacy mcmod.info renamed to mcmod.info.112-reference; loader uses templates for [26.2]

## You must still fix manually

- Proxy + FML pre/init/post lifecycle to @Mod constructor + IEventBus
- All registrations (blocks/items/entities) to DeferredRegister
- World gen, fuels, recipes
- Client models (JSON blockstates / items; OBJ pipeline)
- Tile entities / GUIs / packets
- Remaining compile errors after gradlew compileJava
- Runtime testing on NeoForge 26.2

## Next

cd "$OutputPath"
.\gradlew.bat compileJava --stacktrace

Scaffold success is not compile success. 1.12 to 26.2 is a multi-year API gap; use this output as a starting workspace, not a finished mod.
"@
[System.IO.File]::WriteAllText($reportPath, $report)
Write-Ok "Wrote $reportPath"

if ($Compile) {
    Write-Step 'Running compileJava (diagnostic only)'
    Push-Location $OutputPath
    try {
        if (Test-Path '.\gradlew.bat') {
            cmd /c "gradlew.bat compileJava --no-daemon --stacktrace > compile-errors.log 2>&1"
            Write-Host "Gradle exit: $LASTEXITCODE"
            if (Test-Path 'compile-errors.log') {
                Get-Content 'compile-errors.log' -Tail 30 | ForEach-Object { Write-Host "    $_" }
            }
        } else {
            Write-Warn2 'No gradlew.bat - skipped compile'
        }
    } finally { Pop-Location }
}

Write-Host ''
Write-Host "1.12 conversion scaffold complete: $OutputPath" -ForegroundColor Green
Write-Host 'Original unchanged. Expect remaining compile errors on large mods.' -ForegroundColor Yellow
exit 0
