library assetgenie;

import 'package:dart_mcp/server.dart';

import 'src/common/context.dart';
import 'src/tools/app_harness.dart';
import 'src/tools/audit_accessibility.dart';
import 'src/tools/audit_health.dart';
import 'src/tools/audit_localization.dart';
import 'src/tools/audit_variants.dart';
import 'src/tools/extract_strings.dart';
import 'src/tools/generate_constants.dart';
import 'src/tools/optimize_images.dart';
import 'src/tools/sync_localization.dart';
import 'src/tools/translate_localization.dart';

export 'src/common/arb.dart';
export 'src/common/context.dart';
export 'src/common/dart_scan.dart';
export 'src/common/project.dart';
export 'src/prompts/project_prompts.dart';
export 'src/resources/project_resources.dart';
export 'src/server/server.dart';
export 'src/tools/app_harness.dart';
export 'src/tools/audit_accessibility.dart';
export 'src/tools/audit_health.dart';
export 'src/tools/audit_localization.dart';
export 'src/tools/audit_variants.dart';
export 'src/tools/extract_strings.dart';
export 'src/tools/generate_constants.dart';
export 'src/tools/optimize_images.dart';
export 'src/tools/sync_localization.dart';
export 'src/tools/translate_localization.dart';

/// Extension providing backwards-compatible `toJson()` on MCP [Content].
extension ContentBackwardsCompat on Content {
  Map<String, Object?> toJson() {
    if (isText) {
      final t = this as TextContent;
      return {
        'type': 'text',
        'text': t.text,
      };
    }
    if (isImage) {
      final img = this as ImageContent;
      return {
        'type': 'image',
        'data': img.data,
        'mimeType': img.mimeType,
        'url': 'data:${img.mimeType};base64,${img.data}',
      };
    }
    return (this as dynamic) as Map<String, Object?>;
  }
}

// ---------------------------------------------------------------------------
// Backwards-compatible legacy function signatures for test/library callers
// ---------------------------------------------------------------------------

Future<CallToolResult> auditHealth(Map<String, dynamic> arguments) =>
    auditHealthHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> syncLocalization(Map<String, dynamic> arguments) =>
    syncLocalizationHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> generateConstants(Map<String, dynamic> arguments) =>
    generateConstantsHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> auditLocalization(Map<String, dynamic> arguments) =>
    auditLocalizationHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> appHarness(Map<String, dynamic> arguments) =>
    appHarnessHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> optimizeImages(Map<String, dynamic> arguments) =>
    optimizeImagesHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> extractStrings(Map<String, dynamic> arguments) =>
    extractStringsHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> auditVariants(Map<String, dynamic> arguments) =>
    auditVariantsHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> auditAccessibility(Map<String, dynamic> arguments) =>
    auditAccessibilityHandler(arguments, const HeadlessToolContext());

Future<CallToolResult> translateLocalization(Map<String, dynamic> arguments) =>
    translateLocalizationHandler(arguments, const HeadlessToolContext());
