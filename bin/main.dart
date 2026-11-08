import 'dart:io';

import 'package:assetgenie/assetgenie.dart';

void main(List<String> args) async {
  if (args.contains('--version') || args.contains('-v')) {
    stdout.writeln('AssetGenie v1.1.0');
    exit(0);
  }

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
AssetGenie - Model Context Protocol (MCP) Server for Flutter Projects

Usage:
  dart run bin/main.dart [options]

Options:
  -v, --version    Show AssetGenie version
  -h, --help       Show this help message

Tools Exposed (10):
  - assetgenie_audit_health         Audit asset references, sizes, and code usage
  - assetgenie_optimize_images      Compress PNG/JPEG to WebP & downscale
  - assetgenie_extract_strings      Extract hardcoded Text() widgets into ARB
  - assetgenie_audit_variants       Verify 2.0x/3.0x scales & vector_graphics
  - assetgenie_audit_accessibility  Check Image/IconButton semantic labels & tooltips
  - assetgenie_translate_localization Auto-translate ARB keys with LLM sampling
  - assetgenie_generate_constants   Generate type-safe Assets constants & fonts
  - assetgenie_audit_localization   Audit missing/extra ARB keys & ICU placeholders
  - assetgenie_sync_localization    Merge & alphabetize ARB translation keys
  - assetgenie_app_harness          Connect to VM Service for layout, shots & logs

Resources:
  - assetgenie://project/pubspec
  - assetgenie://project/assets
  - assetgenie://project/arb/{locale}

Prompts:
  - asset_cleanup, add_language, localize_ui
''');
    exit(0);
  }

  // Prevent any console noise on stdout that would corrupt JSON-RPC protocol.
  // All logging MUST go to stderr or through MCP sendLog.
  try {
    final server = AssetGenieServer.startStdio();
    stderr.writeln(
      'AssetGenie MCP Server v1.1.0 started successfully on stdio with 10 tools, resources, and prompts.',
    );
    await server.done;
  } catch (e, stack) {
    stderr.writeln('Failed to start AssetGenie MCP Server: $e\n$stack');
    exit(1);
  }
}
