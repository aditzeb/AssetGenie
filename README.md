# AssetGenie 🧞‍♂️

A complete, local Model Context Protocol (MCP) server written in pure Dart to automate, audit, and optimize Flutter project assets and localization structure. Connect it to AI clients like Cursor or Claude Desktop to let the AI interact directly with your project's assets and translation structures.

---

## 🚀 Features

AssetGenie exposes three powerful tools to the LLM context:

### 1. `assetgenie_audit_health`
Scans the project's `pubspec.yaml` and physical folders to identify asset anomalies:
- Flags missing physical files declared in `pubspec.yaml`.
- Flags physical assets that are not declared in `pubspec.yaml` (undeclared assets).
- Identifies heavy assets exceeding a configurable file size threshold (default: 500 KB).
- Automatically checks for unused physical files by searching for references in `lib/` source code.

### 2. `assetgenie_sync_localization`
Safely updates or injects translation keys into local Application Resource Bundle (`.arb`) files:
- Appends new translations without manual copying/pasting.
- Standardizes formatting and groups metadata keys (`@key`) next to their respective properties.
- Alphabetizes keys according to standard ARB guidelines.

### 3. `assetgenie_generate_constants`
Auto-generates clean, modern Dart constants from physical asset files:
- Recursively walks through the physical assets folders.
- Converts file paths into structured `camelCase` variable names.
- Resolves identifier collisions and reserved keywords dynamically.
- Writes a safe config class `Assets` inside `lib/generated/` to prevent typos and hardcoded string values.

---

## 🛠️ Installation & Setup

Ensure you have [Dart SDK](https://dart.dev/get-dart) installed on your system.

1. Clone the repository:
   ```bash
   git clone https://github.com/aditzeb/AssetGenie.git
   cd AssetGenie
   ```

2. Download package dependencies:
   ```bash
   dart pub get
   ```

3. Run the verification/tests to make sure everything is ready:
   ```bash
   dart test test/assetgenie_test.dart
   ```

---

## 🔌 Connecting to LLMs (MCP Clients)

To use AssetGenie inside your favorite AI environment, configure it as a local stdio MCP server.

### 1. Claude Desktop
Add the following to your `claude_desktop_config.json` configuration:

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
Go to **Settings** -> **Features** -> **MCP**, click **Add New MCP Server**:
- **Name**: `AssetGenie`
- **Type**: `stdio`
- **Command**: `dart run C:\path\to\AssetGenie\bin\main.dart`

---

## 📖 Tool Schema Details

### 1. `assetgenie_audit_health`
- `project_path` (string, required): Absolute path to the Flutter root directory.
- `max_size_kb` (number, optional): Size threshold in KB (default: 500).

### 2. `assetgenie_sync_localization`
- `project_path` (string, required): Absolute path to the Flutter root directory.
- `locale` (string, required): Target language code (e.g. `'en'`, `'de'`).
- `kv_pairs` (object, required): A JSON map of translation pairs (e.g., `{"loginButton": "Sign In"}`).

### 3. `assetgenie_generate_constants`
- `project_path` (string, required): Absolute path to the Flutter root directory.
- `output_filename` (string, optional): Target file name (default: `'generated_assets.dart'`).

---

## 📄 License

This project is open-source and licensed under the MIT License. See [LICENSE](LICENSE) for more details.