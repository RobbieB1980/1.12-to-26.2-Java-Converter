# RB 1.12 → 26.2 Java Converter

**Current release: v0.4.0 (experimental — Stage C registration; Hospital compileJava green)**

Dedicated converter for **Minecraft Forge 1.12.2** finished `.jar` mods (and 1.12-style source trees) toward a **NeoForge 26.2** ModDevGradle scaffold.

This is **not** the same product as [LegacyJavaConverter](https://github.com/RobbieB1980/LegacyJavaConverter) (1.20.1 / 1.21.x → 26.2).  
1.12.2 is a different generation (packages, FML lifecycle, registries). Expect a **scaffold + mechanical rewrites**, not an automatic full port.

## What this tool does

1. **Decompile** finished jars (Vineflower) into `src/main/java` + resources  
2. Read **`mcmod.info`** (and best-effort package hints)  
3. Write a **NeoForge 26.2** Gradle scaffold (Java 25)  
4. Apply **1.12-era mechanical rewrites** (packages, ResourceLocation, stubs for removed APIs)  
5. Emit **`MIGRATION_112_REPORT.md`** listing remaining work  

## Stages included

**Stage A (v0.2):** IProxy stubs, FML→stub112, modern `@Mod` + IEventBus  

**Stage B (v0.3):** LegacyBlock112 + 1.12 type stubs (compile surface)  

**Stage C (v0.4):** ElementDiscovery + **RegisterEvent** blocks/items + real **BlockItem** + lang JSON  

Hospital proof: **compileJava SUCCESS**; blocks/items should register at runtime (behaviour still LegacyBlock112 shims).

## What it does **not** do (yet)

- Full block behaviour port (Properties, facing, voxel shapes, redstone)  
- Per-mod CreativeModeTab mapping (Stage C dumps into BUILDING_BLOCKS)  
- GUIs / TileEntities / networking modernization  
- Mixins without hand repair  

## Requirements

- Windows 10/11 (GUI)  
- PowerShell 5.1+  
- Java **17+** for Vineflower; **JDK 25** for compiling 26.2 projects  
- Internet on first Gradle resolve  

## Downloads (Windows)

From [GitHub Releases](https://github.com/RobbieB1980/1.12-to-26.2-Java-Converter/releases):

| Artifact | Description |
|----------|-------------|
| `RB-112-to-262-Java-Converter-Setup.exe` | GUI installer (Install + Uninstall; embeds portable package) |
| `RB-112-to-262-Java-Converter-Portable.zip` | Portable folder — unzip and run `Start-Converter.bat` |

Build locally:

```powershell
.\scripts\Build-Release.ps1
```

Outputs land in `dist\` (portable folder, portable ZIP, Setup EXE).

### Install / uninstall

- Default install: `%LOCALAPPDATA%\RB-112-to-262-Java-Converter` (no admin)
- Uninstall: Setup **Uninstall** button, Start Menu entry, `Uninstall.cmd`, or Windows **Apps & features**

## GUI

**Mode B — Finished `.jar`:** decompile → optional 26.2 scaffold  
**Mode A — Project folder:** decompiled/source tree with `src/`  

Or: `.\Launch-GUI.bat` for debug runs without packaging.

## CLI

```powershell
# Full pipeline: jar → decompiled intermediate → 26.2 scaffold
.\Convert-OldJar112ToNeoForge262.ps1 `
  -JarPath "D:\mods\Hospital-1.12.2.jar" `
  -OutputPath "D:\mods\Hospital-26.2"

# Decompile only
.\Convert-JarToProject112.ps1 `
  -JarPath "D:\mods\Hospital-1.12.2.jar" `
  -OutputPath "D:\mods\Hospital-decompiled"

# Project folder already decompiled
.\Convert-112ToNeoForge262.ps1 `
  -Path "D:\mods\Hospital-decompiled" `
  -OutputPath "D:\mods\Hospital-26.2"
```

## After conversion

```powershell
cd "D:\mods\Hospital-26.2"
.\gradlew.bat compileJava --stacktrace
```

Read `MIGRATION_112_REPORT.md` in the output. Install **only** jars from `build\libs` after a clean build — never the original 1.12.2 jar.

## Related

- [LegacyJavaConverter](https://github.com/RobbieB1980/LegacyJavaConverter) — Forge 1.20.1 / NeoForge 1.21.x → 26.2  

## License

MIT — see [LICENSE](LICENSE).

## Disclaimer

Experimental migration assistant. Keep originals. Large 1.12 mods will need substantial manual work after the scaffold.
