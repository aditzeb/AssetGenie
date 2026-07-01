import 'dart:io';
import 'package:mcp_server/mcp_server.dart';
import 'package:assetgenie/assetgenie.dart';

/// Pure-Dart wrapper class matching the required FlutterMcpServer specification.
/// Exposes `createStdioTransport` and wraps core server actions.
class FlutterMcpServer {
  /// Creates a standard I/O (stdio) transport for communication.
  static StdioServerTransport createStdioTransport() {
    return McpServer.createStdioTransport();
  }
}

void main() async {
  // Prevent any console noise on stdout that would corrupt JSON-RPC protocol
  // All log messages should go to stderr or through MCP sendLog.
  final server = McpServer.createServer(
    name: 'AssetGenie',
    version: '1.0.0',
    capabilities: const ServerCapabilities(
      tools: true,
      toolsListChanged: true,
    ),
  );

  // Register assetgenie_audit_health tool
  server.addTool(
    name: 'assetgenie_audit_health',
    description:
        "Scans the target Flutter project's pubspec.yaml and physical assets directories "
        "to identify unused images, missing file references, or excessively large files.",
    inputSchema: {
      'type': 'object',
      'properties': {
        'project_path': {
          'type': 'string',
          'description': 'Absolute path to the Flutter project root directory.',
        },
        'max_size_kb': {
          'type': 'number',
          'description':
              'File size threshold in KB to flag heavy assets (default: 500).',
        },
      },
      'required': ['project_path'],
    },
    handler: auditHealth,
  );

  // Register assetgenie_sync_localization tool
  server.addTool(
    name: 'assetgenie_sync_localization',
    description:
        'Directly updates or injects missing translation keys into local Application '
        'Resource Bundle (.arb) files, sorted alphabetically.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'project_path': {
          'type': 'string',
          'description': 'Absolute path to the Flutter project root directory.',
        },
        'locale': {
          'type': 'string',
          'description': "Target language code (e.g., 'en', 'id', 'de').",
        },
        'kv_pairs': {
          'type': 'object',
          'description':
              'A JSON map of key-value translation strings to merge.',
        },
      },
      'required': ['project_path', 'locale', 'kv_pairs'],
    },
    handler: syncLocalization,
  );

  // Register assetgenie_generate_constants tool
  server.addTool(
    name: 'assetgenie_generate_constants',
    description:
        'Scans the physical assets directory and auto-generates a clean, modern '
        'Dart class containing string constants inside lib/generated/.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'project_path': {
          'type': 'string',
          'description': 'Absolute path to the Flutter project root directory.',
        },
        'output_filename': {
          'type': 'string',
          'description':
              "Target filename for the generated class (default: 'generated_assets.dart').",
        },
      },
      'required': ['project_path'],
    },
    handler: generateConstants,
  );

  // Register assetgenie_audit_localization tool
  server.addTool(
    name: 'assetgenie_audit_localization',
    description:
        "Scans the target Flutter project's ARB localization files to identify "
        "missing translations, extra keys, mismatched placeholders, or unused translation keys.",
    inputSchema: {
      'type': 'object',
      'properties': {
        'project_path': {
          'type': 'string',
          'description': 'Absolute path to the Flutter project root directory.',
        },
        'primary_locale': {
          'type': 'string',
          'description':
              "The base locale code to compare other locales against (default: 'en').",
        },
        'unused_keys_check': {
          'type': 'boolean',
          'description':
              "Whether to check if translation keys are unused in the Dart source code (default: true).",
        },
      },
      'required': ['project_path'],
    },
    handler: auditLocalization,
  );

  // Register assetgenie_app_harness tool
  server.addTool(
    name: 'assetgenie_app_harness',
    description:
        "Connects to a running Flutter application via its VM Service to inspect "
        "widgets, retrieve console logs, or capture live UI screenshots.",
    inputSchema: {
      'type': 'object',
      'properties': {
        'vm_service_uri': {
          'type': 'string',
          'description':
              'The Dart VM Service WebSocket or HTTP URI (e.g. http://127.0.0.1:8181/T9n3k_04gA=/).',
        },
        'action': {
          'type': 'string',
          'enum': ['get_widget_tree', 'capture_screenshot', 'get_logs'],
          'description':
              'The instrumentation action to perform on the running Flutter application.',
        },
      },
      'required': ['vm_service_uri', 'action'],
    },
    handler: appHarness,
  );

  try {
    final transport = FlutterMcpServer.createStdioTransport();
    server.connect(transport);
    stderr.writeln('AssetGenie MCP Server started successfully on stdio.');
  } catch (e) {
    stderr.writeln('Failed to start AssetGenie MCP Server: $e');
    exit(1);
  }
}
