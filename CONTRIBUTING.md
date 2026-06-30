# Contributing to AssetGenie 🧞‍♂️

Thank you for your interest in contributing to AssetGenie! This project aims to make Flutter asset and localization management easier by connecting local development projects directly to LLMs through the Model Context Protocol.

Contributions from the community help make this utility more robust, feature-rich, and reliable.

---

## 🗺️ Codebase & Project Architecture

AssetGenie is designed to be a lightweight, modular package:
- `bin/main.dart`: Standard entry point initializing the JSON-RPC server and registering tools.
- `lib/src/tools/`: Each tool has its own dedicated Dart file (e.g. `audit_health.dart`, `sync_localization.dart`, `generate_constants.dart`) to keep code modular and readable.
- `lib/src/compatibility.dart`: Ensures full compilation compatibility with both pure Dart CLI VM and Flutter SDK environments.
- `test/`: Contains diagnostic verification suites to test the tools.

---

## 🛠️ Development Workflow

To set up your local development environment:

1. **Fork and Clone** the repository.
2. **Download dependencies**:
   ```bash
   dart pub get
   ```
3. **Format & Analyze**: Ensure all your modifications follow the Dart styling guidelines and don't introduce compiler errors:
   ```bash
   dart format .
   dart analyze
   ```
4. **Run Verification Suite**: Make sure all verifications pass before committing:
   ```bash
   dart test test/assetgenie_test.dart
   ```

---

## ➕ Adding a New MCP Tool

If you want to contribute a new tool:
1. Create a separate Dart file under `lib/src/tools/` (e.g. `lib/src/tools/my_tool.dart`).
2. Implement your tool logic. Ensure all file operations are wrapped inside a `try-catch` block, returning a clean `CallToolResult` with `isError: true` rather than crashing the process.
3. Export your tool in `lib/assetgenie.dart`.
4. Define the input schema and register the tool in `bin/main.dart`.
5. Add test coverage/verification to `test/assetgenie_test.dart`.

---

## 📥 Pull Request Guidelines

When submitting a pull request:
- Make sure your PR resolves or references an open issue.
- Verify that `dart analyze` reports **no warnings/errors**.
- Verify that `dart format` is run on all files.
- Keep commits descriptive and atomic.
- Provide a summary of what changed and how you tested the changes in the PR description.
