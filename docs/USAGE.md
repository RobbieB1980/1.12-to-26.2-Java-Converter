# Usage

## GUI

1. Run `RB-112-to-262-Java-Converter.exe` (or `Start-Converter.bat`).
2. Choose **Mode B** for a finished 1.12.2 `.jar`, or **Mode A** for a decompiled project folder with `src/`.
3. Pick empty **Output** folder.
4. Optionally enable **Scaffold NeoForge 26.2** (jar mode) and/or **Compile after convert**.
5. Click **Convert**. Original input is never modified.

## CLI examples

See root [README.md](../README.md).

## Interpreting results

| Output | Meaning |
|--------|---------|
| `DECOMPILE_REPORT.md` | Jar extract + Vineflower stats |
| `MIGRATION_112_REPORT.md` | What was rewritten and remaining 1.12 gaps |
| `gradlew compileJava` many errors | Expected on first pass for large 1.12 mods |
| `build/libs/*.jar` | Only after you fix compile and run `gradlew build` |

## Honest scope

This converter **starts** a port. It does not replace rewriting 1.12 FML lifecycle, registries, and client rendering for 26.2.
