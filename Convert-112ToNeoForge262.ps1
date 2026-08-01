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
    public void sendToDimension(IMessage message, int dimension) { /* no-op */ }
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
    REPLY onMessage(REQ message, MessageContext ctx);
}
'@
        'MessageContext.java' = @'
package rb.converter.stub112;

import net.minecraft.world.level.Level;

/** Stage A/B stub for 1.12 simpleimpl.MessageContext. */
public final class MessageContext {
    public Object side;
    public final ServerHandler serverHandler = new ServerHandler();
    public ServerHandler getServerHandler() { return serverHandler; }

    public static final class ServerHandler {
        /** player entity SRG field on NetHandlerPlayServer */
        public final DummyPlayer field_147369_b = new DummyPlayer();
        public ServerHandler func_71121_q() { return this; }
        public void func_152344_a(Runnable task) { if (task != null) task.run(); }
    }

    public static final class DummyPlayer {
        public final Level field_70170_p = null;
        public DummyPlayer func_71121_q() { return this; }
        public void func_152344_a(Runnable task) { if (task != null) task.run(); }
    }
}
'@
        'LegacyClient.java' = @'
package rb.converter.stub112;

/** Stage B helpers for 1.12 client Minecraft statics / scheduled tasks. */
public final class LegacyClient {
    private LegacyClient() {}
    public static void addScheduledTask(Runnable task) {
        if (task != null) task.run();
    }
    public static final Object field_71439_g = null;
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

/** Stage A/B stub: 1.12 WorldSavedData (modern: SavedData). */
public class WorldSavedData {
    public WorldSavedData(String name) {}
    public void markDirty() {}
    /** markDirty SRG */
    public void func_76185_a() { markDirty(); }
    /** readFromNBT */
    public void func_76184_a(Object nbt) {}
    /** writeToNBT */
    public NBTTagCompound func_189551_b(NBTTagCompound nbt) { return nbt == null ? new NBTTagCompound() : nbt; }
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
        # ---------- Stage B: 1.12 block / item API surface ----------
        'Material.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 Material (removed; use BlockBehaviour.Properties on 26.2). */
public final class Material {
    public static final Material field_151573_f = new Material(); // IRON
    public static final Material field_151576_e = new Material(); // ROCK
    public static final Material field_151575_d = new Material(); // WOOD
    public static final Material field_151578_c = new Material(); // GROUND
    public static final Material field_151579_a = new Material(); // AIR
    public static final Material field_151577_b = new Material(); // GRASS
    public static final Material field_151583_m = new Material(); // CLOTH
    public static final Material field_151584_j = new Material(); // SAND
    public static final Material field_151592_s = new Material(); // GLASS-ish
    public static final Material field_151594_q = new Material(); // CIRCUITS
    public static final Material ROCK = field_151576_e;
    public static final Material IRON = field_151573_f;
    public static final Material WOOD = field_151575_d;
    private Material() {}
}
'@
        'IProperty.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 IProperty. */
public interface IProperty<T extends Comparable<T>> {
    String getName();
    java.util.Collection<T> getAllowedValues();
}
'@
        'PropertyDirection.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 PropertyDirection (modern: DirectionProperty). */
public final class PropertyDirection implements IProperty<EnumFacing> {
    private final String name;
    private PropertyDirection(String name) { this.name = name; }
    public static PropertyDirection create(String name) { return new PropertyDirection(name); }
    @Override public String getName() { return name; }
    @Override public java.util.Collection<EnumFacing> getAllowedValues() {
        return java.util.Arrays.asList(EnumFacing.values());
    }
}
'@
        'BlockHorizontal.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 BlockHorizontal. */
public final class BlockHorizontal {
    public static final PropertyDirection field_185512_D = PropertyDirection.create("facing");
    public static final PropertyDirection FACING = field_185512_D;
    private BlockHorizontal() {}
}
'@
        'BlockStateContainer.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 BlockStateContainer (modern: StateDefinition). */
public final class BlockStateContainer {
    public BlockStateContainer(Object block, IProperty<?>... properties) {}
    public LegacyBlockState getBaseState() { return new LegacyBlockState(); }
}
'@
        'LegacyBlockState.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12-style blockstate fluent API (not real BlockState). */
public final class LegacyBlockState {
    /** getBaseState / container base */
    public LegacyBlockState func_177621_b() { return this; }
    public LegacyBlockState func_177226_a(Object property, Object value) { return this; }
    public Object func_177229_b(Object property) { return EnumFacing.NORTH; }
    public LegacyBlockState func_185907_a(Object mirror) { return this; }
    public LegacyBlockState withProperty(Object property, Object value) { return func_177226_a(property, value); }
    public Object getValue(Object property) { return func_177229_b(property); }
}
'@
        'BlockRenderLayer.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 BlockRenderLayer (modern client: RenderType). */
public enum BlockRenderLayer {
    SOLID,
    CUTOUT,
    CUTOUT_MIPPED,
    TRANSLUCENT
}
'@
        'EnumFacing.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 EnumFacing (modern: Direction). */
public enum EnumFacing {
    DOWN, UP, NORTH, SOUTH, WEST, EAST;

    public static EnumFacing func_82600_a(int index) {
        EnumFacing[] v = values();
        if (index < 0 || index >= v.length) return NORTH;
        return v[index];
    }
    public int func_176745_a() { return ordinal(); }
    public EnumFacing func_176734_d() {
        return switch (this) {
            case NORTH -> SOUTH;
            case SOUTH -> NORTH;
            case WEST -> EAST;
            case EAST -> WEST;
            default -> this;
        };
    }
    public EnumFacing getOpposite() { return func_176734_d(); }
}
'@
        'AxisAlignedBB.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 AxisAlignedBB (modern: AABB). */
public final class AxisAlignedBB {
    public final double minX, minY, minZ, maxX, maxY, maxZ;
    public AxisAlignedBB(double x1, double y1, double z1, double x2, double y2, double z2) {
        minX = x1; minY = y1; minZ = z1; maxX = x2; maxY = y2; maxZ = z2;
    }
    public AxisAlignedBB(Object pos1, Object pos2) {
        this(0, 0, 0, 1, 1, 1);
    }
}
'@
        'IBlockAccess.java' = @'
package rb.converter.stub112;

import net.minecraft.core.BlockPos;

/** Stage B stub: 1.12 IBlockAccess (modern: BlockGetter / LevelReader). */
public interface IBlockAccess {
    default Object getTileEntity(BlockPos pos) { return null; }
    default int getCombinedLight(BlockPos pos, int lightValue) { return 0; }
}
'@
        'Mirror.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 Mirror helpers. */
public enum Mirror {
    NONE, LEFT_RIGHT, FRONT_BACK;
    public EnumFacing func_185800_a(EnumFacing facing) { return facing; }
}
'@
        'Rotation.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 Rotation helpers. */
public enum Rotation {
    NONE, CLOCKWISE_90, CLOCKWISE_180, COUNTERCLOCKWISE_90;
    public EnumFacing func_185831_a(EnumFacing facing) { return facing; }
}
'@
        'EntityLivingBase.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 EntityLivingBase (modern: LivingEntity). */
public class EntityLivingBase {
    public EnumFacing func_174811_aO() { return EnumFacing.NORTH; }
    public EnumFacing getHorizontalFacing() { return func_174811_aO(); }
}
'@
        'ItemBlock.java' = @'
package rb.converter.stub112;

import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;

/** Stage B stub: 1.12 ItemBlock (modern: BlockItem) with registry-name chaining. */
public class ItemBlock extends Item {
    private final Block block;
    public ItemBlock(Block block) {
        super(new Item.Properties());
        this.block = block;
    }
    public Block getBlock() { return block; }
    public ItemBlock setRegistryName(String name) { return this; }
    public ItemBlock setRegistryName(String modId, String name) { return this; }
    public ItemBlock setRegistryName(Object name) { return this; }
    public Object getRegistryName() { return null; }
}
'@
        'CreativeTabs.java' = @'
package rb.converter.stub112;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.function.Supplier;
import net.minecraft.world.item.Item;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.block.Block;

/** Stage B/D/F: 1.12 CreativeTabs bridge toward CreativeModeTab. */
public class CreativeTabs {
    private static final List<CreativeTabs> ALL = new ArrayList<>();
    public final String tabLabel;
    private final Set<Block> blocks = new LinkedHashSet<>();
    private final Set<Item> items = new LinkedHashSet<>();
    private Supplier<ItemStack> iconOverride;

    public CreativeTabs(String label) {
        this.tabLabel = label == null ? "tab" : label;
        ALL.add(this);
    }

    public static List<CreativeTabs> allTabs() {
        return Collections.unmodifiableList(ALL);
    }

    public ItemStack func_78016_d() {
        if (iconOverride != null) {
            ItemStack s = iconOverride.get();
            if (s != null && !s.isEmpty()) return s;
        }
        for (Item it : items) {
            if (it != null && it != net.minecraft.world.item.Items.AIR) {
                return new ItemStack(it);
            }
        }
        for (Block b : blocks) {
            Item i = b.asItem();
            if (i != null && i != net.minecraft.world.item.Items.AIR) {
                return new ItemStack(i);
            }
        }
        return ItemStack.EMPTY;
    }

    public ItemStack createIcon() { return func_78016_d(); }
    public boolean hasSearchBar() { return false; }
    public CreativeTabs func_78025_a(String texture) { return this; }
    public String getTabLabel() { return tabLabel; }

    public String registryPath() {
        String p = tabLabel.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9_]", "_");
        if (p.startsWith("tab")) p = p.substring(3);
        if (p.isEmpty()) p = "misc";
        if (p.isEmpty()) p = "misc";
        // avoid empty / illegal paths
        while (p.startsWith("_")) p = p.substring(1);
        if (p.isEmpty()) p = "misc";
        return p;
    }

    public void addBlock(Block block) {
        if (block != null) blocks.add(block);
    }

    public void addItem(Item item) {
        if (item != null) items.add(item);
    }

    public Set<Block> getBlocks() { return Collections.unmodifiableSet(blocks); }
    public Set<Item> getItems() { return Collections.unmodifiableSet(items); }

    public void setIconSupplier(Supplier<ItemStack> icon) { this.iconOverride = icon; }
}
'@
        'LegacyItems.java' = @'
package rb.converter.stub112;

import net.minecraft.world.item.Item;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.block.Block;

/** Stage B helpers for 1.12 Item statics. */
public final class LegacyItems {
    private LegacyItems() {}
    /** 1.12 Item.getItemFromBlock - stub returns AIR until real BlockItem registration exists. */
    public static Item func_150898_a(Block block) {
        return Items.AIR;
    }
}
'@
        'LegacyLevel.java' = @'
package rb.converter.stub112;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.Level;

/** Stage B no-op helpers for 1.12 World/Level SRG calls. */
public final class LegacyLevel {
    private LegacyLevel() {}
    public static void destroyBlock(Level level, BlockPos pos) { /* no-op */ }
    public static void setBlockState(Level level, BlockPos pos, Object state, int flags) { /* no-op */ }
    public static int getRedstonePower(Level level, BlockPos pos) { return 0; }
    public static MapStorage getMapStorage(Level level) { return new MapStorage(); }
    public static MapStorage getPerWorldStorage(Level level) { return new MapStorage(); }

    public static final class MapStorage {
        public Object func_75742_a(Class<?> clazz, String id) { return null; }
        public void func_75745_a(String id, Object data) { /* no-op */ }
    }
}
'@
        'ElementDiscovery.java' = @'
package rb.converter.stub112;

import java.io.File;
import java.lang.annotation.Annotation;
import java.net.URL;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

/**
 * Stage C: find classes bearing a runtime annotation under a package
 * (replaces empty FML ASMDataTable scanning).
 */
public final class ElementDiscovery {
    private ElementDiscovery() {}

    public static List<Class<?>> findAnnotated(Class<? extends Annotation> annotation, String packageName) {
        List<Class<?>> found = new ArrayList<>();
        if (annotation == null || packageName == null || packageName.isEmpty()) return found;
        String path = packageName.replace('.', '/');
        ClassLoader cl = Thread.currentThread().getContextClassLoader();
        if (cl == null) cl = ElementDiscovery.class.getClassLoader();
        try {
            Enumeration<URL> roots = cl.getResources(path);
            while (roots.hasMoreElements()) {
                URL url = roots.nextElement();
                String protocol = url.getProtocol();
                if ("file".equals(protocol)) {
                    scanDirectory(new File(url.toURI()), packageName, annotation, found, cl);
                } else if ("jar".equals(protocol)) {
                    scanJarUrl(url, path, packageName, annotation, found, cl);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return found;
    }

    private static void scanDirectory(File dir, String packageName, Class<? extends Annotation> annotation,
                                      List<Class<?>> found, ClassLoader cl) {
        if (dir == null || !dir.isDirectory()) return;
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                scanDirectory(f, packageName + "." + f.getName(), annotation, found, cl);
            } else if (f.getName().endsWith(".class") && !f.getName().contains("$")) {
                String simple = f.getName().substring(0, f.getName().length() - 6);
                loadIfAnnotated(packageName + "." + simple, annotation, found, cl);
            }
        }
    }

    private static void scanJarUrl(URL url, String pathPrefix, String packageName,
                                   Class<? extends Annotation> annotation, List<Class<?>> found, ClassLoader cl) {
        try {
            String s = url.getPath();
            // jar:file:/.../mod.jar!/net/mcreator/foo
            int bang = s.indexOf('!');
            String jarPath = s;
            if (s.startsWith("file:")) jarPath = s.substring(5);
            if (bang >= 0) jarPath = s.substring(s.startsWith("file:") ? 5 : 0, bang);
            if (jarPath.contains("%20")) jarPath = java.net.URLDecoder.decode(jarPath, java.nio.charset.StandardCharsets.UTF_8);
            // Windows leading slash: /F:/...
            if (jarPath.length() > 2 && jarPath.charAt(0) == '/' && jarPath.charAt(2) == ':') {
                jarPath = jarPath.substring(1);
            }
            try (JarFile jar = new JarFile(jarPath)) {
                Enumeration<JarEntry> en = jar.entries();
                String prefix = pathPrefix.endsWith("/") ? pathPrefix : pathPrefix + "/";
                while (en.hasMoreElements()) {
                    JarEntry e = en.nextElement();
                    String name = e.getName();
                    if (!name.startsWith(prefix) || !name.endsWith(".class") || name.contains("$")) continue;
                    String className = name.substring(0, name.length() - 6).replace('/', '.');
                    loadIfAnnotated(className, annotation, found, cl);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static void loadIfAnnotated(String className, Class<? extends Annotation> annotation,
                                        List<Class<?>> found, ClassLoader cl) {
        try {
            Class<?> c = Class.forName(className, false, cl);
            if (c.getAnnotation(annotation) != null) {
                found.add(c);
            }
        } catch (Throwable ignored) {
            /* skip unloadable / client-only */
        }
    }
}
'@
        'LegacyBlocks.java' = @'
package rb.converter.stub112;

import java.util.IdentityHashMap;
import java.util.Locale;
import java.util.Map;
import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;

/** Stage C/D helpers: registry paths + creative tab assignment. */
public final class LegacyBlocks {
    private static final Map<Object, String> ITEM_IDS = new IdentityHashMap<>();
    private static final Map<Block, CreativeTabs> BLOCK_TABS = new IdentityHashMap<>();
    private LegacyBlocks() {}

    public static void rememberItem(Item item, Block block) {
        if (item == null) return;
        ITEM_IDS.put(item, resolveBlockPath(block));
        // Stage F: attach item to the block's creative tab (asItem() is unreliable pre-link)
        CreativeTabs tab = BLOCK_TABS.get(block);
        if (tab != null) {
            tab.addItem(item);
        }
    }

    public static void assignTab(Block block, Object tab) {
        if (block == null) return;
        if (tab instanceof CreativeTabs ct) {
            BLOCK_TABS.put(block, ct);
            ct.addBlock(block);
        }
    }

    public static CreativeTabs tabOf(Block block) {
        return BLOCK_TABS.get(block);
    }

    public static String resolveBlockPath(Block block) {
        if (block instanceof LegacyBlock112 legacy) {
            String n = legacy.getLegacyRegistryName();
            if (n != null && !n.isEmpty()) return stripPath(n);
        }
        String simple = block == null ? "unknown" : block.getClass().getSimpleName().toLowerCase(Locale.ROOT);
        return simple.replaceAll("[^a-z0-9_]", "");
    }

    public static String resolveItemPath(Item item) {
        if (item == null) return "unknown_item";
        String remembered = ITEM_IDS.get(item);
        if (remembered != null) return remembered;
        if (item instanceof BlockItem bi) return resolveBlockPath(bi.getBlock());
        return item.getClass().getSimpleName().toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9_]", "");
    }

    private static String stripPath(String name) {
        int i = name.indexOf(':');
        String path = i >= 0 ? name.substring(i + 1) : name;
        return path.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9_/.-]", "");
    }
}
'@
        'LegacyProps.java' = @'
package rb.converter.stub112;

import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.material.MapColor;

/** Stage D: fold 1.12 Material + hardness/light/sound into BlockBehaviour.Properties. */
public final class LegacyProps {
    private LegacyProps() {}

    public static BlockBehaviour.Properties of(Material material, SoundType sound,
                                               float hardness, float resistance,
                                               float light01, int lightOpacity) {
        SoundType s = sound != null ? sound : SoundType.STONE;
        BlockBehaviour.Properties p = BlockBehaviour.Properties.of()
                .mapColor(mapColor(material))
                .sound(s)
                .strength(Math.max(0f, hardness), Math.max(0f, resistance));
        if (light01 > 0f) {
            int lvl = Math.max(0, Math.min(15, Math.round(light01 * 15f)));
            p = p.lightLevel(state -> lvl);
        }
        if (lightOpacity <= 0) {
            p = p.noOcclusion();
        }
        return p;
    }

    public static BlockBehaviour.Properties fromMaterial(Material material) {
        return of(material, SoundType.STONE, 1.0f, 1.0f, 0f, 255);
    }

    private static MapColor mapColor(Material material) {
        if (material == null) return MapColor.STONE;
        // Common 1.12 Material SRG statics used by MCreator
        if (material == Material.field_151573_f || material == Material.IRON) return MapColor.METAL;
        if (material == Material.field_151575_d || material == Material.WOOD) return MapColor.WOOD;
        if (material == Material.field_151576_e || material == Material.ROCK) return MapColor.STONE;
        if (material == Material.field_151578_c) return MapColor.DIRT;
        if (material == Material.field_151583_m) return MapColor.WOOL;
        if (material == Material.field_151584_j) return MapColor.SAND;
        if (material == Material.field_151592_s) return MapColor.NONE;
        return MapColor.STONE;
    }
}
'@
        'LegacyHorizontalBlock112.java' = @'
package rb.converter.stub112;

import net.minecraft.core.Direction;
import net.minecraft.world.item.context.BlockPlaceContext;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.Mirror;
import net.minecraft.world.level.block.Rotation;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.StateDefinition;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.block.state.properties.EnumProperty;

/** Stage D: real horizontal FACING state for MCreator BlockHorizontal-style blocks. */
public class LegacyHorizontalBlock112 extends LegacyBlock112 {
    public static final EnumProperty<Direction> FACING = BlockStateProperties.HORIZONTAL_FACING;

    public LegacyHorizontalBlock112(Material material) {
        super(LegacyProps.fromMaterial(material));
        finishFacingDefault();
    }

    public LegacyHorizontalBlock112(BlockBehaviour.Properties properties) {
        super(properties);
        finishFacingDefault();
    }

    private void finishFacingDefault() {
        this.registerDefaultState(this.stateDefinition.any().setValue(FACING, Direction.NORTH));
    }

    @Override
    protected void createBlockStateDefinition(StateDefinition.Builder<Block, BlockState> builder) {
        builder.add(FACING);
    }

    @Override
    public BlockState getStateForPlacement(BlockPlaceContext context) {
        return this.defaultBlockState().setValue(FACING, context.getHorizontalDirection().getOpposite());
    }

    @Override
    protected BlockState rotate(BlockState state, Rotation rotation) {
        return state.setValue(FACING, rotation.rotate(state.getValue(FACING)));
    }

    @Override
    protected BlockState mirror(BlockState state, Mirror mirror) {
        return state.rotate(mirror.getRotation(state.getValue(FACING)));
    }
}
'@
        'LegacyBlock112.java' = @'
package rb.converter.stub112;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.shapes.CollisionContext;
import net.minecraft.world.phys.shapes.Shapes;
import net.minecraft.world.phys.shapes.VoxelShape;

/**
 * Stage B/D: 1.12-shaped Block base.
 * Stage D applies light/occlusion/collision/tab side-effects for remaining setter calls.
 */
public class LegacyBlock112 extends Block {
    /** 1.12 NULL_AABB */
    public static final AxisAlignedBB field_185506_k = new AxisAlignedBB(0, 0, 0, 0, 0, 0);
    public static final AxisAlignedBB FULL_BLOCK_AABB = new AxisAlignedBB(0, 0, 0, 1, 1, 1);

    protected final LegacyBlockState field_176227_L = new LegacyBlockState();
    private String legacyRegistryName;
    private boolean legacyNoCollision;
    private boolean legacyCutout;
    private int legacyLight = 0;
    private VoxelShape legacyShape = null;

    public LegacyBlock112(Material material) {
        super(LegacyProps.fromMaterial(material));
    }

    public LegacyBlock112(BlockBehaviour.Properties properties) {
        super(properties);
    }

    public LegacyBlock112 setRegistryName(String name) {
        this.legacyRegistryName = name;
        return this;
    }

    public LegacyBlock112 setRegistryName(String modId, String name) {
        this.legacyRegistryName = modId + ":" + name;
        return this;
    }

    public Object getRegistryName() {
        return legacyRegistryName;
    }

    /** Stage C: path (or mod:path) captured from setRegistryName. */
    public String getLegacyRegistryName() {
        return legacyRegistryName;
    }

    /** Stage D: empty collision (1.12 NULL_AABB style). */
    public void setLegacyNoCollision() {
        this.legacyNoCollision = true;
    }

    public void setLegacyCutout() {
        this.legacyCutout = true;
    }

    public boolean isLegacyCutout() {
        return legacyCutout;
    }

    /** Stage E: 1.12 AxisAlignedBB (0..1) → VoxelShape. */
    public void setLegacyShape(double x1, double y1, double z1, double x2, double y2, double z2) {
        double minX = Math.min(x1, x2), maxX = Math.max(x1, x2);
        double minY = Math.min(y1, y2), maxY = Math.max(y1, y2);
        double minZ = Math.min(z1, z2), maxZ = Math.max(z1, z2);
        minX = clamp01(minX); maxX = clamp01(maxX);
        minY = clamp01(minY); maxY = clamp01(maxY);
        minZ = clamp01(minZ); maxZ = clamp01(maxZ);
        if (maxX - minX < 1.0e-6 || maxY - minY < 1.0e-6 || maxZ - minZ < 1.0e-6) {
            this.legacyShape = Shapes.empty();
        } else {
            this.legacyShape = Shapes.box(minX, minY, minZ, maxX, maxY, maxZ);
        }
    }

    private static double clamp01(double v) {
        if (v < 0) return 0;
        if (v > 1) return 1;
        return v;
    }

    /** setUnlocalizedName */
    public void func_149663_c(String name) { /* no-op */ }
    /** setSoundType - preferred via LegacyProps; keep as soft no-op after super */
    public void func_149672_a(SoundType sound) { /* baked into Properties when using LegacyProps.of */ }
    public void func_149672_a(Object sound) { /* no-op */ }
    /** setHardness */
    public void func_149711_c(float hardness) { /* baked into Properties when using LegacyProps.of */ }
    /** setResistance */
    public void func_149752_b(float resistance) { /* baked into Properties when using LegacyProps.of */ }
    /** setLightLevel (0..1 in 1.12) */
    public void func_149715_a(float value) {
        this.legacyLight = Math.max(0, Math.min(15, Math.round(value * 15f)));
    }
    /** setLightOpacity */
    public void func_149713_g(int opacity) {
        if (opacity <= 0) {
            // noOcclusion is best applied via Properties; mark cutout-ish
            this.legacyCutout = true;
        }
    }
    /** setCreativeTab */
    public void func_149647_a(Object tab) {
        LegacyBlocks.assignTab(this, tab);
    }
    /** setDefaultState */
    public void func_180632_j(Object state) { /* horizontal default handled by LegacyHorizontalBlock112 */ }

    /** getDefaultState (legacy fluent stub) */
    public LegacyBlockState func_176223_P() { return field_176227_L; }

    public BlockRenderLayer func_180664_k() {
        return legacyCutout ? BlockRenderLayer.CUTOUT_MIPPED : BlockRenderLayer.SOLID;
    }
    public AxisAlignedBB func_180646_a(Object state, IBlockAccess world, BlockPos pos) {
        return legacyNoCollision ? field_185506_k : FULL_BLOCK_AABB;
    }
    public boolean func_176205_b(IBlockAccess world, BlockPos pos) { return legacyNoCollision || legacyCutout; }
    public boolean func_149686_d(Object state) { return !(legacyNoCollision || legacyCutout); }
    protected BlockStateContainer func_180661_e() { return new BlockStateContainer(this); }
    public Object func_185499_a(Object state, Rotation rot) { return state; }
    public Object func_185471_a(Object state, Mirror mirror) { return state; }
    public Object func_176203_a(int meta) { return func_176223_P(); }
    public int func_176201_c(Object state) { return 0; }
    public Object func_180642_a(Object world, BlockPos pos, EnumFacing facing, float hitX, float hitY, float hitZ, int meta, EntityLivingBase placer) {
        return func_176223_P();
    }
    public boolean func_149662_c(Object state) { return !(legacyNoCollision || legacyCutout); }

    public void func_189540_a(Object state, Object world, BlockPos pos, Object blockIn, BlockPos fromPos) {}
    public boolean func_180639_a(Object world, BlockPos pos, Object state, Object player, EnumHand hand, EnumFacing facing, float hitX, float hitY, float hitZ) {
        return false;
    }

    // ---- Stage D modern overrides ----
    @Override
    protected int getLightDampening(BlockState state) {
        return (legacyCutout || legacyNoCollision) ? 0 : super.getLightDampening(state);
    }

    @Override
    protected VoxelShape getCollisionShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        if (legacyNoCollision) return Shapes.empty();
        if (legacyShape != null) return legacyShape;
        return super.getCollisionShape(state, level, pos, context);
    }

    @Override
    protected VoxelShape getShape(BlockState state, BlockGetter level, BlockPos pos, CollisionContext context) {
        if (legacyShape != null) return legacyShape;
        // Keep a selectable outline even when collision is empty (signs/decor).
        return legacyNoCollision ? Shapes.block() : super.getShape(state, level, pos, context);
    }

    /**
     * Stage E: bridge modern neighbor updates to 1.12-style {@code func_189540_a} if present.
     */
    @Override
    protected void neighborChanged(BlockState state, net.minecraft.world.level.Level level, BlockPos pos, Block neighborBlock,
                                   net.minecraft.world.level.redstone.Orientation orientation,
                                   boolean movedByPiston) {
        try {
            java.lang.reflect.Method m = this.getClass().getMethod(
                    "func_189540_a", BlockState.class, net.minecraft.world.level.Level.class, BlockPos.class, Block.class, BlockPos.class);
            m.invoke(this, state, level, pos, neighborBlock, pos);
            return;
        } catch (ReflectiveOperationException ignored) {
            /* no legacy neighbor method */
        }
        super.neighborChanged(state, level, pos, neighborBlock, orientation, movedByPiston);
    }

    /**
     * Stage E: bridge modern use to 1.12 {@code func_180639_a} if present.
     */
    @Override
    protected net.minecraft.world.InteractionResult useWithoutItem(
            BlockState state, net.minecraft.world.level.Level level, BlockPos pos,
            net.minecraft.world.entity.player.Player player, net.minecraft.world.phys.BlockHitResult hitResult) {
        try {
            java.lang.reflect.Method m = this.getClass().getMethod(
                    "func_180639_a",
                    net.minecraft.world.level.Level.class, BlockPos.class, BlockState.class,
                    net.minecraft.world.entity.player.Player.class, EnumHand.class, EnumFacing.class,
                    float.class, float.class, float.class);
            Object r = m.invoke(this, level, pos, state, player, EnumHand.MAIN_HAND, EnumFacing.NORTH, 0f, 0f, 0f);
            if (r instanceof Boolean b && b) {
                return net.minecraft.world.InteractionResult.SUCCESS;
            }
        } catch (ReflectiveOperationException ignored) {
            /* no legacy use method */
        }
        return super.useWithoutItem(state, level, pos, player, hitResult);
    }

    @Override
    protected boolean propagatesSkylightDown(BlockState state) {
        return legacyCutout || legacyNoCollision || super.propagatesSkylightDown(state);
    }

    @Override
    protected float getShadeBrightness(BlockState state, BlockGetter level, BlockPos pos) {
        return (legacyCutout || legacyNoCollision) ? 1.0F : super.getShadeBrightness(state, level, pos);
    }
}
'@
        'EnumHand.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 EnumHand (modern: InteractionHand). */
public enum EnumHand {
    MAIN_HAND,
    OFF_HAND
}
'@
        'NBTTagCompound.java' = @'
package rb.converter.stub112;

/** Stage B stub: 1.12 NBTTagCompound (modern: CompoundTag). */
public class NBTTagCompound {
    public void func_74768_a(String key, int value) {}
    public int func_74762_e(String key) { return 0; }
    public void func_74778_a(String key, String value) {}
    public String func_74779_i(String key) { return ""; }
    public boolean func_74764_b(String key) { return false; }
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

function Invoke-112StageBBlockRewrites {
    param([string]$Root)
    $files = Get-ChildItem (Join-Path $Root 'src\main\java') -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]rb[\\/]converter[\\/]stub112[\\/]' }
    $touched = 0
    $nl = [Environment]::NewLine
    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- Map classic 1.12 block/item types to stub112 (after package modernize may have wrong paths) ---
        $typeMap = [ordered]@{
            'net.minecraft.world.level.material.Material'                    = 'rb.converter.stub112.Material'
            'net.minecraft.block.material.Material'                          = 'rb.converter.stub112.Material'
            'net.minecraft.world.level.block.BlockHorizontal'                = 'rb.converter.stub112.BlockHorizontal'
            'net.minecraft.block.BlockHorizontal'                            = 'rb.converter.stub112.BlockHorizontal'
            'net.minecraft.world.level.block.properties.IProperty'           = 'rb.converter.stub112.IProperty'
            'net.minecraft.world.level.block.properties.PropertyDirection'   = 'rb.converter.stub112.PropertyDirection'
            'net.minecraft.block.properties.IProperty'                       = 'rb.converter.stub112.IProperty'
            'net.minecraft.block.properties.PropertyDirection'               = 'rb.converter.stub112.PropertyDirection'
            'net.minecraft.world.level.block.state.BlockStateContainer'      = 'rb.converter.stub112.BlockStateContainer'
            'net.minecraft.block.state.BlockStateContainer'                  = 'rb.converter.stub112.BlockStateContainer'
            'net.minecraft.util.BlockRenderLayer'                            = 'rb.converter.stub112.BlockRenderLayer'
            'net.minecraft.util.EnumFacing'                                  = 'rb.converter.stub112.EnumFacing'
            'net.minecraft.util.Mirror'                                      = 'rb.converter.stub112.Mirror'
            'net.minecraft.util.Rotation'                                    = 'rb.converter.stub112.Rotation'
            'net.minecraft.util.EnumHand'                                    = 'rb.converter.stub112.EnumHand'
            'net.minecraft.core.AxisAlignedBB'                               = 'rb.converter.stub112.AxisAlignedBB'
            'net.minecraft.util.math.AxisAlignedBB'                          = 'rb.converter.stub112.AxisAlignedBB'
            'net.minecraft.world.IBlockAccess'                               = 'rb.converter.stub112.IBlockAccess'
            'net.minecraft.world.entity.EntityLivingBase'                    = 'rb.converter.stub112.EntityLivingBase'
            'net.minecraft.entity.EntityLivingBase'                          = 'rb.converter.stub112.EntityLivingBase'
            'net.minecraft.world.item.ItemBlock'                             = 'rb.converter.stub112.ItemBlock'
            'net.minecraft.item.ItemBlock'                                   = 'rb.converter.stub112.ItemBlock'
            'net.minecraft.world.item.CreativeTabs'                          = 'rb.converter.stub112.CreativeTabs'
            'net.minecraft.creativetab.CreativeTabs'                         = 'rb.converter.stub112.CreativeTabs'
            'net.minecraft.nbt.NBTTagCompound'                               = 'rb.converter.stub112.NBTTagCompound'
        }
        foreach ($pair in $typeMap.GetEnumerator()) {
            $t = $t -replace [regex]::Escape($pair.Key), $pair.Value
        }

        # Drop dead properties package imports; FQN map above already rewrote specific types
        $t = $t -replace '(?m)^import\s+net\.minecraft\.world\.level\.block\.properties\.\w+\s*;\s*\r?\n', ''

        # Ensure stub imports when simple names appear
        $importPairs = @(
            @('Material', 'import rb.converter.stub112.Material;'),
            @('BlockHorizontal', 'import rb.converter.stub112.BlockHorizontal;'),
            @('PropertyDirection', 'import rb.converter.stub112.PropertyDirection;'),
            @('IProperty', 'import rb.converter.stub112.IProperty;'),
            @('BlockStateContainer', 'import rb.converter.stub112.BlockStateContainer;'),
            @('BlockRenderLayer', 'import rb.converter.stub112.BlockRenderLayer;'),
            @('EnumFacing', 'import rb.converter.stub112.EnumFacing;'),
            @('AxisAlignedBB', 'import rb.converter.stub112.AxisAlignedBB;'),
            @('IBlockAccess', 'import rb.converter.stub112.IBlockAccess;'),
            @('Mirror', 'import rb.converter.stub112.Mirror;'),
            @('Rotation', 'import rb.converter.stub112.Rotation;'),
            @('EntityLivingBase', 'import rb.converter.stub112.EntityLivingBase;'),
            @('ItemBlock', 'import rb.converter.stub112.ItemBlock;'),
            @('CreativeTabs', 'import rb.converter.stub112.CreativeTabs;'),
            @('EnumHand', 'import rb.converter.stub112.EnumHand;'),
            @('NBTTagCompound', 'import rb.converter.stub112.NBTTagCompound;'),
            @('LegacyBlock112', 'import rb.converter.stub112.LegacyBlock112;'),
            @('LegacyBlockState', 'import rb.converter.stub112.LegacyBlockState;')
        )
        foreach ($pair in $importPairs) {
            $simple = $pair[0]
            $imp = $pair[1]
            if ($t -match "(?<![\w.])$([regex]::Escape($simple))\b" -and $t -notmatch [regex]::Escape($imp)) {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)', ('$1' + $nl + $imp + $nl)
            }
        }

        # MCreator / 1.12 blocks: extend LegacyBlock112 when Material-based Block
        if ($t -match 'super\s*\(\s*Material\.' -or ($t -match 'extends\s+Block\b' -and $t -match 'setRegistryName\s*\(|func_149663_c\s*\(|func_149711_c\s*\(')) {
            $t = $t -replace 'extends\s+Block\b', 'extends LegacyBlock112'
            if ($t -match 'extends\s+LegacyBlock112' -and $t -notmatch 'import rb\.converter\.stub112\.LegacyBlock112') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)', ('$1' + $nl + 'import rb.converter.stub112.LegacyBlock112;' + $nl)
            }
        }

        # BlockState fluent 1.12 API → LegacyBlockState in property-heavy block classes
        if ($t -match 'BlockStateContainer|PropertyDirection|IProperty|func_177226_a|func_176223_P') {
            $t = $t -replace 'import\s+net\.minecraft\.world\.level\.block\.state\.BlockState\s*;', 'import rb.converter.stub112.LegacyBlockState;'
            $t = $t -replace '(?<![\w.])BlockState\b', 'LegacyBlockState'
            if ($t -match 'LegacyBlockState' -and $t -notmatch 'import rb\.converter\.stub112\.LegacyBlockState') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)', ('$1' + $nl + 'import rb.converter.stub112.LegacyBlockState;' + $nl)
            }
        }

        # Item.getItemFromBlock
        $t = $t -replace 'Item\.func_150898_a\s*\(', 'rb.converter.stub112.LegacyItems.func_150898_a('

        # Block/Item getRegistryName not on modern Block — replace whole receiver.expr with null
        $t = $t -replace '[a-zA-Z_][\w]*\.getRegistryName\s*\(\s*\)', 'null /* TODO_112 registry name */'

        # BlockPos 1.12 SRG accessors
        $t = $t -replace '\.func_177958_n\s*\(\s*\)', '.getX()'
        $t = $t -replace '\.func_177956_o\s*\(\s*\)', '.getY()'
        $t = $t -replace '\.func_177952_p\s*\(\s*\)', '.getZ()'

        # Minecraft.getMinecraft()
        $t = $t -replace 'Minecraft\.func_71410_x\s*\(\s*\)', 'Minecraft.getInstance()'

        # SoundType SRG fields → modern constants
        $soundMap = [ordered]@{
            'field_185848_a' = 'WOOD'
            'field_185849_b' = 'GRAVEL'
            'field_185850_c' = 'GRASS'
            'field_185851_d' = 'STONE'
            'field_185852_e' = 'METAL'
            'field_185853_f' = 'GLASS'
            'field_185854_g' = 'WOOL'
            'field_185855_h' = 'SAND'
            'field_185856_i' = 'SNOW'
            'field_185857_j' = 'LADDER'
            'field_185858_k' = 'ANVIL'
            'field_185859_l' = 'SLIME_BLOCK'
        }
        foreach ($k in $soundMap.Keys) {
            $t = $t -replace "SoundType\.$k\b", "SoundType.$($soundMap[$k])"
        }
        $t = $t -replace 'SoundType\.field_\w+', 'SoundType.STONE'
        # Unknown Material SRG fields → ROCK stub instance
        $t = $t -replace 'Material\.field_(?!151573_f|151576_e|151575_d|151578_c|151579_a|151577_b|151583_m|151584_j|151592_s|151594_q)\w+', 'Material.ROCK'

        # Soft-fix leftover world. SRG in variable classes
        $t = $t -replace '\bworld\.field_72995_K\b', 'false /* TODO_112 isRemote */'
        # World→Level renamed the type/param to Level but left body `world` refs
        $t = $t -replace '(?<![\w."])\bworld\b(?![\w"])', 'Level'

        # static Block field .func_176223_P() not on modern Block
        $t = $t -replace '[\w.]+\.func_176223_P\s*\(\s*\)', '(new rb.converter.stub112.LegacyBlockState())'

        # Client scheduled tasks / player field
        $t = $t -replace 'Minecraft\.getInstance\(\)\.func_152344_a\s*\(', 'rb.converter.stub112.LegacyClient.addScheduledTask('
        $t = $t -replace 'Minecraft\.getInstance\(\)\.field_71439_g\.field_70170_p', 'null'
        $t = $t -replace 'Minecraft\.getInstance\(\)\.field_71439_g', 'null'

        # Level SRG helpers used by procedures (no-ops via LegacyLevel)
        $t = $t -replace '\bLevel\.func_175698_g\s*\(', 'rb.converter.stub112.LegacyLevel.destroyBlock(Level, '
        $t = $t -replace '\bLevel\.func_180501_a\s*\(', 'rb.converter.stub112.LegacyLevel.setBlockState(Level, '
        $t = $t -replace '\bLevel\.func_175687_A\s*\(', 'rb.converter.stub112.LegacyLevel.getRedstonePower(Level, '
        $t = $t -replace '\bLevel\.func_175693_T\s*\(\s*\)', 'rb.converter.stub112.LegacyLevel.getMapStorage(Level)'
        $t = $t -replace '\bLevel\.getPerWorldStorage\s*\(\s*\)', 'rb.converter.stub112.LegacyLevel.getPerWorldStorage(Level)'

        if ($t -match 'LegacyBlock112|stub112\.(Material|EnumFacing|ItemBlock)' -and $t -notmatch 'TODO_112_STAGE_B') {
            $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                ('$1' + $nl + '// TODO_112_STAGE_B: block/item 1.12 API stubbed - replace with BlockBehaviour.Properties + BlockItem.' + $nl)
        }

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
}

function Invoke-112StageCRegistryPass {
    param([string]$Root)
    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { return 0 }
    $files = Get-ChildItem $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]rb[\\/]converter[\\/]stub112[\\/]' }
    $touched = 0
    $nl = [Environment]::NewLine

    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t
        $name = $f.Name

        # --- Elements*: replace empty ASM discovery with classpath annotation scan ---
        if ($name -match '^Elements\w+\.java$') {
            $elClass = [IO.Path]::GetFileNameWithoutExtension($name)
            # Rewrite from start of preInit through Collections.sort (keeps sort + initElements + network)
            $t2 = [regex]::Replace($t, '(?s)public\s+void\s+preInit\s*\(\s*\)\s*\{.*?(\r?\n\s*Collections\.sort\(this\.elements\);)', {
                param($m)
                $sortLine = $m.Groups[1].Value
                @"
public void preInit() {
      try {
         for (Class<?> clazz : rb.converter.stub112.ElementDiscovery.findAnnotated(
               $elClass.ModElement.Tag.class, this.getClass().getPackageName())) {
            if (clazz.getSuperclass() == $elClass.ModElement.class) {
               this.elements.add(($elClass.ModElement)clazz.getConstructor(this.getClass()).newInstance(this));
            }
         }
      } catch (Exception e) {
         e.printStackTrace();
      }
$sortLine
"@
            }, 1)
            $t = $t2
            if ($t -match 'ElementDiscovery\.findAnnotated') {
                $t = $t -replace '(?m)^import\s+rb\.converter\.stub112\.ASMDataTable\.ASMData;\s*\r?\n', ''
                if ($t -notmatch 'TODO_112_STAGE_C') {
                    $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                        ('$1' + $nl + '// TODO_112_STAGE_C: element discovery via classpath scan; wire real RegisterEvent on @Mod.' + $nl)
                }
            }
        }

        # --- MCreator block elements: assignable block field + single-instance BlockItem ---
        if ($t -match 'extends\s+LegacyBlock112' -or $t -match 'new\s+\w+\.BlockCustom') {
            $t = $t -replace '(?m)^\s*@ObjectHolder\s*\([^)]*\)\s*\r?\n', ''
            $t = $t -replace 'public\s+static\s+final\s+Block\s+block\s*=\s*null\s*;', 'public static Block block;'
            $t = $t -replace 'public\s+static\s+final\s+Block\s+block\s*;', 'public static Block block;'

            $pattern = 'this\.elements\.blocks\.add\(\(\)\s*->\s*new\s+([\w.]+)\.BlockCustom\(\)\);\s*this\.elements\.items\.add\(\(\)\s*->\s*\(Item\)new\s+ItemBlock\(block\)[^;]*;'
            $t = [regex]::Replace($t, $pattern, {
                param($m)
                $cn = $m.Groups[1].Value
                @"
{
         $cn.BlockCustom __stageC_b = new $cn.BlockCustom();
         block = __stageC_b;
         net.minecraft.world.item.BlockItem __stageC_i = new net.minecraft.world.item.BlockItem(__stageC_b, new net.minecraft.world.item.Item.Properties());
         rb.converter.stub112.LegacyBlocks.rememberItem(__stageC_i, __stageC_b);
         this.elements.blocks.add(() -> __stageC_b);
         this.elements.items.add(() -> __stageC_i);
      }
"@
            })

            if ($t -match '__stageC_b' -and $t -notmatch 'TODO_112_STAGE_C') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_STAGE_C: single-instance block + real BlockItem; register via mod RegisterEvent.' + $nl)
            }
        }

        # --- @Mod class: real RegisterEvent + creative tab dump into BUILDING_BLOCKS ---
        if ($t -match '@Mod\s*\(' -and $t -match 'public\s+class\s+\w+') {
            if ($t -notmatch 'TODO_112_STAGE_C_REG') {
                # Ensure imports
                $need = @(
                    'import net.neoforged.neoforge.registries.RegisterEvent;',
                    'import net.minecraft.core.registries.Registries;',
                    'import net.minecraft.resources.Identifier;',
                    'import net.neoforged.neoforge.event.BuildCreativeModeTabContentsEvent;',
                    'import net.minecraft.world.item.CreativeModeTabs;',
                    'import net.minecraft.world.item.BlockItem;'
                )
                foreach ($imp in $need) {
                    if ($t -notmatch [regex]::Escape($imp)) {
                        $t = $t -replace '(?m)^(package\s+[^;]+;\s*)', ('$1' + $nl + $imp + $nl)
                    }
                }

                # Upgrade constructor body to register RegisterEvent + creative listener
                if ($t -match 'modEventBus\.addListener\(this::commonSetup\)') {
                    $t = $t -replace 'modEventBus\.addListener\(this::commonSetup\);', @'
modEventBus.addListener(this::commonSetup);
        modEventBus.addListener(this::onRegisterBlocksItems);
        modEventBus.addListener(this::addCreative);
'@
                }

                # Inject Stage C registration methods before commonSetup if missing
                if ($t -notmatch 'onRegisterBlocksItems\s*\(') {
                    $regMethods = @'

    // TODO_112_STAGE_C_REG: real NeoForge RegisterEvent wiring from Elements supplier lists.
    private void onRegisterBlocksItems(final RegisterEvent event) {
        if (this.elements == null) return;
        event.register(Registries.BLOCK, helper -> {
            for (java.util.function.Supplier<Block> s : this.elements.getBlocks()) {
                Block b = s.get();
                if (b == null) continue;
                String path = rb.converter.stub112.LegacyBlocks.resolveBlockPath(b);
                if (path == null || path.isEmpty()) path = "block_" + System.identityHashCode(b);
                helper.register(Identifier.fromNamespaceAndPath(MODID, path), b);
            }
        });
        event.register(Registries.ITEM, helper -> {
            for (java.util.function.Supplier<Item> s : this.elements.getItems()) {
                Item i = s.get();
                if (i == null) continue;
                String path = rb.converter.stub112.LegacyBlocks.resolveItemPath(i);
                if (path == null || path.isEmpty()) path = "item_" + System.identityHashCode(i);
                helper.register(Identifier.fromNamespaceAndPath(MODID, path), i);
            }
        });
    }

    private void addCreative(final BuildCreativeModeTabContentsEvent event) {
        if (this.elements == null) return;
        if (event.getTabKey() == CreativeModeTabs.BUILDING_BLOCKS) {
            for (java.util.function.Supplier<Item> s : this.elements.getItems()) {
                Item i = s.get();
                if (i != null) event.accept(i);
            }
        }
    }
'@
                    if ($t -match 'private void commonSetup') {
                        $t = $t -replace 'private void commonSetup', ($regMethods + $nl + '    private void commonSetup')
                    }
                    elseif ($t -match 'private void commonSetup\(final FMLCommonSetupEvent') {
                        $t = $t -replace 'private void commonSetup\(final FMLCommonSetupEvent', ($regMethods + $nl + '    private void commonSetup(final FMLCommonSetupEvent')
                    }
                }

                # Comment out obsolete stub RegistryEvent subscribers (avoid confusion)
                $t = $t -replace '(?m)^(\s*)@SubscribeEvent\s*\r?\n(\s*)public void register(Blocks|Items|Biomes|Entities|Potions|Sounds)\b',
                    ('$1// Stage C: legacy stub registry handler disabled' + $nl + '$1// @SubscribeEvent' + $nl + '$2public void register$3')
            }
        }

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }

    # Stage C: convert 1.12 en_us.lang → en_us.json (best-effort)
    $langFiles = Get-ChildItem (Join-Path $Root 'src\main\resources') -Recurse -Filter 'en_us.lang' -File -ErrorAction SilentlyContinue
    foreach ($lf in $langFiles) {
        $jsonPath = Join-Path $lf.DirectoryName 'en_us.json'
        if (Test-Path $jsonPath) { continue }
        $map = [ordered]@{}
        foreach ($line in Get-Content -LiteralPath $lf.FullName) {
            $trim = $line.Trim()
            if (-not $trim -or $trim.StartsWith('#')) { continue }
            $eq = $trim.IndexOf('=')
            if ($eq -lt 1) { continue }
            $k = $trim.Substring(0, $eq).Trim()
            $v = $trim.Substring($eq + 1).Trim()
            # Escape JSON string
            $v = $v.Replace('\', '\\').Replace('"', '\"')
            $map[$k] = $v
        }
        if ($map.Count -eq 0) { continue }
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('{')
        $i = 0
        foreach ($k in $map.Keys) {
            $i++
            $comma = if ($i -lt $map.Count) { ',' } else { '' }
            [void]$sb.AppendLine(('  "{0}": "{1}"{2}' -f $k, $map[$k], $comma))
        }
        [void]$sb.AppendLine('}')
        [System.IO.File]::WriteAllText($jsonPath, $sb.ToString())
        # Keep .lang as reference
        Move-Item -LiteralPath $lf.FullName -Destination ($lf.FullName + '.112-reference') -Force -ErrorAction SilentlyContinue
        $touched++
    }

    return $touched
}

function Invoke-112StageDBehaviourPass {
    param([string]$Root)
    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { return 0 }
    $files = Get-ChildItem $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]rb[\\/]converter[\\/]stub112[\\/]' }
    $touched = 0
    $nl = [Environment]::NewLine
    $cutoutPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    foreach ($f in $files) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t

        # --- Fold Material + sound/hardness/light/opacity into LegacyProps.of(...) ---
        $propPattern = '(?s)super\s*\(\s*(Material\.\w+)\s*\)\s*;\s*this\.setRegistryName\s*\(\s*("([^"]+)")\s*\)\s*;\s*this\.func_149663_c\s*\(\s*("([^"]+)")\s*\)\s*;\s*this\.func_149672_a\s*\(\s*(SoundType\.\w+)\s*\)\s*;\s*this\.func_149711_c\s*\(\s*([0-9eE.+-]+F)\s*\)\s*;\s*this\.func_149752_b\s*\(\s*([0-9eE.+-]+F)\s*\)\s*;\s*this\.func_149715_a\s*\(\s*([0-9eE.+-]+F)\s*\)\s*;\s*this\.func_149713_g\s*\(\s*(\d+)\s*\)\s*;'
        $t = [regex]::Replace($t, $propPattern, {
            param($m)
            $mat = $m.Groups[1].Value
            $regQ = $m.Groups[2].Value
            $unlocQ = $m.Groups[4].Value
            $sound = $m.Groups[6].Value
            $hard = $m.Groups[7].Value
            $resist = $m.Groups[8].Value
            $light = $m.Groups[9].Value
            $opacity = $m.Groups[10].Value
            $path = $m.Groups[3].Value
            @"
super(rb.converter.stub112.LegacyProps.of($mat, $sound, $hard, $resist, $light, $opacity));
         this.setRegistryName($regQ);
         this.func_149663_c($unlocQ);
"@
        })

        # Facing blocks → real horizontal state holder
        if ($t -match 'PropertyDirection\s+FACING|BlockHorizontal\.field_185512_D|LegacyHorizontalBlock112') {
            $t = $t -replace 'extends\s+LegacyBlock112\b', 'extends LegacyHorizontalBlock112'
            $t = $t -replace 'public\s+static\s+final\s+PropertyDirection\s+FACING\s*=\s*BlockHorizontal\.field_185512_D\s*;',
                '// Stage D: FACING = LegacyHorizontalBlock112.FACING (real BlockState property)'
            $t = $t -replace 'this\.func_180632_j\s*\([^;]*\);',
                '// Stage D: default facing registered by LegacyHorizontalBlock112'
            # Legacy BlockStateContainer cannot hold modern EnumProperty
            $t = $t -replace 'new\s+IProperty\s*\[\s*\]\s*\{\s*FACING\s*\}',
                'new IProperty[]{ /* Stage D: real FACING on LegacyHorizontalBlock112 */ }'
            # Soft-disable leftover 1.12 state helpers that still mention FACING with LegacyBlockState
            $t = $t -replace '(?s)(public\s+LegacyBlockState\s+func_185499_a\s*\([^)]*\)\s*\{)(.*?)(\n\s*\})',
                '$1 return state; /* Stage D: use Block.rotate */ $3'
            $t = $t -replace '(?s)(public\s+LegacyBlockState\s+func_185471_a\s*\([^)]*\)\s*\{)(.*?)(\n\s*\})',
                '$1 return state; /* Stage D: use Block.mirror */ $3'
            $t = $t -replace '(?s)(public\s+LegacyBlockState\s+func_176203_a\s*\([^)]*\)\s*\{)(.*?)(\n\s*\})',
                '$1 return new rb.converter.stub112.LegacyBlockState(); $3'
            $t = $t -replace '(?s)(public\s+int\s+func_176201_c\s*\([^)]*\)\s*\{)(.*?)(\n\s*\})',
                '$1 return 0; $3'
            $t = $t -replace '(?s)(public\s+LegacyBlockState\s+func_180642_a\s*\([^)]*\)\s*\{)(.*?)(\n\s*\})',
                '$1 return new rb.converter.stub112.LegacyBlockState(); /* placement via getStateForPlacement */ $3'
            if ($t -match 'LegacyHorizontalBlock112' -and $t -notmatch 'import rb\.converter\.stub112\.LegacyHorizontalBlock112') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + 'import rb.converter.stub112.LegacyHorizontalBlock112;' + $nl)
            }
        }

        # No-collision decorations (NULL_AABB)
        if ($t -match 'return\s+field_185506_k\b') {
            if ($t -match 'super\(rb\.converter\.stub112\.LegacyProps\.of') {
                $t = $t -replace '(super\(rb\.converter\.stub112\.LegacyProps\.of\([^;]+;\s*)',
                    ('$1' + $nl + '         this.setLegacyNoCollision();' + $nl + '         ')
            }
            elseif ($t -match 'super\(Material\.') {
                $t = $t -replace '(super\(Material\.\w+\);\s*)',
                    ('$1' + $nl + '         this.setLegacyNoCollision();' + $nl + '         ')
            }
        }

        # Cutout layers
        if ($t -match 'BlockRenderLayer\.CUTOUT') {
            if ($t -match 'super\(rb\.converter\.stub112\.LegacyProps\.of') {
                $t = $t -replace '(super\(rb\.converter\.stub112\.LegacyProps\.of\([^;]+;\s*)',
                    ('$1' + $nl + '         this.setLegacyCutout();' + $nl + '         ')
            }
            elseif ($t -match 'setLegacyNoCollision') {
                $t = $t -replace '(this\.setLegacyNoCollision\(\);\s*)',
                    ('$1' + $nl + '         this.setLegacyCutout();' + $nl + '         ')
            }
            # collect registry paths for model render_type injection
            [regex]::Matches($t, 'setRegistryName\(\s*"([^"]+)"\s*\)') | ForEach-Object {
                [void]$cutoutPaths.Add($_.Groups[1].Value)
            }
        }

        # Ensure LegacyProps import when used
        if ($t -match 'LegacyProps\.of' -and $t -notmatch 'import rb\.converter\.stub112\.LegacyProps') {
            $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                ('$1' + $nl + 'import rb.converter.stub112.LegacyProps;' + $nl)
        }

        if ($t -match 'LegacyProps\.of|LegacyHorizontalBlock112|setLegacyNoCollision|setLegacyCutout') {
            if ($t -notmatch 'TODO_112_STAGE_D') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_STAGE_D: Properties/facing/collision applied; refine shapes & tabs as needed.' + $nl)
            }
        }

        # --- @Mod: register CreativeModeTabs from CreativeTabs bridge; drop BUILDING_BLOCKS dump ---
        if ($t -match '@Mod\s*\(' -and $t -match 'onRegisterBlocksItems') {
            $need = @(
                'import net.minecraft.world.item.CreativeModeTab;',
                'import net.minecraft.network.chat.Component;',
                'import rb.converter.stub112.CreativeTabs;'
            )
            foreach ($imp in $need) {
                if ($t -notmatch [regex]::Escape($imp)) {
                    $t = $t -replace '(?m)^(package\s+[^;]+;\s*)', ('$1' + $nl + $imp + $nl)
                }
            }

            # Expand RegisterEvent to also register creative tabs
            if ($t -notmatch 'CREATIVE_MODE_TAB') {
                $t = $t -replace '(event\.register\(Registries\.ITEM,\s*helper\s*->\s*\{[\s\S]*?\}\);)', @'
$1
        event.register(Registries.CREATIVE_MODE_TAB, helper -> {
            for (rb.converter.stub112.CreativeTabs tab : rb.converter.stub112.CreativeTabs.allTabs()) {
                final rb.converter.stub112.CreativeTabs tabRef = tab;
                helper.register(Identifier.fromNamespaceAndPath(MODID, tabRef.registryPath()),
                    CreativeModeTab.builder()
                        .title(Component.literal(tabRef.getTabLabel()))
                        .icon(tabRef::createIcon)
                        .displayItems((params, out) -> {
                            for (Block b : tabRef.getBlocks()) {
                                Item it = b.asItem();
                                if (it != null && it != net.minecraft.world.item.Items.AIR) {
                                    out.accept(it);
                                }
                            }
                        })
                        .build());
            }
        });
'@
            }

            # Prefer custom tabs over dumping everything into BUILDING_BLOCKS
            if ($t -match 'CreativeModeTabs\.BUILDING_BLOCKS') {
                $t = $t -replace '(?s)private void addCreative\(final BuildCreativeModeTabContentsEvent event\)\s*\{[\s\S]*?\n    \}', @'
private void addCreative(final BuildCreativeModeTabContentsEvent event) {
        // Stage D: items are attached to registered CreativeModeTabs via CreativeTabs bridge.
    }
'@
            }
        }

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }

    # Inject render_type into block/item models for cutout registry paths
    if ($cutoutPaths.Count -gt 0) {
        $modelRoots = @(
            (Join-Path $Root 'src\main\resources\assets')
        )
        foreach ($assets in $modelRoots) {
            if (-not (Test-Path $assets)) { continue }
            $models = Get-ChildItem $assets -Recurse -Include '*.json' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '[\\/]models[\\/](block|item)[\\/]' }
            foreach ($mf in $models) {
                $base = [IO.Path]::GetFileNameWithoutExtension($mf.Name)
                if (-not $cutoutPaths.Contains($base)) { continue }
                $raw = [System.IO.File]::ReadAllText($mf.FullName)
                if ($raw -match '"render_type"') { continue }
                # Insert render_type after opening brace
                $newRaw = [regex]::Replace($raw, '^\s*\{', "{`r`n  `"render_type`": `"minecraft:cutout_mipped`",", 1)
                if ($newRaw -ne $raw) {
                    [System.IO.File]::WriteAllText($mf.FullName, $newRaw)
                    $touched++
                }
            }
        }
    }

    return $touched
}

function Invoke-112StageEPlusPass {
    param(
        [string]$Root,
        [string]$ModId = 'examplemod'
    )
    $touched = 0
    $nl = [Environment]::NewLine
    $javaRoot = Join-Path $Root 'src\main\java'
    $assetsRoot = Join-Path $Root 'src\main\resources\assets'
    $dataRoot = Join-Path $Root 'src\main\resources\data'
    $blockNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    # ---------- Java: shapes + redstone method renames ----------
    if (Test-Path $javaRoot) {
        $files = Get-ChildItem $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]rb[\\/]converter[\\/]stub112[\\/]' }
        foreach ($f in $files) {
            $t = [System.IO.File]::ReadAllText($f.FullName)
            $o = $t

            # Collect registry names for loot/tags
            [regex]::Matches($t, 'setRegistryName\(\s*"([^"]+)"\s*\)') | ForEach-Object {
                [void]$blockNames.Add($_.Groups[1].Value)
            }

            # Inject setLegacyShape from simple bounding-box returns (func_185496_a etc.)
            $shapeMatch = [regex]::Match($t, 'return\s+new\s+AxisAlignedBB\s*\(\s*([0-9eE.+-]+)\s*,\s*([0-9eE.+-]+)\s*,\s*([0-9eE.+-]+)\s*,\s*([0-9eE.+-]+)\s*,\s*([0-9eE.+-]+)\s*,\s*([0-9eE.+-]+)\s*\)\s*;')
            if ($shapeMatch.Success -and $t -match 'setRegistryName' -and $t -notmatch 'setLegacyShape\s*\(') {
                $a = $shapeMatch.Groups[1].Value; $b = $shapeMatch.Groups[2].Value; $c = $shapeMatch.Groups[3].Value
                $d = $shapeMatch.Groups[4].Value; $e = $shapeMatch.Groups[5].Value; $g = $shapeMatch.Groups[6].Value
                if ($t -match 'super\(rb\.converter\.stub112\.LegacyProps\.of') {
                    $t = $t -replace '(super\(rb\.converter\.stub112\.LegacyProps\.of\([^;]+;\s*)',
                        ('$1' + $nl + "         this.setLegacyShape($a, $b, $c, $d, $e, $g);" + $nl + '         ')
                }
                elseif ($t -match 'this\.setLegacyNoCollision\(\)') {
                    $t = $t -replace '(this\.setLegacyNoCollision\(\);\s*)',
                        ('$1' + $nl + "         this.setLegacyShape($a, $b, $c, $d, $e, $g);" + $nl + '         ')
                }
                elseif ($t -match 'this\.setRegistryName\(') {
                    $t = $t -replace '(this\.setRegistryName\([^;]+;\s*)',
                        ("         this.setLegacyShape($a, $b, $c, $d, $e, $g);" + $nl + '         $1')
                }
            }

            # Redstone power → modern signal methods (Direction, BlockGetter)
            $t = $t -replace 'public\s+int\s+func_180656_a\s*\(\s*BlockState\s+(\w+)\s*,\s*IBlockAccess\s+(\w+)\s*,\s*BlockPos\s+(\w+)\s*,\s*EnumFacing\s+(\w+)\s*\)',
                '@Override`r`n      protected int getSignal(BlockState $1, net.minecraft.world.level.BlockGetter $2, BlockPos $3, net.minecraft.core.Direction $4)'
            $t = $t -replace 'public\s+int\s+func_176211_b\s*\(\s*BlockState\s+(\w+)\s*,\s*IBlockAccess\s+(\w+)\s*,\s*BlockPos\s+(\w+)\s*,\s*EnumFacing\s+(\w+)\s*\)',
                '@Override`r`n      protected int getDirectSignal(BlockState $1, net.minecraft.world.level.BlockGetter $2, BlockPos $3, net.minecraft.core.Direction $4)'

            # canConnectRedstone: prefer NeoForge extension signature
            $t = $t -replace 'public\s+boolean\s+canConnectRedstone\s*\(\s*BlockState\s+(\w+)\s*,\s*IBlockAccess\s+(\w+)\s*,\s*BlockPos\s+(\w+)\s*,\s*EnumFacing\s+(\w+)\s*\)',
                'public boolean canConnectRedstone(BlockState $1, net.minecraft.world.level.BlockGetter $2, BlockPos $3, net.minecraft.core.Direction $4)'

            if ($t -match 'setLegacyShape|getSignal\(|getDirectSignal\(' -and $t -notmatch 'TODO_112_STAGE_E') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_STAGE_E: shapes/signal bridges; verify in-game.' + $nl)
            }

            if ($t -ne $o) {
                # Fix accidental backtick-r from replace above
                $t = $t -replace '`r`n', $nl
                [System.IO.File]::WriteAllText($f.FullName, $t)
                $touched++
            }
        }
    }

    # ---------- Resources: blockstates + texture paths ----------
    if (Test-Path $assetsRoot) {
        $modAssets = Get-ChildItem $assetsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'minecraft' }
        foreach ($modDir in $modAssets) {
            $modid = $modDir.Name

            # textures/blocks → textures/block
            $blocksTex = Join-Path $modDir.FullName 'textures\blocks'
            $blockTex = Join-Path $modDir.FullName 'textures\block'
            if ((Test-Path $blocksTex) -and -not (Test-Path $blockTex)) {
                Move-Item -LiteralPath $blocksTex -Destination $blockTex -Force
                $touched++
            }
            elseif ((Test-Path $blocksTex) -and (Test-Path $blockTex)) {
                Get-ChildItem $blocksTex -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $rel = $_.FullName.Substring($blocksTex.Length).TrimStart('\', '/')
                    $dest = Join-Path $blockTex $rel
                    $destDir = Split-Path $dest -Parent
                    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                    if (-not (Test-Path $dest)) { Copy-Item $_.FullName $dest -Force }
                }
                $touched++
            }

            # Rewrite model/blockstate JSON refs: :blocks/ → :block/ ; parent block/cube → minecraft:block/cube
            $jsonFiles = Get-ChildItem $modDir.FullName -Recurse -Filter '*.json' -File -ErrorAction SilentlyContinue
            foreach ($jf in $jsonFiles) {
                $raw = [System.IO.File]::ReadAllText($jf.FullName)
                $n = $raw
                $n = $n -replace ('"' + [regex]::Escape($modid) + ':blocks/'), ('"' + $modid + ':block/')
                $n = $n -replace '"minecraft:blocks/', '"minecraft:block/'
                $n = $n -replace '"parent"\s*:\s*"block/', '"parent": "minecraft:block/'
                $n = $n -replace '"parent"\s*:\s*"item/', '"parent": "minecraft:item/'
                if ($n -ne $raw) {
                    [System.IO.File]::WriteAllText($jf.FullName, $n)
                    $touched++
                }
            }

            # Blockstates: normal → "", model path → mod:block/name
            $bsDir = Join-Path $modDir.FullName 'blockstates'
            if (Test-Path $bsDir) {
                Get-ChildItem $bsDir -Filter '*.json' -File | ForEach-Object {
                    $raw = [System.IO.File]::ReadAllText($_.FullName)
                    $n = $raw
                    # "model": "modid:name" → "model": "modid:block/name" when not already block/ or item/ or custom/
                    $n = [regex]::Replace($n, '"model"\s*:\s*"' + [regex]::Escape($modid) + ':((?!block/|item/|custom/)[^"]+)"',
                        '"model": "' + $modid + ':block/$1"')
                    # Replace variant key "normal" with empty string key for modern loaders
                    $n = $n -replace '"normal"\s*:', '"":'
                    # If facing variants exist, drop the empty-default entry (1.12 often had both)
                    if ($n -match '"facing=') {
                        $n = [regex]::Replace($n, '(?s),?\s*""\s*:\s*\{[^{}]*\}', '')
                        # clean trailing commas before closing braces in variants object
                        $n = $n -replace ',(\s*})', '$1'
                        $n = $n -replace '(\{\s*),', '$1'
                    }
                    if ($n -ne $raw) {
                        [System.IO.File]::WriteAllText($_.FullName, $n)
                        $touched++
                    }
                    # Also collect names from filenames
                    [void]$blockNames.Add([IO.Path]::GetFileNameWithoutExtension($_.Name))
                }
            }
        }
    }

    # ---------- data/: loot tables + mineable tag ----------
    if ($blockNames.Count -eq 0 -and $ModId) {
        # fallback from blockstates if java scan empty
        $bs = Join-Path $assetsRoot "$ModId\blockstates"
        if (Test-Path $bs) {
            Get-ChildItem $bs -Filter '*.json' | ForEach-Object { [void]$blockNames.Add([IO.Path]::GetFileNameWithoutExtension($_.Name)) }
        }
    }

    if ($blockNames.Count -gt 0) {
        $modData = if ($ModId) { $ModId } else { 'examplemod' }
        # prefer assets mod id if single
        $assetMods = @(Get-ChildItem $assetsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'minecraft' } | ForEach-Object { $_.Name })
        if ($assetMods.Count -ge 1) { $modData = $assetMods[0] }

        $lootDir = Join-Path $dataRoot "$modData\loot_table\blocks"
        New-Item -ItemType Directory -Force -Path $lootDir | Out-Null
        foreach ($bn in ($blockNames | Sort-Object)) {
            if (-not $bn) { continue }
            $path = ($bn -replace '^.*:', '')
            $lootFile = Join-Path $lootDir ($path + '.json')
            if (Test-Path $lootFile) { continue }
            $loot = @"
{
  "type": "minecraft:block",
  "pools": [
    {
      "rolls": 1,
      "entries": [
        {
          "type": "minecraft:item",
          "name": "$modData`:$path"
        }
      ],
      "conditions": [
        {
          "condition": "minecraft:survives_explosion"
        }
      ]
    }
  ]
}
"@
            # Fix accidental escape of colon in name - PowerShell double-quote
            $loot = $loot -replace "$modData``:$path", "$modData`:$path"
            $loot = @"
{
  "type": "minecraft:block",
  "pools": [
    {
      "rolls": 1,
      "entries": [
        {
          "type": "minecraft:item",
          "name": "${modData}:${path}"
        }
      ],
      "conditions": [
        {
          "condition": "minecraft:survives_explosion"
        }
      ]
    }
  ]
}
"@
            [System.IO.File]::WriteAllText($lootFile, $loot.Trim() + "`r`n")
            $touched++
        }

        # mineable/pickaxe tag
        $tagDir = Join-Path $dataRoot 'minecraft\tags\block\mineable'
        New-Item -ItemType Directory -Force -Path $tagDir | Out-Null
        $tagFile = Join-Path $tagDir 'pickaxe.json'
        $values = ($blockNames | ForEach-Object {
            $p = ($_ -replace '^.*:', '')
            "    `"${modData}:${p}`""
        }) -join ",`r`n"
        $tagJson = "{`r`n  `"replace`": false,`r`n  `"values`": [`r`n$values`r`n  ]`r`n}`r`n"
        [System.IO.File]::WriteAllText($tagFile, $tagJson)
        $touched++

        # optional: needs_stone_tool empty skip
    }

    return $touched
}

function Invoke-112StageFRuntimeFixPass {
    param([string]$Root)
    $javaRoot = Join-Path $Root 'src\main\java'
    if (-not (Test-Path $javaRoot)) { return 0 }
    $touched = 0
    $nl = [Environment]::NewLine

    # Collect fully-qualified class names of files annotated with ModElement.Tag
    $elementFqns = New-Object System.Collections.Generic.List[string]
    $javaFiles = Get-ChildItem $javaRoot -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]rb[\\/]converter[\\/]stub112[\\/]' }
    foreach ($jf in $javaFiles) {
        $raw = [System.IO.File]::ReadAllText($jf.FullName)
        if ($raw -notmatch 'ModElement\.Tag') { continue }
        if ($raw -notmatch '(?m)^public\s+class\s+(\w+)') { continue }
        $simple = $Matches[1]
        # skip Elements* host classes themselves
        if ($simple -match '^Elements') { continue }
        $pkg = $null
        if ($raw -match '(?m)^package\s+([\w.]+)\s*;') { $pkg = $Matches[1] }
        if (-not $pkg) { continue }
        $elementFqns.Add("$pkg.$simple") | Out-Null
    }
    $elementFqns = @($elementFqns | Sort-Object -Unique)
    Write-Info "Stage F: found $($elementFqns.Count) ModElement class(es) for explicit bootstrap"

    foreach ($f in $javaFiles) {
        $t = [System.IO.File]::ReadAllText($f.FullName)
        $o = $t
        $name = $f.Name

        # --- Elements host: inject GENERATED_ELEMENT_CLASS_NAMES + reliable preInit loader ---
        if ($name -match '^Elements\w+\.java$') {
            $elClass = [IO.Path]::GetFileNameWithoutExtension($name)
            $arrLines = ($elementFqns | ForEach-Object { '      "' + $_ + '"' }) -join ",$nl"
            if (-not $arrLines) { $arrLines = '      // (no tagged elements found at convert time)' }

            # Insert / replace generated array field
            $genField = @"
/** Stage F: converter-generated explicit element list (ModLauncher-safe). */
   public static final String[] GENERATED_ELEMENT_CLASS_NAMES = new String[] {
$arrLines
   };
"@
            if ($t -match 'GENERATED_ELEMENT_CLASS_NAMES') {
                $t = [regex]::Replace($t,
                    '(?s)/\*\* Stage F:.*?public\s+static\s+final\s+String\s*\[\s*\]\s*GENERATED_ELEMENT_CLASS_NAMES\s*=\s*new\s+String\s*\[\s*\]\s*\{.*?\};|public\s+static\s+final\s+String\s*\[\s*\]\s*GENERATED_ELEMENT_CLASS_NAMES\s*=\s*new\s+String\s*\[\s*\]\s*\{.*?\};',
                    $genField.Trim())
            }
            else {
                $t = $t -replace ("(public\s+class\s+" + [regex]::Escape($elClass) + "\s*\{)"),
                    ('$1' + $nl + '   ' + $genField.Trim() + $nl)
            }

            # Rewrite preInit discovery to prefer generated list
            $t = [regex]::Replace($t, '(?s)public\s+void\s+preInit\s*\(\s*\)\s*\{.*?(\r?\n\s*Collections\.sort\(this\.elements\);)', {
                param($m)
                $sortLine = $m.Groups[1].Value
                @"
public void preInit() {
      int loaded = 0;
      try {
         for (String className : GENERATED_ELEMENT_CLASS_NAMES) {
            if (className == null || className.isEmpty()) continue;
            Class<?> clazz = Class.forName(className);
            if (clazz.getSuperclass() == $elClass.ModElement.class) {
               this.elements.add(($elClass.ModElement)clazz.getConstructor(this.getClass()).newInstance(this));
               loaded++;
            }
         }
      } catch (Exception e) {
         System.err.println("[112to262] Generated element bootstrap failed: " + e);
         e.printStackTrace();
      }
      if (loaded == 0) {
         System.err.println("[112to262] Generated list loaded 0 elements; falling back to classpath scan");
         try {
            for (Class<?> clazz : rb.converter.stub112.ElementDiscovery.findAnnotated(
                  $elClass.ModElement.Tag.class, this.getClass().getPackageName())) {
               if (clazz.getSuperclass() == $elClass.ModElement.class) {
                  this.elements.add(($elClass.ModElement)clazz.getConstructor(this.getClass()).newInstance(this));
               }
            }
         } catch (Exception e) {
            System.err.println("[112to262] Classpath element scan failed: " + e);
            e.printStackTrace();
         }
      }
$sortLine
"@
            }, 1)

            # After initElements, log counts (inject once after forEach initElements)
            if ($t -notmatch '\[112to262\] elements=') {
                $t = $t -replace '(this\.elements\.forEach\([^;]+initElements\)\s*;)',
                    ('$1' + $nl +
                     '      System.out.println("[112to262] elements=" + this.elements.size()' +
                     ' + " blocks=" + this.blocks.size() + " items=" + this.items.size()' +
                     ' + " tabs=" + rb.converter.stub112.CreativeTabs.allTabs().size());')
            }

            if ($t -notmatch 'TODO_112_STAGE_F') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_STAGE_F: explicit GENERATED_ELEMENT_CLASS_NAMES bootstrap for runtime.' + $nl)
            }
        }

        # --- @Mod: creative dump fallback + better tab displayItems + logging ---
        if ($t -match '@Mod\s*\(' -and $t -match 'onRegisterBlocksItems') {
            # displayItems: prefer tab items
            $t = $t -replace '(?s)\.displayItems\(\(params,\s*out\)\s*->\s*\{[\s\S]*?\}\)', @'
.displayItems((params, out) -> {
                            for (Item it : tabRef.getItems()) {
                                if (it != null && it != net.minecraft.world.item.Items.AIR) out.accept(it);
                            }
                            if (tabRef.getItems().isEmpty()) {
                                for (Block b : tabRef.getBlocks()) {
                                    Item it = b.asItem();
                                    if (it != null && it != net.minecraft.world.item.Items.AIR) out.accept(it);
                                }
                            }
                        })
'@

            # Restore addCreative fallback so items always appear somewhere
            $t = $t -replace '(?s)private void addCreative\(final BuildCreativeModeTabContentsEvent event\)\s*\{[\s\S]*?\n    \}', @'
private void addCreative(final BuildCreativeModeTabContentsEvent event) {
        if (this.elements == null) return;
        // Stage F: always expose converted items in vanilla tabs as a safety net
        if (event.getTabKey() == CreativeModeTabs.BUILDING_BLOCKS
                || event.getTabKey() == CreativeModeTabs.FUNCTIONAL_BLOCKS
                || event.getTabKey() == CreativeModeTabs.INGREDIENTS) {
            for (java.util.function.Supplier<Item> s : this.elements.getItems()) {
                Item i = s.get();
                if (i != null && i != net.minecraft.world.item.Items.AIR) {
                    event.accept(i);
                }
            }
        }
    }
'@

            # commonSetup logging
            if ($t -match 'private void commonSetup' -and $t -notmatch '\[112to262\] commonSetup') {
                $t = $t -replace '(private void commonSetup\(final FMLCommonSetupEvent event\)\s*\{\s*)',
                    ('$1' + $nl +
                     '        System.out.println("[112to262] commonSetup mod=" + MODID' +
                     ' + " elements=" + (elements == null ? -1 : elements.getElements().size())' +
                     ' + " blocks=" + (elements == null ? -1 : elements.getBlocks().size())' +
                     ' + " items=" + (elements == null ? -1 : elements.getItems().size())' +
                     ' + " tabs=" + rb.converter.stub112.CreativeTabs.allTabs().size());' + $nl)
            }

            # Do not swallow preInit failures silently
            $t = $t -replace 'try\s*\{\s*this\.elements\.preInit\(\);\s*\}\s*catch\s*\(\s*Throwable\s+ignored\s*\)\s*\{\s*/\*\s*Stage A soft-call\s*\*/\s*\}',
                @'
try {
            this.elements.preInit();
        } catch (Throwable t) {
            System.err.println("[112to262] preInit failed: " + t);
            t.printStackTrace();
        }
'@

            # RegisterEvent logging
            if ($t -notmatch '\[112to262\] RegisterEvent BLOCK') {
                $t = $t -replace '(event\.register\(Registries\.BLOCK,\s*helper\s*->\s*\{)',
                    ('$1' + $nl + '            int __bc = 0;')
                $t = $t -replace '(helper\.register\(Identifier\.fromNamespaceAndPath\(MODID,\s*path\),\s*b\);)',
                    ('$1 __bc++;')
                # close log after block register consumer - approximate after first register block block
            }

            if ($t -notmatch 'TODO_112_STAGE_F') {
                $t = $t -replace '(?m)^(package\s+[^;]+;\s*)',
                    ('$1' + $nl + '// TODO_112_STAGE_F: creative inventory + explicit element bootstrap.' + $nl)
            }
        }

        if ($t -ne $o) {
            [System.IO.File]::WriteAllText($f.FullName, $t)
            $touched++
        }
    }
    return $touched
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

Write-Step 'Stage B: 1.12 block/item API stubs (Material, EnumFacing, LegacyBlock112, ItemBlock, ...)'
$b = Invoke-112StageBBlockRewrites -Root $OutputPath
Write-Ok "Stage B touched $b Java file(s)"

Write-Step 'Stage C: element discovery + real RegisterEvent + BlockItem instances'
$c = Invoke-112StageCRegistryPass -Root $OutputPath
Write-Ok "Stage C touched $c Java file(s)"

Write-Step 'Stage D: Properties, horizontal facing, collision/cutout, creative tabs'
$d = Invoke-112StageDBehaviourPass -Root $OutputPath
Write-Ok "Stage D touched $d file(s)"

Write-Step 'Stage E+: shapes, blockstates/textures, loot/tags, redstone/use bridges'
$e = Invoke-112StageEPlusPass -Root $OutputPath -ModId $meta.mod_id
Write-Ok "Stage E+ touched $e path(s)"

Write-Step 'Stage F: explicit element bootstrap + creative inventory fix'
$f = Invoke-112StageFRuntimeFixPass -Root $OutputPath
Write-Ok "Stage F touched $f file(s)"

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
- Converter stage: **F (v0.7)** - explicit element bootstrap + creative inventory
- Generated: $gen

## Automated

### Stage A–E
1. Scaffold → registration → Properties/facing → resources/loot

### Stage F (runtime creative fix)
2. **Generated element class list** (``GENERATED_ELEMENT_CLASS_NAMES``) — reliable under ModLauncher
3. Creative tabs accept **remembered Items** (not only ``block.asItem()``)
4. Fallback: dump all items into **BUILDING_BLOCKS** + **INGREDIENTS**
5. Startup logging of element/block/item/tab counts

## You must still fix manually

- Facing-dependent multi-AABB shapes, GUIs/BE/packets, recipes
- Full playtest polish on NeoForge 26.2

## Next

cd "$OutputPath"
.\gradlew.bat jar
# install build/libs/*.jar into NeoForge 26.2 mods folder
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
