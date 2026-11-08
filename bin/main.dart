import 'dart:io';

import 'package:assetgenie/assetgenie.dart';

void main() async {
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
