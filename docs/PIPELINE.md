# Pipeline (1.12.2 → NeoForge 26.2)

```
[1.12.2 .jar]
    │ Vineflower decompile + resources
    ▼
[decompiled src/ + mcmod.info]
    │ package renames, lifecycle stubs, 26.2 scaffold
    ▼
[NeoForge 26.2 ModDevGradle project]
    │ manual fixes + gradlew build
    ▼
[build/libs/*-mc26.2-neoforge.jar]
```

## Stages

### 1. Decompile (`Convert-JarToProject112.ps1`)

- Unzip jar, Vineflower classes → `src/main/java`
- Copy `assets`, `data`, `META-INF`, `mcmod.info`
- Parse **mcmod.info** for modid / name / mcversion
- Write `DECOMPILE_REPORT.md`

### 2. Scaffold + rewrites (`Convert-112ToNeoForge262.ps1`)

- Copy tree (exclude `build/`, `.gradle/`)
- Write `build.gradle`, `settings.gradle`, `gradle.properties`, `neoforge.mods.toml` templates
- Mechanical **1.12 → modern** package renames (+ ServerPlayer / MobEffect fixes)
- **Stage A:** inject `rb.converter.stub112`, stub proxies, modern `@Mod` + IEventBus ctor
- **Stage B:** LegacyBlock112, Material/EnumFacing/ItemBlock/properties, Level SRG helpers
- **Stage C:** ElementDiscovery, single-instance BlockItem, real `RegisterEvent`, lang JSON
- **Stage D:** LegacyProps Properties, horizontal FACING, cutout render_type, CreativeModeTabs
- Map FML lifecycle / GameRegistry leftovers to stubs where still needed
- Write `MIGRATION_112_REPORT.md`

### 3. Full pipeline (`Convert-OldJar112ToNeoForge262.ps1`)

- Decompile beside output as `*-decompiled`
- Run stage 2 into your 26.2 folder

## Why separate from Legacy converter

| | Legacy (1.20.1 / 1.21) | This tool (1.12.2) |
|--|------------------------|---------------------|
| Packages | Already modern-ish | Pre-flatten (`item`/`block`) |
| Lifecycle | Near modern | Proxies + FML pre/init/post |
| Registries | DeferredRegister era | GameRegistry / ore dict era |
| Target rewrites | 26.2 API polish | First modernize, then 26.2 |
