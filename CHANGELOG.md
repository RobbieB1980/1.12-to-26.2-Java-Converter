# Changelog

## 0.8.0 — 2026-08-01

### Stage G — DeferredRegister + master creative tab (still-empty creative)

If v0.7 still showed no items, Stage G hardens registration further:

- **DeferredRegister** for blocks/items/tabs (queue entries, then `register(bus)`)
- Per-element **try/catch** bootstrap (`Class.forName` + `initElements`) so one failure cannot wipe all
- Guaranteed creative tab **`the_hospital_mod:all`** titled **"Hospital / Converted Items"**
- Vanilla tab fallbacks (Building / Functional / Ingredients / Tools)
- SLF4J logs: `DeferredRegister queued blocks=N items=N`

### Install

Use jar from reconvert output `-26.2-9` (not older builds).

## 0.7.0 — 2026-08-01

### Stage F — runtime creative inventory fix

**Problem:** Mod loaded but **no creative tabs/items** — classpath `ElementDiscovery` returns empty under NeoForge/ModLauncher, so no blocks/items registered.

**Fix:**
- Generate **`GENERATED_ELEMENT_CLASS_NAMES`** at convert time (explicit `Class.forName` list)
- Creative tabs use **remembered Item instances** (not only `block.asItem()`)
- Fallback dump of all items into **BUILDING_BLOCKS / FUNCTIONAL_BLOCKS / INGREDIENTS**
- Startup logs: `[112to262] elements=… blocks=… items=… tabs=…`

### Hospital proof

- 141 ModElement classes in generated bootstrap list
- `compileJava` + `jar` **SUCCESS**
- Expect items in vanilla Building Blocks tab after reinstall of new jar

## 0.6.0 — 2026-08-01

### Stage E+ — shapes, resources, loot/tags, interaction bridges

- **Voxel shapes** from 1.12 `AxisAlignedBB` via `setLegacyShape` (0..1 → `Shapes.box`)
- **Blockstates**: `normal`→`""`, model paths `mod:block/name`, drop empty variant when `facing=` present
- **Textures**: `textures/blocks` → `textures/block`; refs `:blocks/` → `:block/`; `block/cube` → `minecraft:block/cube`
- **Loot**: self-drop `data/<mod>/loot_table/blocks/*.json` for all blocks
- **Tags**: `minecraft:mineable/pickaxe` listing converted blocks
- **Redstone**: `func_180656_a` / `func_176211_b` → `getSignal` / `getDirectSignal`
- **Use / neighbor**: reflection bridges on `LegacyBlock112` to legacy `func_180639_a` / `func_189540_a`

### Hospital proof

| | Stage D | Stage E+ |
|--|---------|----------|
| `compileJava` / `jar` | SUCCESS | **SUCCESS** |
| `setLegacyShape` | — | **41** |
| Loot tables | 0 | **131** |
| Texture folder | `blocks/` | **`block/`** |
| Blockstate model paths | 1.12-style | **`mod:block/*`** |

Still open: facing-dependent multi-AABB, GUIs/menus, block entities, full packets, playtest polish.

## 0.5.0 — 2026-08-01

### Stage D — block behaviour + creative tabs

- **LegacyProps.of**: Material + SoundType + hardness/resistance/light/opacity → `BlockBehaviour.Properties`
- **LegacyHorizontalBlock112**: real `HORIZONTAL_FACING` for ~80 MCreator horizontal blocks
- Empty collision + cutout flags; inject `render_type: minecraft:cutout_mipped` into matching models
- **CreativeModeTab** registration from `CreativeTabs` + `func_149647_a` block assignment
- Soft-disable leftover 1.12 facing state helpers that conflicted with modern properties

### Hospital proof

| | Stage C | Stage D |
|--|---------|---------|
| `compileJava` | SUCCESS | **SUCCESS** |
| Properties fold | no | **131× LegacyProps.of** |
| Horizontal facing | stub only | **80× LegacyHorizontalBlock112** |
| Cutout models | — | **166 JSON** |
| Creative tabs | BUILDING_BLOCKS dump | **registered CreativeModeTab(s)** |

Still open: precise voxel shapes, multi-property states, GUIs/TE/packets, recipes.

## 0.4.0 — 2026-08-01

### Stage C — real registration path (MCreator-oriented)

- **ElementDiscovery**: classpath scan for `@ModElement.Tag` (replaces empty ASMDataTable)
- **initElements**: single-instance `BlockCustom` + real `BlockItem` (no null ObjectHolder)
- **RegisterEvent** on mod bus registers blocks/items using paths from `setRegistryName`
- Creative dump into `CreativeModeTabs.BUILDING_BLOCKS`
- `en_us.lang` → `en_us.json` (legacy `.lang` kept as `.112-reference`)

### Hospital proof

| | Stage B (v0.3) | Stage C (v0.4) |
|--|----------------|----------------|
| `compileJava` | SUCCESS | **SUCCESS** |
| Element discovery | empty ASM stub | **classpath scan** |
| BlockItem | stub ItemBlock / null block | **real BlockItem + RegisterEvent** |
| Lang | `en_us.lang` only | **`en_us.json`** |

Still shimmed: LegacyBlock112 behaviour, facing/collision, per-tab CreativeModeTab, GUIs/packets.

## 0.3.0 — 2026-08-01

### Stage B — 1.12 block / item compile surface

- **LegacyBlock112** base for MCreator `extends Block` + common `func_*` / `setRegistryName`
- **LegacyBlockState**, Material, EnumFacing, AxisAlignedBB, IBlockAccess, properties, ItemBlock, CreativeTabs stubs
- SoundType SRG fields → modern constants; BlockPos SRG → `getX/Y/Z`
- `Item.func_150898_a` → LegacyItems; Level/World procedure SRG helpers (`LegacyLevel`)
- Leftover `world` body refs after World→Level rename; client scheduled-task stubs

### Hospital proof (MCreator 1.12.2 jar)

| Metric (compileJava, maxerrs 10000) | v0.1.0 | v0.2.0 Stage A | v0.3.0 Stage B |
|-------------------------------------|--------|----------------|----------------|
| Unique `file:line:msg` errors       | 5472   | 4009           | **0**          |
| Lifecycle errors                    | 137    | 0              | **0**          |
| `compileJava`                       | fail   | fail           | **SUCCESS**    |

**Note:** compile success uses **stub112 no-ops** — not a runtime-ready NeoForge port. DeferredRegister, real BlockBehaviour.Properties, BlockItem, CreativeModeTab, models, and networking still need Stage C+ hand port.

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
