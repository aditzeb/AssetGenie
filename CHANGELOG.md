# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-11-08

### Added
- **10 Specialized MCP Tools**:
  - `assetgenie_optimize_images`: WebP conversion, proportional downsizing, and compression calculations using pure Dart `package:image`.
  - `assetgenie_extract_strings`: Automatic discovery of hardcoded `Text('...')` widgets, ARB extraction with ICU placeholder formatting, and optional source code rewrites with `AppLocalizations.of(context)`.
  - `assetgenie_audit_variants`: Verification of high-DPI resolution variants (`2.0x/`, `3.0x/`), detection of orphaned variants, and SVG vector graphics transformer recommendations.
  - `assetgenie_audit_accessibility`: Audit of `Image`, `SvgPicture`, and `IconButton` widgets for missing `semanticLabel` or `tooltip` properties.
  - `assetgenie_translate_localization`: Automatic translation of missing ARB keys using MCP LLM sampling while strictly locking ICU placeholders and plurals.
- **MCP Protocol Upgrades (`package:dart_mcp`)**:
  - Full tool annotations: `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`.
  - Typed `outputSchema` with machine-readable `structuredContent` on every tool.
  - Interactive user confirmation via `ElicitRequest.form` prior to file mutations.
  - LLM Sampling support via `CreateMessageRequest`.
- **MCP Resources**:
  - `assetgenie://project/pubspec`: Direct view of `pubspec.yaml`.
  - `assetgenie://project/assets`: Live JSON array of physical bundled assets and byte sizes.
  - `assetgenie://project/arb/{locale}`: Direct view of target ARB translation file.
- **MCP Prompts**:
  - `asset_cleanup`: Full asset audit, variant check, compression preview, and constant regeneration workflow.
  - `add_language`: Step-by-step workflow to introduce and translate a new locale.
  - `localize_ui`: UI string extraction and widget localization workflow.
- **Agent Skill**: Bundled `skills/assetgenie/SKILL.md` for Antigravity, Cursor, Claude Code, and Roo Code.
- **Self-contained automated test suite**: Portable tests covering all 10 tools.

### Changed
- Migrated core server to `package:dart_mcp: ^0.5.2` with `ToolsSupport`, `ResourcesSupport`, `PromptsSupport`, `LoggingSupport`, `RootsTrackingSupport`, and `ElicitationRequestSupport`.
- `generate_constants` now includes font family constants declared in `pubspec.yaml`.
- `audit_localization` now features ICU-aware placeholder extraction to prevent syntax collisions with plurals and selectors.

## [1.0.0] - 2026-06-30

### Added
- Initial release of AssetGenie MCP server.
- `assetgenie_audit_health`: Scans for missing asset references, heavy assets, and unused files.
- `assetgenie_sync_localization`: Merges key-value translation pairs into ARB files with alphabetical sorting.
- `assetgenie_generate_constants`: Generates modern `Assets` constants class.
- `assetgenie_audit_localization`: Audits missing keys, extra keys, and placeholders between locales.
- `assetgenie_app_harness`: Connects to running Flutter apps via VM Service for widget tree, screenshots, and logs.
