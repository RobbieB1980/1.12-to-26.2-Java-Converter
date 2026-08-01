# Changelog

## 0.2.0 — 2026-08-01

### Stage A — FML lifecycle / proxies / entrypoint

- **Stub package** `rb.converter.stub112` (FML*Event, GameRegistry, IGuiHandler, ModelRegistryEvent, simpleimpl network, RegistryEvent, etc.)
- **IProxy / ClientProxy / ServerProxy / CommonProxy** rewritten to empty no-arg stubs
- **@Mod** modernized to string-literal mod id + **IEventBus** constructor + `FMLCommonSetupEvent` hook; FML `@EventHandler` pre/init/post/serverLoad removed
- **Rename fixes:** `EntityPlayerMP` → `ServerPlayer` (`server.level`); `Potion` → `MobEffect`; SideOnly → OnlyIn(Dist); `MinecraftForge.EVENT_BUS` → `NeoForge.EVENT_BUS`
- Remove broken `implements Object` leftovers from IFuelHandler/IWorldGenerator flags
- Gradle compile diagnostics: `-Xmaxerrs 10000` so full 1.12 error volume is visible

### Hospital proof (MCreator 1.12.2 jar)

| Metric (compileJava, maxerrs 10000) | v0.1.0 out (`-26.2-2`) | v0.2.0 out (`-26.2-3`) |
|-------------------------------------|------------------------|------------------------|
| Unique `file:line:msg` errors       | **5472**               | **4009** (−26.6%)      |
| Lifecycle files (mod/proxy/Elements)| **137**                | **0**                  |
| Files with errors                   | 147                    | 142                    |

Remaining errors are mostly 1.12 block APIs (Material, properties, ItemBlock, SRG `func_*`, etc.) — Stage B territory.

## 0.1.0 — 2026-08-01

### Initial experimental release

- Dedicated **Forge 1.12.2** → **NeoForge 26.2** converter product (separate from Legacy 1.20.1/1.21 path)
- **Jar pipeline:** Vineflower decompile + `mcmod.info` metadata detection
- **Scaffold:** ModDevGradle 26.2 / Java 25 workspace templates
- **1.12 rewrite pass (mechanical):**
  - Classic package moves (`item`/`block`/`entity` → modern `world.*` / `core` packages)
  - `ResourceLocation` → `Identifier`
  - `World` → `Level` (import/type renames)
  - Stub/comment `FML*InitializationEvent` / proxy-style lifecycle leftovers
  - Flag removed APIs (`IFuelHandler`, `IWorldGenerator`, `GameRegistry`, etc.)
  - Avoid wrong `fml.common.event` → NeoForge renames that do not exist
- Windows GUI (Mode B jar; Mode A project folder)
- **Setup installer** (same pattern as Legacy converter): Install / Uninstall, desktop + Start Menu shortcuts, `Uninstall.cmd`, Apps & features registration, app icon
- Portable build + Setup via `scripts\Build-Release.ps1`
- Docs: pipeline limits and usage

### Proven intent

- Target sample: Hospital / MCreator 1.12.2 style jars (scaffold + diagnostics; full compile still manual)
