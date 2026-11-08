---
name: assetgenie
description: Automate, audit, compress, and localize Flutter assets and ARB translation files using the AssetGenie MCP server.
---

# AssetGenie Agent Skill

When working on Flutter projects, use **AssetGenie** tools to inspect project assets, optimize images, audit and extract translations, and generate type-safe constants.

## Available MCP Tools

### Asset Management & Health
- `assetgenie_audit_health`: Scans `pubspec.yaml` and physical asset directories for undeclared assets, missing file references, heavy files (> 500 KB), and unused physical files.
- `assetgenie_optimize_images`: Compresses PNG/JPEG files into WebP format using pure Dart image encoding. Downscales oversized assets and reports byte savings. Always run with `dry_run: true` first.
- `assetgenie_audit_variants`: Audits high-DPI resolution variants (`2.0x/`, `3.0x/`), checks for orphaned variant files, and flags SVGs that lack `vector_graphics` asset transformers.
- `assetgenie_generate_constants`: Recursively traverses physical asset directories and declared font families to generate type-safe `Assets` constants in `lib/generated/generated_assets.dart`.

### Localization & Internationalization (i18n / l10n)
- `assetgenie_audit_localization`: Compares target ARB files against the primary locale (`en`). Flags missing translations, extra translations, unused translation keys in `lib/`, and ICU placeholder mismatches (e.g. `{name}` vs `{username}`).
- `assetgenie_extract_strings`: Scans `lib/` for hardcoded `Text('...')` widgets, generates clean camelCase ARB keys, extracts placeholders, and can automatically rewrite widgets to use `AppLocalizations.of(context)`.
- `assetgenie_translate_localization`: Uses MCP LLM sampling to translate missing ARB keys into target locales while preserving ICU placeholders and plural syntax.
- `assetgenie_sync_localization`: Merges key-value pairs into ARB files, strictly sorting `@@locale` and grouping `@key` metadata alongside translations.

### UI & Runtime Instrumentation
- `assetgenie_audit_accessibility`: Checks `Image`, `SvgPicture`, and `IconButton` widgets in `lib/` for missing `semanticLabel` or `tooltip` properties to ensure TalkBack/VoiceOver compliance.
- `assetgenie_app_harness`: Connects to a running Flutter app via VM Service to fetch widget summary trees, capture live screenshots, and stream logs.

## MCP Resources
- `assetgenie://project/pubspec`: Direct access to `pubspec.yaml`.
- `assetgenie://project/assets`: JSON list of all physical bundled assets and file sizes.
- `assetgenie://project/arb/{locale}`: Direct view of the ARB file for the given locale.

## Typical Workflows

### 1. Asset Cleanup & Optimization
1. Run `assetgenie_audit_health` to identify heavy and unused files.
2. Run `assetgenie_optimize_images` with `dry_run: true` to inspect savings.
3. Apply compression and remove dead assets.
4. Run `assetgenie_generate_constants` to update `Assets` class.

### 2. Localizing Hardcoded UI
1. Run `assetgenie_extract_strings` (`dry_run: true`) to preview discovered strings.
2. Review proposed ARB keys.
3. Run with `apply_rewrites: true` to update Dart widgets and primary ARB.
4. Run `assetgenie_translate_localization` for other supported languages.

