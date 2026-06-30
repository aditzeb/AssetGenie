// Compatibility file that references package:flutter_mcp_server
// This is not imported by the CLI binary to avoid transitive compile-time dependency on package:flutter (which fails on pure Dart VM due to missing dart:ui).
import 'package:flutter_mcp_server/flutter_mcp_server.dart';

void checkCompatibility() {
  print("flutter_mcp_server check: ${FlutterMcpServerConfig}");
}
