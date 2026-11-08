# AssetGenie 🧞‍♂️

A complete, production-grade Model Context Protocol (MCP) server written in pure Dart to automate, audit, compress, and optimize Flutter project assets and localization structures. Connect it to AI clients like Antigravity, Cursor, Windsurf, Claude Desktop, or Continue to give your AI assistant direct, native tools and context to manage your Flutter app's assets and translations.

---

<img width="302" height="994" alt="AssetGenie in Action" src="https://github.com/user-attachments/assets/0858bc99-c10b-43a0-a8d4-05b9be17d558" />

## 🌟 What's New in v1.1.0

- 🛠️ **10 Specialized MCP Tools**: Expanded from 5 to 10 tools, covering image compression, hardcoded UI string extraction, variant checks, accessibility audits, and automated translations.
- ⚡ **Tool Annotations & Structured Output**: All tools provide `readOnlyHint`, `destructiveHint`, `idempotentHint`, and typed `outputSchema` with machine-readable `structuredContent` for reliable AI agent chaining.
- 📦 **MCP Resources**: Exposes `assetgenie://project/pubspec`, `assetgenie://project/assets`, and `assetgenie://project/arb/{locale}` for instant, zero-tool-call inspection.
- 💬 **MCP Prompts**: Ready-made agent workflows for `/asset_cleanup`, `/add_language`, and `/localize_ui`.
- 🤝 **Elicitation & Sampling**: Interactive user confirmation before destructive disk edits and client-driven LLM translations that strictly preserve ICU placeholders and plurals.
- 🛡️ **`dry_run` Mode**: Preview compression savings, code rewrites, and ARB updates safely before writing to disk.
- 🤖 **Agent Skill Included**: Bundled `skills/assetgenie/SKILL.md` for zero-configuration adoption across agentic IDEs.

---

## 🚀 Features & Tools

### Asset Auditing & Optimization

#### 1. `assetgenie_audit_health`
Scans `pubspec.yaml` and physical folders to identify asset anomalies:
- Flags missing physical files declared in `pubspec.yaml`.
- Flags physical assets in `assets/` not declared in `pubspec.yaml` (undeclared assets).
- Identifies heavy assets exceeding a configurable threshold (default: 500 KB).
- Automatically scans `lib/` Dart source code to find unused assets.

#### 2. `assetgenie_optimize_images`
Converts and compresses raster images with pure Dart image processing:
- Converts PNG and JPEG files to modern **WebP** format.
- Proportionally downscales oversized images exceeding `max_width` or `max_height`.
- Calculates exact byte savings and percentage saved.
- Supports `dry_run` to preview savings without touching files on disk.

#### 3. `assetgenie_audit_variants`
Ensures crisp rendering on modern high-DPI screens and smooth graphics:
- Verifies that base images have corresponding `2.0x/` and `3.0x/` resolution variants.
- Flags orphaned variant files whose base asset was deleted.
- Recommends Flutter asset transformers (`vector_graphics_compiler`) for SVGs to eliminate runtime SVG parsing jank.

#### 4. `assetgenie_generate_constants`
Auto-generates clean, type-safe Dart constants from physical asset files:
- Recursively walks asset directories and reads declared font families.
- Converts file paths into structured `camelCase` identifiers.
- Dynamically resolves naming collisions and Dart reserved keywords.
- Generates `Assets` class inside `lib/generated/generated_assets.dart`.

### Localization & Internationalization (i18n / l10n)

#### 5. `assetgenie_audit_localization`
Audits ARB (`.arb`) files against a primary locale (`en`):
- Detects missing translation keys in target locales.
- Flags extra keys defined in target locales but missing in the primary locale.
- **ICU Placeholder Validation**: Ensures parameterized variables (e.g., `{name}`, `{count}`) match between translations to prevent runtime formatting crashes.
- Identifies unused translation keys across `lib/` Dart code.

#### 6. `assetgenie_extract_strings`
Automates extracting hardcoded UI strings into ARB:
- Scans `lib/` for hardcoded `Text('...')` widgets and string literals.
- Generates clean camelCase ARB keys and parameterized placeholders from string interpolations (`$name` -> `{name}`).
- Injects keys into the primary ARB file.
- Optionally rewrites widget code to use `AppLocalizations.of(context)` with required imports.

#### 7. `assetgenie_translate_localization`
Translates missing keys using MCP client LLM sampling:
- Discovers missing keys in target locales.
- Asks the connected AI model to translate strings into target languages.
- Strictly protects ICU placeholders and plural format structures.
- Appends new translations cleanly into target `.arb` files.

#### 8. `assetgenie_sync_localization`
Safely injects or updates translation keys into local `.arb` files:
- Standardizes formatting and groups metadata keys (`@key`) next to their messages.
- Alphabetizes keys according to standard ARB guidelines with `@@locale` at top.
- Supports `dry_run` preview.

### Accessibility & App Instrumentation

#### 9. `assetgenie_audit_accessibility`
Audits visual and interactive widgets for screen reader compliance:
- Scans `Image`, `SvgPicture`, and `IconButton` widgets in `lib/`.
- Flags missing `semanticLabel` or `tooltip` properties to ensure TalkBack / VoiceOver readiness.

#### 10. `assetgenie_app_harness`
Connects to a running Flutter application via its Dart VM Service:
- Retrieves a structured JSON Widget Summary Tree from the active app.
- Captures live UI screenshots as PNG images directly in tool responses.
- Streams stdout/stderr prints and runtime logging statements over WebSocket.

---

## 📦 MCP Resources & Prompts

### Resources
| URI | Description |
|---|---|
| `assetgenie://project/pubspec` | Direct view of the active Flutter project's `pubspec.yaml` |
| `assetgenie://project/assets` | JSON list of all physical bundled assets and file sizes |
| `assetgenie://project/arb/{locale}` | Direct view of the ARB file for the given locale |

### Prompts
| Prompt Name | Purpose |
|---|---|
| `asset_cleanup` | Complete asset audit, WebP optimization, and constant regeneration workflow |
| `add_language` | Step-by-step workflow to add and translate a new locale |
| `localize_ui` | Hardcoded string discovery, ARB extraction, and widget rewriting |

---

## 🛠️ Installation & Setup

Ensure you have the [Dart SDK](https://dart.dev/get-dart) installed.

1. Clone the repository:
   ```bash
   git clone https://github.com/aditzeb/AssetGenie.git
   cd AssetGenie
   ```

2. Download package dependencies:
   ```bash
   dart pub get
   ```

3. Run the automated test suite:
   ```bash
   dart test
   ```

---

## 🔌 Connecting to LLMs & IDEs (MCP Clients)

Configure AssetGenie as a local stdio MCP server in your development environment.

### 1. Antigravity IDE
Add the following to your global MCP configuration:
- **Windows**: `C:\Users\<Your-Username>\.gemini\antigravity-ide\mcp_config.json`
- **macOS / Linux**: `~/.gemini/antigravity-ide/mcp_config.json`

```json
{
  "mcpServers": {
    "assetgenie": {
      "command": "dart",
      "args": [
        "run",
        "C:\\path\\to\\AssetGenie\\bin\\main.dart"
      ]
    }
  }
}
```

### 2. Cursor / Windsurf
In **Settings** -> **Features** -> **MCP**, click **Add New MCP Server**:
- **Name**: `AssetGenie`
- **Type**: `stdio`
- **Command**: `dart run C:\path\to\AssetGenie\bin\main.dart`

### 3. Claude Desktop
Add to your `claude_desktop_config.json`:
- **Windows**: `C:\Users\<Your-Username>\AppData\Roaming\Claude\claude_desktop_config.json`
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "assetgenie": {
      "command": "dart",
      "args": [
        "run",
        "C:\\path\\to\\AssetGenie\\bin\\main.dart"
      ]
    }
  }
}
```

### 4. JetBrains / Android Studio / VS Code (Continue & Cline / Roo Code)
Add to your `config.yaml` or `roo_cline_mcp_settings.json`:

```yaml
mcpServers:
  - name: assetgenie
    type: stdio
    command: dart
    args:
      - "run"
      - "C:\\path\\to\\AssetGenie\\bin\\main.dart"
```

---

## 📄 License

This project is open-source and licensed under the MIT License. See [LICENSE](LICENSE) for more details.
