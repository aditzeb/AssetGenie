# AssetGenie 🧞‍♂️

A complete, local Model Context Protocol (MCP) server written in pure Dart to automate, audit, and optimize Flutter project assets and localization structure. Connect it to AI clients like Cursor or Claude Desktop to let the AI interact directly with your project's assets and translation structures.

---

<img width="302" height="994" alt="AssetGenie in Action" src="https://github.com/user-attachments/assets/0858bc99-c10b-43a0-a8d4-05b9be17d558" />


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

### 4. `assetgenie_audit_localization`
Audits the project's ARB localization files to ensure quality and consistency:
- Compares target locales against a primary locale to find missing translation keys.
- Detects extra translation keys defined in target locales but missing in the primary locale.
- Validates that parameterized placeholders (e.g., `{name}`) match between translations to prevent runtime formatting crashes.
- Scans Dart code recursively in `lib/` to identify unused translation keys.

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

## 🔌 Connecting to LLMs & IDEs (MCP Clients)

To use AssetGenie inside your favorite AI assistant or development environment, configure it as a local stdio MCP server.

### 1. Antigravity IDE
Antigravity automatically discovers MCP servers configured in its global MCP configuration file:
- **Windows**: `C:\Users\<Your-Username>\.gemini\antigravity-ide\mcp_config.json`
- **macOS / Linux**: `~/.gemini/antigravity-ide/mcp_config.json`

Add the following under the `"mcpServers"` object:

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

### 2. JetBrains IntelliJ IDEA / Android Studio
To bring AssetGenie's capabilities into IntelliJ IDEA or Android Studio, you can use the **Continue** plugin or the **Cline / Roo Cline** plugins.

#### Option A: Using Continue (via config.yaml)
Add the following to your global Continue configuration (`~/.continue/config.yaml` or `C:\Users\<Your-Username>\.continue\config.yaml`) under the `mcpServers` block:

```yaml
mcpServers:
  - name: assetgenie
    type: stdio
    command: dart
    args:
      - "run"
      - "C:\\path\\to\\AssetGenie\\bin\\main.dart"
```
> [!NOTE]
> Make sure to switch Continue to **Agent Mode** in your chat panel to enable tool execution.

#### Option B: Using Cline / Roo Cline
Add the following to your settings file (`roo_cline_mcp_settings.json`):

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

### 3. VS Code
You can use the **Continue**, **Cline**, or **Roo Cline** extensions in VS Code by applying the same configurations as JetBrains IDEs.
- Cline settings are stored in `C:\Users\<Your-Username>\AppData\Roaming\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json` (Windows) or `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` (macOS).

### 4. Claude Desktop
Add the following to your `claude_desktop_config.json` configuration file:
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

### 5. Cursor / Windsurf
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

### 4. `assetgenie_audit_localization`
- `project_path` (string, required): Absolute path to the Flutter root directory.
- `primary_locale` (string, optional): The base locale to compare other locales against (default: `'en'`).
- `unused_keys_check` (boolean, optional): Whether to check for unused keys in `lib/**/*.dart` (default: `true`).

---

## 📄 License

This project is open-source and licensed under the MIT License. See [LICENSE](LICENSE) for more details.
