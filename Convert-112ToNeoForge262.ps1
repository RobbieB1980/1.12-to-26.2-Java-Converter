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
    // Surface full 1.12→26.2 error volume (default javac cap is 100)
    options.compilerArgs.addAll(['-Xmaxerrs', '10000', '-Xmaxwarns', '10000'])
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

function Write-Stub112Sources {
    param([string]$Root)
    $dir = Join-Path $Root 'src\main\java\rb\converter\stub112'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $nl = "`r`n"
    $files = @{
        'FMLPreInitializationEvent.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 FMLPreInitializationEvent (not present on NeoForge 26.2). */
public final class FMLPreInitializationEvent {
    public ASMDataTable getAsmData() { return new ASMDataTable(); }
    public java.io.File getModConfigurationDirectory() { return new java.io.File("."); }
    public java.io.File getSuggestedConfigurationFile() { return new java.io.File("stub.cfg"); }
    public org.apache.logging.log4j.Logger getModLog() { return org.apache.logging.log4j.LogManager.getLogger("stub112"); }
}
'@
        'FMLInitializationEvent.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 FMLInitializationEvent. */
public final class FMLInitializationEvent {}
'@
        'FMLPostInitializationEvent.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 FMLPostInitializationEvent. */
public final class FMLPostInitializationEvent {}
'@
        'FMLServerStartingEvent.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 FMLServerStartingEvent. */
public final class FMLServerStartingEvent {}
'@
        'ASMDataTable.java' = @'
package rb.converter.stub112;

import java.util.Collections;
import java.util.Set;

/** Stage A stub for FML annotation scanning. */
public final class ASMDataTable {
    public static final class ASMData {
        public String getClassName() { return ""; }
    }
    public Set<ASMData> getAll(String annotationClassName) { return Collections.emptySet(); }
}
'@
        'ModelRegistryEvent.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 ModelRegistryEvent (client model bake pipeline changed). */
public final class ModelRegistryEvent {}
'@
        'IGuiHandler.java' = @'
package rb.converter.stub112;

import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;

/** Stage A stub: 1.12 IGuiHandler replaced by MenuType / Screen registration. */
public interface IGuiHandler {
    Object getServerGuiElement(int id, Player player, Level level, int x, int y, int z);
    Object getClientGuiElement(int id, Player player, Level level, int x, int y, int z);
}
'@
        'GameRegistry.java' = @'
package rb.converter.stub112;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Stage A stub: 1.12 GameRegistry.
 * Real registration must move to DeferredRegister / event bus.
 */
public final class GameRegistry {
    private GameRegistry() {}

    @Retention(RetentionPolicy.RUNTIME)
    @Target({ElementType.TYPE, ElementType.FIELD})
    public @interface ObjectHolder {
        String value();
    }

    public static void registerWorldGenerator(Object generator, int weight) {
        /* no-op stub */
    }

    public static void registerFuelHandler(Object handler) {
        /* no-op stub */
    }
}
'@
        'EntityEntry.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 EntityEntry registry type. */
public final class EntityEntry {}
'@
        'IForgeRegistryEntry.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 IForgeRegistryEntry. */
public interface IForgeRegistryEntry {
    IForgeRegistryEntry setRegistryName(String name);
    Object getRegistryName();
}
'@
        'RegistryEvent.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 RegistryEvent.Register (use DeferredRegister on 26.2). */
public final class RegistryEvent {
    private RegistryEvent() {}

    public static final class Register<T> {
        public IForgeRegistry<T> getRegistry() { return new IForgeRegistry<>(); }
    }

    public static final class IForgeRegistry<T> {
        /** Accept Object arrays so legacy (IForgeRegistryEntry[]) casts still compile. */
        public void registerAll(Object... values) { /* no-op */ }
        public void register(Object value) { /* no-op */ }
    }
}
'@
        'NetworkRegistry.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 NetworkRegistry / SimpleChannel era networking. */
public final class NetworkRegistry {
    public static final NetworkRegistry INSTANCE = new NetworkRegistry();
    private NetworkRegistry() {}
    public SimpleNetworkWrapper newSimpleChannel(String name) { return new SimpleNetworkWrapper(name); }
    public void registerGuiHandler(Object mod, IGuiHandler handler) { /* no-op */ }
}
'@
        'SimpleNetworkWrapper.java' = @'
package rb.converter.stub112;

/** Stage A stub for 1.12 SimpleNetworkWrapper. */
public final class SimpleNetworkWrapper {
    public SimpleNetworkWrapper(String name) {}
    public <REQ extends IMessage, REPLY extends IMessage> void registerMessage(
            Class<? extends IMessageHandler<REQ, REPLY>> messageHandler,
            Class<REQ> requestMessageType,
            int discriminator,
            Object side) { /* no-op */ }
    public void sendTo(IMessage message, Object player) { /* no-op */ }
    public void sendToServer(IMessage message) { /* no-op */ }
    public void sendToAll(IMessage message) { /* no-op */ }
}
'@
        'IMessage.java' = @'
package rb.converter.stub112;

/** Stage A stub for 1.12 IMessage. */
public interface IMessage {}
'@
        'IMessageHandler.java' = @'
package rb.converter.stub112;

/** Stage A stub for 1.12 IMessageHandler. */
public interface IMessageHandler<REQ extends IMessage, REPLY extends IMessage> {
    REPLY onMessage(REQ message, Object ctx);
}
'@
        'MessageContext.java' = @'
package rb.converter.stub112;

/** Stage A stub for 1.12 simpleimpl.MessageContext. */
public final class MessageContext {
    public Object side;
    public Object getServerHandler() { return null; }
}
'@
        'ByteBufUtils.java' = @'
package rb.converter.stub112;

import io.netty.buffer.ByteBuf;

/** Stage A stub for 1.12 ByteBufUtils. */
public final class ByteBufUtils {
    private ByteBufUtils() {}
    public static void writeUTF8String(ByteBuf buf, String s) {}
    public static String readUTF8String(ByteBuf buf) { return ""; }
    public static void writeTag(ByteBuf buf, Object tag) {}
    public static Object readTag(ByteBuf buf) { return null; }
}
'@
        'FluidRegistry.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 FluidRegistry. */
public final class FluidRegistry {
    private FluidRegistry() {}
    public static void enableUniversalBucket() { /* no-op */ }
}
'@
        'SidedProxy.java' = @'
package rb.converter.stub112;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** Stage A stub: @SidedProxy removed on modern loaders. */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.FIELD)
public @interface SidedProxy {
    String clientSide() default "";
    String serverSide() default "";
}
'@
        'ModelLoader.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 ModelLoader client helpers. */
public final class ModelLoader {
    private ModelLoader() {}
    public static void setCustomModelResourceLocation(Object item, int meta, Object location) { /* no-op */ }
}
'@
        'ModelResourceLocation.java' = @'
package rb.converter.stub112;

/** Stage A stub for 1.12 ModelResourceLocation. */
public final class ModelResourceLocation {
    public ModelResourceLocation(String path, String variant) {}
    public ModelResourceLocation(Object location, String variant) {}
}
'@
        'IChunkProvider.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 world-gen chunk provider. */
public interface IChunkProvider {}
'@
        'IChunkGenerator.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 world-gen chunk generator. */
public interface IChunkGenerator {}
'@
        'WorldSavedData.java' = @'
package rb.converter.stub112;

/** Stage A stub: 1.12 WorldSavedData (modern: SavedData). */
public class WorldSavedData {
    public WorldSavedData(String name) {}
    public void markDirty() {}
}
'@
        'SubscribeEvent.java' = @'
package rb.converter.stub112;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** Stage A stub redirect; prefer net.neoforged.bus.api.SubscribeEvent when wiring real buses. */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface SubscribeEvent {}
'@
        'PlayerLoggedInEvent.java' = @'
package rb.converter.stub112;

import net.minecraft.world.entity.player.Player;

/** Stage A stub for 1.12 PlayerEvent.PlayerLoggedInEvent. */
public class PlayerLoggedInEvent {
    public Player player;
}
'@
        'PlayerChangedDimensionEvent.java' = @'
package rb.converter.stub112;

import net.minecraft.world.entity.player.Player;

/** Stage A stub for 1.12 PlayerEvent.PlayerChangedDimensionEvent. */
public class PlayerChangedDimensionEvent {
    public Player player;
}
'@
    }

    $count = 0
    foreach ($name in $files.Keys) {
        $path = Join-Path $dir $name
        [System.IO.File]::WriteAllText($path, ($files[$name].Trim() + $nl))
        $count++
    }
    return $count
}

function Invoke-112ProxyStubPass {
    param([string]$Root)
    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { return 0 }
    $touched = 0
    $files = Get-ChildItem $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $name = $f.Name
        $isIProxy = $name -match '^IProxy'
        $isClientProxy = $name -match '^ClientProxy'
        $isServerProxy = $name -match '^ServerProxy'
        $isCommonProxy = $name -match '^CommonProxy'
        if (-not ($isIProxy -or $isClientProxy -or $isServerProxy -or $isCommonProxy)) { continue }

        $raw = [System.IO.File]::ReadAllText($f.FullName)
        $pkg = 'unknown'
        if ($raw -match '(?m)^package\s+([\w.]+)\s*;') { $pkg = $Matches[1] }
        $simple = [IO.Path]::GetFileNameWithoutExtension($name)
        $ifaceName = $null
        if ($raw -match 'implements\s+(IProxy\w+)') { $ifaceName = $Matches[1] }
        elseif ($isIProxy) { $ifaceName = $simple }

        $nl = "`r`n"
        if ($isIProxy) {
            $body = @"
package $pkg;

// Stage A: 1.12 IProxy removed - empty hook surface for any leftover references.
public interface $simple {
    default void preInit() {}
    default void init() {}
    default void postInit() {}
    default void serverLoad() {}
}
"@
        }
        elseif ($ifaceName) {
            $body = @"
package $pkg;

// Stage A: 1.12 $($simple) stubbed (SidedProxy obsolete on NeoForge 26.2).
public class $simple implements $ifaceName {
    @Override public void preInit() {}
    @Override public void init() {}
    @Override public void postInit() {}
    @Override public void serverLoad() {}
}
"@
        }
        else {
            $body = @"
package $pkg;

// Stage A: 1.12 proxy class stubbed.
public class $simple {
    public void preInit() {}
    public void init() {}
    public void postInit() {}
    public void serverLoad() {}
}
"@
        }
        [System.IO.File]::WriteAllText($f.FullName, $body.Trim() + $nl)
        $touched++
    }
    return $touched
}

function Invoke-112ModConstructorPass {
    param([string]$Root)
    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { return 0 }
    $touched = 0
    $modFiles = Get-ChildItem $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Where-Object { Select-String -Path $_.FullName -Pattern '@Mod\s*\(' -Quiet }
    foreach ($f in $modFiles) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t
        if ($t -match 'TODO_112_STAGE_A_MOD') { continue }

        $className = $null
        if ($t -match 'public\s+class\s+(\w+)') { $className = $Matches[1] }
        if (-not $className) { continue }

        # Annotation values must be compile-time constants; prefer string literal over bare MODID.
        $modIdLiteral = "`"$className`""
        if ($t -match 'public\s+static\s+final\s+String\s+MODID\s*=\s*("[^"]+")') {
            $modIdLiteral = $Matches[1]
        }
        elseif ($t -match '@Mod\s*\([^)]*modid\s*=\s*("([^"]+)")') {
            $modIdLiteral = $Matches[1]
        }
        elseif ($t -match '@Mod\s*\(\s*("([^"]+)")\s*\)') {
            $modIdLiteral = $Matches[1]
        }

        # Modern @Mod annotation (value = mod id string literal)
        $t = $t -replace '@Mod\s*\([^)]*\)', "@Mod($modIdLiteral)"

        # Drop SidedProxy field block
        $t = $t -replace '(?s)\s*@SidedProxy\s*\([^)]*\)\s*public\s+static\s+\w+\s+proxy\s*;', ''
        $t = $t -replace '(?s)\s*@rb\.converter\.stub112\.SidedProxy\s*\([^)]*\)\s*public\s+static\s+\w+\s+proxy\s*;', ''
        # Drop @Instance field if present (keep static instance if assigned in ctor)
        $t = $t -replace '(?m)^\s*@Instance\s*\([^)]*\)\s*\r?\n', ''
        $t = $t -replace '(?m)^\s*@net\.neoforged\.fml\.common\.Mod\.Instance\s*\([^)]*\)\s*\r?\n', ''

        # Remove FML @EventHandler lifecycle methods (bodies often reference proxy/FML types)
        $t = $t -replace '(?s)\s*@EventHandler\s+public\s+void\s+preInit\s*\([^)]*\)\s*\{.*?\n\s*\}', ''
        $t = $t -replace '(?s)\s*@EventHandler\s+public\s+void\s+init\s*\([^)]*\)\s*\{.*?\n\s*\}', ''
        $t = $t -replace '(?s)\s*@EventHandler\s+public\s+void\s+postInit\s*\([^)]*\)\s*\{.*?\n\s*\}', ''
        $t = $t -replace '(?s)\s*@EventHandler\s+public\s+void\s+serverLoad\s*\([^)]*\)\s*\{.*?\n\s*\}', ''
        $t = $t -replace '(?s)\s*@Mod\.EventHandler\s+public\s+void\s+preInit\s*\([^)]*\)\s*\{.*?\n\s*\}', ''
        $t = $t -replace '(?s)\s*@Mod\.EventHandler\s+public\s+void\s+init\s*\([^)]*\)\s*\{.*?\n\s*\}', ''
        $t = $t -replace '(?s)\s*@Mod\.EventHandler\s+public\s+void\s+postInit\s*\([^)]*\)\s*\{.*?\n\s*\}', ''
        $t = $t -replace '(?s)\s*@Mod\.EventHandler\s+public\s+void\s+serverLoad\s*\([^)]*\)\s*\{.*?\n\s*\}', ''

        # Ensure required imports for Stage A constructor
        $needImports = @(
            'import net.neoforged.bus.api.IEventBus;',
            'import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;',
            'import net.neoforged.fml.common.Mod;'
        )
        foreach ($imp in $needImports) {
            if ($t -notmatch [regex]::Escape($imp)) {
                if ($t -match '(?m)^package\s+[^;]+;\s*') {
                    $t = $t -replace '(?m)^(package\s+[^;]+;\s*)', ('$1' + "`r`n" + $imp + "`r`n")
                }
            }
        }

        # Strip obsolete imports that no longer apply after EventHandler removal
        $t = $t -replace '(?m)^import\s+net\.minecraftforge\.fml\.common\.event\.\w+;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+rb\.converter\.stub112\.FML\w+;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+net\.minecraftforge\.fml\.common\.SidedProxy;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+rb\.converter\.stub112\.SidedProxy;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+net\.neoforged\.fml\.common\.Mod\.EventHandler;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+net\.minecraftforge\.fml\.common\.Mod\.EventHandler;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+net\.neoforged\.fml\.common\.Mod\.Instance;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+net\.minecraftforge\.fml\.common\.Mod\.Instance;\s*\r?\n', ''

        if ($t -notmatch [regex]::Escape("public $className(IEventBus")) {
            $ctor = @"

    // TODO_112_STAGE_A_MOD: modern NeoForge entry - expand DeferredRegister / setup here.
    public $className(IEventBus modEventBus) {
        instance = this;
        modEventBus.addListener(this::commonSetup);
        // Legacy 1.12 registry subscribers are retained as compile stubs only.
        if (this.elements != null) {
            try { this.elements.preInit(); } catch (Throwable ignored) { /* Stage A soft-call */ }
        }
    }

    private void commonSetup(final FMLCommonSetupEvent event) {
        // TODO_112: move former init/postInit / NetworkRegistry work here.
    }
"@
            # Prefer insert after first field block — after class opening and early fields
            if ($t -match "(?s)(public\s+class\s+$className\s*\{)") {
                # Insert after elements field if present, else after class brace content start
                if ($t -match '(?m)^(\s*public\s+\w+\s+elements\s*=\s*new\s+\w+\s*\(\s*\)\s*;\s*)$') {
                    $t = $t -replace '(?m)^(\s*public\s+\w+\s+elements\s*=\s*new\s+\w+\s*\(\s*\)\s*;\s*)$', ('$1' + "`r`n" + $ctor)
                }
                else {
                    $t = $t -replace "(public\s+class\s+$className\s*\{)", ('$1' + "`r`n" + $ctor)
                }
            }
        }

        # Soft-call proxy usages if any remain
        $t = $t -replace '\bproxy\.preInit\s*\([^)]*\)\s*;', '/* proxy removed */;'
        $t = $t -replace '\bproxy\.init\s*\([^)]*\)\s*;', '/* proxy removed */;'
        $t = $t -replace '\bproxy\.postInit\s*\([^)]*\)\s*;', '/* proxy removed */;'
        $t = $t -replace '\bproxy\.serverLoad\s*\([^)]*\)\s*;', '/* proxy removed */;'

        # Elements lifecycle often took FML event — call no-arg after Stage A signature change
        $t = $t -replace '\.preInit\s*\(\s*event\s*\)', '.preInit()'
        $t = $t -replace '\.init\s*\(\s*event\s*\)', '.init()'
        $t = $t -replace '\.serverLoad\s*\(\s*event\s*\)', '.serverLoad()'
        $t = $t -replace 'element\s*->\s*element\.preInit\s*\(\s*event\s*\)', 'element -> element.preInit()'
        $t = $t -replace 'element\s*->\s*element\.init\s*\(\s*event\s*\)', 'element -> element.init()'
        $t = $t -replace 'element\s*->\s*element\.serverLoad\s*\(\s*event\s*\)', 'element -> element.serverLoad()'

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-112MechanicalRewrites {
    param([string]$Root)
    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]rb[\\/]converter[\\/]stub112[\\/]' }
    $touched = 0
    $nl = [Environment]::NewLine
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- Classic 1.12 package -> modern Minecraft packages ---
        $t = $t -replace 'import\s+net\.minecraft\.item\.', 'import net.minecraft.world.item.'
        $t = $t -replace 'import\s+net\.minecraft\.block\.material\.', 'import net.minecraft.world.level.material.'
        $t = $t -replace 'import\s+net\.minecraft\.block\.state\.', 'import net.minecraft.world.level.block.state.'
        $t = $t -replace 'import\s+net\.minecraft\.block\.', 'import net.minecraft.world.level.block.'
        # ServerPlayer / EntityPlayerMP before broad entity.player rewrite
        $t = $t -replace 'import\s+net\.minecraft\.entity\.player\.EntityPlayerMP\s*;', 'import net.minecraft.server.level.ServerPlayer;'
        $t = $t -replace 'import\s+net\.minecraft\.entity\.player\.EntityPlayer\s*;', 'import net.minecraft.world.entity.player.Player;'
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
        # Potion -> MobEffect (not world.effect.Potion)
        $t = $t -replace 'import\s+net\.minecraft\.potion\.PotionEffect\s*;', 'import net.minecraft.world.effect.MobEffectInstance;'
        $t = $t -replace 'import\s+net\.minecraft\.potion\.Potion\s*;', 'import net.minecraft.world.effect.MobEffect;'
        $t = $t -replace 'import\s+net\.minecraft\.potion\.', 'import net.minecraft.world.effect.'
        $t = $t -replace 'import\s+net\.minecraft\.inventory\.', 'import net.minecraft.world.inventory.'
        $t = $t -replace 'import\s+net\.minecraft\.tileentity\.', 'import net.minecraft.world.level.block.entity.'

        # Fix bad prior-pass renames
        $t = $t -replace 'import\s+net\.minecraft\.world\.entity\.player\.ServerPlayer\s*;', 'import net.minecraft.server.level.ServerPlayer;'
        $t = $t -replace 'import\s+net\.minecraft\.world\.effect\.PotionEffect\s*;', 'import net.minecraft.world.effect.MobEffectInstance;'
        $t = $t -replace 'import\s+net\.minecraft\.world\.effect\.Potion\s*;', 'import net.minecraft.world.effect.MobEffect;'

        # FQN renames (after imports)
        $t = $t -replace '\bnet\.minecraft\.item\.', 'net.minecraft.world.item.'
        $t = $t -replace '\bnet\.minecraft\.block\.state\.', 'net.minecraft.world.level.block.state.'
        $t = $t -replace '\bnet\.minecraft\.block\.material\.', 'net.minecraft.world.level.material.'
        $t = $t -replace '\bnet\.minecraft\.block\.', 'net.minecraft.world.level.block.'
        $t = $t -replace '\bnet\.minecraft\.entity\.player\.EntityPlayerMP\b', 'net.minecraft.server.level.ServerPlayer'
        $t = $t -replace '\bnet\.minecraft\.entity\.player\.', 'net.minecraft.world.entity.player.'
        $t = $t -replace '\bnet\.minecraft\.entity\.', 'net.minecraft.world.entity.'
        $t = $t -replace '\bnet\.minecraft\.util\.math\.', 'net.minecraft.core.'
        $t = $t -replace '\bnet\.minecraft\.util\.ResourceLocation\b', 'net.minecraft.resources.Identifier'
        $t = $t -replace '\bResourceLocation\b', 'Identifier'
        $t = $t -replace '\bnet\.minecraft\.world\.World\b', 'net.minecraft.world.level.Level'
        $t = $t -replace '(?<![\w.])\bWorld\b(?!\s*\.)', 'Level'
        $t = $t -replace '\bEntityPlayerMP\b', 'ServerPlayer'
        $t = $t -replace '\bEntityPlayer\b', 'Player'
        $t = $t -replace '\bTileEntity\b', 'BlockEntity'
        $t = $t -replace '\bIBlockState\b', 'BlockState'
        # Potion type renames (avoid double-rewriting MobEffect*)
        $t = $t -replace '(?<![\w.])PotionEffect\b', 'MobEffectInstance'
        $t = $t -replace '(?<![\w.])Potion\b', 'MobEffect'

        # Side / SideOnly BEFORE broad relauncher rewrite (Side is Dist, not distmarker.Side)
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.relauncher\.SideOnly\s*;', 'import net.neoforged.api.distmarker.OnlyIn;'
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.relauncher\.Side\s*;', 'import net.neoforged.api.distmarker.Dist;'
        $t = $t -replace 'import\s+net\.neoforged\.api\.distmarker\.SideOnly\s*;', 'import net.neoforged.api.distmarker.OnlyIn;'
        $t = $t -replace 'import\s+net\.neoforged\.api\.distmarker\.Side\s*;', 'import net.neoforged.api.distmarker.Dist;'
        $t = $t -replace '@SideOnly\s*\(\s*Side\.CLIENT\s*\)', '@OnlyIn(Dist.CLIENT)'
        $t = $t -replace '@SideOnly\s*\(\s*Side\.SERVER\s*\)', '@OnlyIn(Dist.DEDICATED_SERVER)'
        $t = $t -replace '@OnlyIn\s*\(\s*Side\.CLIENT\s*\)', '@OnlyIn(Dist.CLIENT)'
        $t = $t -replace '@OnlyIn\s*\(\s*Side\.SERVER\s*\)', '@OnlyIn(Dist.DEDICATED_SERVER)'
        $t = $t -replace '\bSide\.CLIENT\b', 'Dist.CLIENT'
        $t = $t -replace '\bSide\.SERVER\b', 'Dist.DEDICATED_SERVER'
        # Method params: Side side -> Dist side (best-effort)
        $t = $t -replace '\bSide\.\.\.\s*sides\b', 'Dist... sides'
        $t = $t -replace '\(([^)]*)\bSide\b(\s+\w+)', '($1Dist$2'
        $t = $t -replace 'for\s*\(\s*Side\s+', 'for (Dist '

        # Forge -> NeoForge packages
        $t = $t -replace 'net\.minecraftforge\.fml\.common\.Mod\b', 'net.neoforged.fml.common.Mod'
        $t = $t -replace 'net\.minecraftforge\.fml\.relauncher\.', 'net.neoforged.api.distmarker.'
        $t = $t -replace 'net\.minecraftforge\.common\.MinecraftForge\b', 'net.neoforged.neoforge.common.NeoForge'
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.common\.MinecraftForge\s*;', 'import net.neoforged.neoforge.common.NeoForge;'
        $t = $t -replace '\bMinecraftForge\.EVENT_BUS\b', 'NeoForge.EVENT_BUS'
        $t = $t -replace 'net\.minecraftforge\.common\.', 'net.neoforged.neoforge.common.'
        $t = $t -replace 'net\.minecraftforge\.client\.', 'net.neoforged.neoforge.client.'
        $t = $t -replace 'net\.minecraftforge\.event\.', 'net.neoforged.neoforge.event.'
        $t = $t -replace 'net\.minecraftforge\.registries\.', 'net.neoforged.neoforge.registries.'
        $t = $t -replace 'net\.minecraftforge\.items\.', 'net.neoforged.neoforge.items.'

        # Map removed 1.12 FML / registry / network / client types -> stub112
        $stubMap = [ordered]@{
            'net.minecraftforge.fml.common.event.FMLPreInitializationEvent'   = 'rb.converter.stub112.FMLPreInitializationEvent'
            'net.minecraftforge.fml.common.event.FMLInitializationEvent'      = 'rb.converter.stub112.FMLInitializationEvent'
            'net.minecraftforge.fml.common.event.FMLPostInitializationEvent'  = 'rb.converter.stub112.FMLPostInitializationEvent'
            'net.minecraftforge.fml.common.event.FMLServerStartingEvent'      = 'rb.converter.stub112.FMLServerStartingEvent'
            'net.minecraftforge.fml.common.discovery.ASMDataTable.ASMData'    = 'rb.converter.stub112.ASMDataTable.ASMData'
            'net.minecraftforge.fml.common.discovery.ASMDataTable'            = 'rb.converter.stub112.ASMDataTable'
            'net.minecraftforge.fml.common.network.simpleimpl.IMessageHandler' = 'rb.converter.stub112.IMessageHandler'
            'net.minecraftforge.fml.common.network.simpleimpl.MessageContext'  = 'rb.converter.stub112.MessageContext'
            'net.minecraftforge.fml.common.network.simpleimpl.IMessage'       = 'rb.converter.stub112.IMessage'
            'net.minecraftforge.fml.common.network.simpleimpl.SimpleNetworkWrapper' = 'rb.converter.stub112.SimpleNetworkWrapper'
            'net.minecraftforge.fml.common.network.ByteBufUtils'              = 'rb.converter.stub112.ByteBufUtils'
            'net.minecraftforge.fml.common.network.NetworkRegistry'           = 'rb.converter.stub112.NetworkRegistry'
            'net.minecraftforge.fml.common.network.IGuiHandler'               = 'rb.converter.stub112.IGuiHandler'
            'net.minecraftforge.fml.common.registry.GameRegistry.ObjectHolder' = 'rb.converter.stub112.GameRegistry.ObjectHolder'
            'net.minecraftforge.fml.common.registry.GameRegistry'             = 'rb.converter.stub112.GameRegistry'
            'net.minecraftforge.fml.common.registry.EntityEntry'              = 'rb.converter.stub112.EntityEntry'
            'net.minecraftforge.fml.common.eventhandler.SubscribeEvent'       = 'rb.converter.stub112.SubscribeEvent'
            'net.minecraftforge.fml.common.gameevent.PlayerEvent.PlayerLoggedInEvent' = 'rb.converter.stub112.PlayerLoggedInEvent'
            'net.minecraftforge.fml.common.gameevent.PlayerEvent.PlayerChangedDimensionEvent' = 'rb.converter.stub112.PlayerChangedDimensionEvent'
            'net.minecraftforge.fml.common.SidedProxy'                        = 'rb.converter.stub112.SidedProxy'
            'net.minecraftforge.fluids.FluidRegistry'                         = 'rb.converter.stub112.FluidRegistry'
            'net.minecraftforge.registries.IForgeRegistryEntry'               = 'rb.converter.stub112.IForgeRegistryEntry'
            'net.minecraftforge.event.RegistryEvent.Register'                 = 'rb.converter.stub112.RegistryEvent.Register'
            'net.minecraftforge.event.RegistryEvent'                          = 'rb.converter.stub112.RegistryEvent'
            'net.minecraftforge.client.event.ModelRegistryEvent'              = 'rb.converter.stub112.ModelRegistryEvent'
            'net.minecraftforge.client.model.ModelLoader'                     = 'rb.converter.stub112.ModelLoader'
            'net.minecraft.client.renderer.block.model.ModelResourceLocation' = 'rb.converter.stub112.ModelResourceLocation'
            'net.minecraft.world.chunk.IChunkProvider'                        = 'rb.converter.stub112.IChunkProvider'
            'net.minecraft.world.gen.IChunkGenerator'                         = 'rb.converter.stub112.IChunkGenerator'
            'net.minecraft.world.storage.WorldSavedData'                      = 'rb.converter.stub112.WorldSavedData'
        }
        # Also map if already half-rewritten to neoforge packages that still don't exist
        $neoDead = [ordered]@{
            'net.neoforged.neoforge.client.event.ModelRegistryEvent' = 'rb.converter.stub112.ModelRegistryEvent'
            'net.neoforged.neoforge.client.model.ModelLoader'        = 'rb.converter.stub112.ModelLoader'
            'net.neoforged.neoforge.client.model.obj.OBJLoader'      = 'rb.converter.stub112.ModelLoader'
            'net.neoforged.neoforge.event.RegistryEvent.Register'    = 'rb.converter.stub112.RegistryEvent.Register'
            'net.neoforged.neoforge.event.RegistryEvent'             = 'rb.converter.stub112.RegistryEvent'
            'net.neoforged.neoforge.registries.IForgeRegistryEntry'  = 'rb.converter.stub112.IForgeRegistryEntry'
            'net.neoforged.neoforge.network.simpleimpl.IMessageHandler' = 'rb.converter.stub112.IMessageHandler'
            'net.neoforged.neoforge.network.simpleimpl.IMessage'     = 'rb.converter.stub112.IMessage'
            'net.neoforged.neoforge.network.simpleimpl.SimpleNetworkWrapper' = 'rb.converter.stub112.SimpleNetworkWrapper'
            'net.neoforged.neoforge.network.NetworkRegistry'         = 'rb.converter.stub112.NetworkRegistry'
            'net.neoforged.neoforge.network.IGuiHandler'             = 'rb.converter.stub112.IGuiHandler'
            'net.neoforged.fml.common.event.FMLPreInitializationEvent'  = 'rb.converter.stub112.FMLPreInitializationEvent'
            'net.neoforged.fml.common.event.FMLInitializationEvent'     = 'rb.converter.stub112.FMLInitializationEvent'
            'net.neoforged.fml.common.event.FMLPostInitializationEvent' = 'rb.converter.stub112.FMLPostInitializationEvent'
            'net.neoforged.fml.common.event.FMLServerStartingEvent'     = 'rb.converter.stub112.FMLServerStartingEvent'
        }
        foreach ($pair in @($stubMap.GetEnumerator() + $neoDead.GetEnumerator())) {
            $from = [regex]::Escape($pair.Key)
            $to = $pair.Value
            $t = $t -replace $from, $to
        }

        # Network package was bulk-rewritten earlier — ensure simpleimpl / IGuiHandler land on stubs
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.network\.simpleimpl\.', 'import rb.converter.stub112.'
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.network\.NetworkRegistry\s*;', 'import rb.converter.stub112.NetworkRegistry;'
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.network\.IGuiHandler\s*;', 'import rb.converter.stub112.IGuiHandler;'

        # Remove broken "implements Object, Object" from prior IFuelHandler/IWorldGenerator rewrites
        $t = $t -replace '\s*implements\s+/\*\s*TODO_112_REMOVED IFuelHandler\s*\*/\s*Object\s*,\s*/\*\s*TODO_112_REMOVED IWorldGenerator\s*\*/\s*Object', ''
        $t = $t -replace '\s*implements\s+/\*\s*TODO_112_REMOVED IWorldGenerator\s*\*/\s*Object\s*,\s*/\*\s*TODO_112_REMOVED IFuelHandler\s*\*/\s*Object', ''
        $t = $t -replace '\s*implements\s+/\*\s*TODO_112_REMOVED IFuelHandler\s*\*/\s*Object', ''
        $t = $t -replace '\s*implements\s+/\*\s*TODO_112_REMOVED IWorldGenerator\s*\*/\s*Object', ''
        $t = $t -replace '(?m)^import\s+net\.minecraftforge\.fml\.common\./\*\s*TODO_112_REMOVED[^*]*\*/\s*Object;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+net\.minecraftforge\.fml\.common\.IFuelHandler\s*;\s*\r?\n', ''
        $t = $t -replace '(?m)^import\s+net\.minecraftforge\.fml\.common\.IWorldGenerator\s*;\s*\r?\n', ''
        $t = $t -replace '\s*implements\s+IFuelHandler\s*,\s*IWorldGenerator', ''
        $t = $t -replace '\s*,\s*IFuelHandler\b', ''
        $t = $t -replace '\s*implements\s+IFuelHandler\b', ''
        $t = $t -replace '\s*,\s*IWorldGenerator\b', ''
        $t = $t -replace '\s*implements\s+IWorldGenerator\b', ''
        $t = $t -replace '/\*\s*TODO_112_REMOVED IFuelHandler\s*\*/\s*Object', 'Object'
        $t = $t -replace '/\*\s*TODO_112_REMOVED IWorldGenerator\s*\*/\s*Object', 'Object'

        # Undo broken GameRegistry comment rewrites; point at stubs
        $t = $t -replace '/\*\s*TODO_112_GameRegistry\s*\*/\s*', ''
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.common\.registry\./\*\s*TODO_112_GameRegistry\s*\*/\s*GameRegistry\.ObjectHolder\s*;',
            'import rb.converter.stub112.GameRegistry.ObjectHolder;'
        $t = $t -replace '(?m)^// TODO_112: GameRegistry removed - use DeferredRegister\s*\r?\n// import GameRegistry;\s*\r?\n',
            "import rb.converter.stub112.GameRegistry;$nl"
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.common\.registry\.GameRegistry\s*;',
            'import rb.converter.stub112.GameRegistry;'
        $t = $t -replace 'import\s+net\.minecraftforge\.fml\.common\.registry\.GameRegistry\.ObjectHolder\s*;',
            'import rb.converter.stub112.GameRegistry.ObjectHolder;'

        # OBJLoader
        $t = $t -replace 'import\s+net\.minecraftforge\.client\.model\.obj\.OBJLoader\s*;',
            "import rb.converter.stub112.ModelLoader; // was OBJLoader$nl"
        $t = $t -replace 'import\s+net\.neoforged\.neoforge\.client\.model\.obj\.OBJLoader\s*;',
            "import rb.converter.stub112.ModelLoader; // was OBJLoader$nl"
        $t = $t -replace 'OBJLoader\.INSTANCE', '/* TODO_112_CLIENT OBJLoader */ null'
        $t = $t -replace '(?m)^// TODO_112_CLIENT: OBJLoader API changed - port models manually\s*\r?\n// import OBJLoader;\s*\r?\n', ''

        # Elements-style lifecycle: prefer no-arg preInit/init/serverLoad when only FML stub event was used
        $t = $t -replace 'void\s+preInit\s*\(\s*(?:rb\.converter\.stub112\.)?FMLPreInitializationEvent\s+\w+\s*\)', 'void preInit()'
        $t = $t -replace 'void\s+init\s*\(\s*(?:rb\.converter\.stub112\.)?FMLInitializationEvent\s+\w+\s*\)', 'void init()'
        $t = $t -replace 'void\s+postInit\s*\(\s*(?:rb\.converter\.stub112\.)?FMLPostInitializationEvent\s+\w+\s*\)', 'void postInit()'
        $t = $t -replace 'void\s+serverLoad\s*\(\s*(?:rb\.converter\.stub112\.)?FMLServerStartingEvent\s+\w+\s*\)', 'void serverLoad()'

        # After stripping FML event params, rewrite leftover `event.*` from former preInit bodies
        $t = $t -replace 'event\.getAsmData\(\)', '(new rb.converter.stub112.ASMDataTable())'
        $t = $t -replace 'event\.getModConfigurationDirectory\(\)', 'new java.io.File(".")'
        $t = $t -replace 'event\.getSuggestedConfigurationFile\(\)', 'new java.io.File("stub.cfg")'
        $t = $t -replace 'event\.getModLog\(\)', 'org.apache.logging.log4j.LogManager.getLogger("stub112")'

        # Legacy registry casts
        $t = $t -replace '\(IForgeRegistryEntry\[\]\)', '(Object[])'
        $t = $t -replace '\(rb\.converter\.stub112\.IForgeRegistryEntry\[\]\)', '(Object[])'

        # World param renamed to Level; leftover `world.` SRG refs from generate() bodies
        $t = $t -replace '\bworld\.field_73011_w\.getDimension\(\)', '0 /* TODO_112 dim */'
        $t = $t -replace '\bworld\.provider\.getDimension\(\)', '0 /* TODO_112 dim */'
        # 1.12 Entity.world SRG field on Player (not present on modern Player)
        $t = $t -replace '!event\.player\.field_70170_p\.field_72995_K', 'true /* TODO_112 isRemote */'
        $t = $t -replace 'event\.player\.field_70170_p\.field_72995_K', 'false /* TODO_112 isRemote */'
        $t = $t -replace 'event\.player\.field_70170_p', 'null /* TODO_112 player.level */'

        if ($t -match 'rb\.converter\.stub112\.FML|TODO_112_STAGE_A|IProxy|ClientProxy|ServerProxy') {
            if ($t -notmatch 'TODO_112_STAGE_A') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_STAGE_A: proxies/FML lifecycle stubbed; finish DeferredRegister + real setup.' + $nl)
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

Write-Step 'Stage A: inject rb.converter.stub112 compile stubs'
$stubCount = Write-Stub112Sources -Root $OutputPath
Write-Ok "Wrote $stubCount stub source file(s)"

Write-Step '1.12 mechanical rewrites (packages, Identifier, stub maps, Potion/ServerPlayer fixes)'
$j = Invoke-112MechanicalRewrites -Root $OutputPath
Write-Ok "Touched $j Java file(s)"

Write-Step 'Stage A: stub IProxy / ClientProxy / ServerProxy / CommonProxy'
$p = Invoke-112ProxyStubPass -Root $OutputPath
Write-Ok "Stubbed $p proxy file(s)"

Write-Step 'Stage A: inject modern @Mod constructor + IEventBus hooks'
$m = Invoke-112ModConstructorPass -Root $OutputPath
Write-Ok "Updated $m @Mod class(es)"

# Second mechanical pass: pick up any leftover after structural edits
$j2 = Invoke-112MechanicalRewrites -Root $OutputPath
if ($j2 -gt 0) { Write-Ok "Second rewrite pass touched $j2 file(s)" }

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
- Converter stage: **A (v0.2)** — proxies/FML lifecycle stubs + modern @Mod ctor
- Generated: $gen

## Automated (Stage A)

1. Project copy (original unchanged)
2. ModDevGradle 26.2 scaffold (Java 25)
3. Metadata from mcmod.info / assets when available
4. Mechanical package renames (1.12 to modern world/core packages)
5. ResourceLocation to Identifier; World/EntityPlayer renames
6. **ServerPlayer** import fix (`server.level`); **Potion** → **MobEffect**
7. SideOnly → OnlyIn(Dist); MinecraftForge.EVENT_BUS → NeoForge.EVENT_BUS
8. **stub112** package for FML*Event, GameRegistry, IGuiHandler, ModelRegistryEvent, network simpleimpl, etc.
9. **IProxy / ClientProxy / ServerProxy** rewritten to empty no-arg stubs
10. **@Mod** rewritten to modern value form + **IEventBus** constructor + FMLCommonSetupEvent listener
11. FML @EventHandler pre/init/post/serverLoad removed from mod entry
12. Legacy mcmod.info → mcmod.info.112-reference; templates for NeoForge mods.toml

## You must still fix manually (post Stage A)

- All registrations (blocks/items/entities) to DeferredRegister (stubs are no-ops)
- MCreator block APIs (Material, properties, func_* SRG names, creative tabs)
- World gen, fuels, recipes
- Client models (JSON blockstates / items; OBJ pipeline)
- Tile entities / GUIs / packets (real networking)
- Remaining compile errors after gradlew compileJava
- Runtime testing on NeoForge 26.2

## Next

cd "$OutputPath"
.\gradlew.bat compileJava --stacktrace

Scaffold + Stage A success is not full compile success. 1.12 to 26.2 is a multi-year API gap.
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
