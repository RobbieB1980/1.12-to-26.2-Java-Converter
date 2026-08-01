# Changelog

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
